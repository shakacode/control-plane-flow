"""Offline deployment-lock behavior; no Control Plane credentials or resources."""

import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

SOURCE = Path(__file__).resolve().parents[1] / ".github/scripts/deployment_lock.py"
SPEC = importlib.util.spec_from_file_location("deployment_lock", SOURCE)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LockTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.resources = {}
        self.calls = []
        self.resource_id = 0
        self.api = patch.object(MODULE.DeploymentLock, "request", autospec=True, side_effect=self.request)
        self.mock_api = self.api.start()
        self.addCleanup(self.api.stop)

    def lock(self, owner="circleci:one", app="sample-review-42"):
        receipt = Path(self.directory.name) / (owner.replace(":", "-") + ".json")
        return MODULE.DeploymentLock("sample-staging", app, owner, receipt)

    def request(self, lock, method, path, body=None):
        self.calls.append((method, path, body))
        if method == "POST":
            key = path + "/" + body["name"]
            if key in self.resources:
                raise MODULE.LockError("Lock already exists")
            self.resource_id += 1
            self.resources[key] = {"id": str(self.resource_id), "tags": body["tags"]}
        elif method == "GET":
            return self.resources[path]
        elif method == "DELETE":
            del self.resources[path]
        else:
            self.fail("Unexpected API method")

    def test_only_one_provider_enters_until_owner_releases(self):
        first, second = self.lock(), self.lock("github:two")
        first.acquire()
        with self.assertRaises(MODULE.LockError):
            second.acquire()
        self.assertFalse(second.receipt.exists())
        self.assertEqual(self.calls[0][0], "POST")
        first.release()
        second.acquire()
        self.assertEqual(self.resources[second.path]["tags"]["cpflow/deploy-owner"], second.owner)

    def test_different_apps_can_deploy_independently(self):
        first, second = self.lock(), self.lock("github:two", "sample-review-43")
        first.acquire()
        second.acquire()
        self.assertEqual(len(self.resources), 2)

    def test_replaced_resource_or_changed_owner_cannot_be_released(self):
        for field, value in (("id", "another-resource"), ("owner", "github:replacement")):
            with self.subTest(field=field):
                self.resources.clear()
                lock = self.lock(field)
                lock.acquire()
                if field == "id":
                    self.resources[lock.path]["id"] = value
                else:
                    self.resources[lock.path]["tags"]["cpflow/deploy-owner"] = value
                with self.assertRaises(MODULE.LockError):
                    lock.release()
                self.assertIn(lock.path, self.resources)
                self.assertTrue(lock.receipt.exists())

    def test_read_failure_after_creation_retains_lock_without_a_receipt(self):
        lock = self.lock()
        def response(instance, method, path, body=None):
            if method == "GET":
                raise MODULE.LockError("Read failed")
            return self.request(instance, method, path, body)
        self.mock_api.side_effect = response
        with self.assertRaises(MODULE.LockError):
            lock.acquire()
        self.assertIn(lock.path, self.resources)
        self.assertFalse(lock.receipt.exists())

    def command_args(self, lock):
        return ["deployment_lock.py", "run", "--org", lock.org, "--app", lock.app,
                "--owner", lock.owner, "--receipt", str(lock.receipt), "--", "deployment-command"]

    def run_command(self, result):
        lock = self.lock()
        with patch.object(sys, "argv", self.command_args(lock)), \
                patch.object(MODULE.subprocess, "run", side_effect=result):
            return MODULE.main(), lock

    def test_normal_command_failure_releases_and_preserves_exit_status(self):
        result, lock = self.run_command(lambda *args, **kwargs: subprocess.CompletedProcess(args, 7))
        self.assertEqual(result, 7)
        self.assertFalse(self.resources)
        self.assertFalse(lock.receipt.exists())

    def test_interrupted_command_retains_lock(self):
        with self.assertRaises(KeyboardInterrupt):
            self.run_command(KeyboardInterrupt())
        self.assertEqual(len(self.resources), 1)

    def test_failed_acquisition_never_runs_the_command(self):
        first = self.lock()
        first.acquire()
        contender = self.lock("github:two")
        with patch.object(sys, "argv", self.command_args(contender)), \
                patch.object(MODULE.subprocess, "run") as command:
            with self.assertRaises(MODULE.LockError):
                MODULE.main()
            command.assert_not_called()

    def test_signaled_child_retains_lock(self):
        with self.assertRaises(MODULE.LockError):
            self.run_command(lambda *args, **kwargs: subprocess.CompletedProcess(args, -15))
        self.assertEqual(len(self.resources), 1)

    def test_release_failure_retains_receipt_and_blocks_completion(self):
        def response(instance, method, path, body=None):
            if method == "DELETE":
                raise MODULE.LockError("Delete did not complete reliably")
            return self.request(instance, method, path, body)
        self.mock_api.side_effect = response
        with self.assertRaises(MODULE.LockError):
            self.run_command(lambda *args, **kwargs: subprocess.CompletedProcess(args, 0))
        self.assertEqual(len(self.resources), 1)
        self.assertTrue(self.lock().receipt.exists())

    def test_unverified_or_foreign_receipt_is_rejected_before_any_api_call(self):
        lock = self.lock()
        lock.receipt.write_text(json.dumps({"org": lock.org, "app": lock.app, "owner": lock.owner}))
        with self.assertRaises(MODULE.LockError):
            lock.release()
        self.assertFalse(self.calls)

    def test_digit_prefixed_resource_names_acquire_and_release(self):
        for org, app in (("1", "2"), ("1-org", "2-review-42")):
            with self.subTest(org=org, app=app):
                lock = MODULE.DeploymentLock(org, app, "github:one", Path(self.directory.name) / app)
                lock.acquire()
                lock.release()
                self.assertFalse(self.resources)
                self.assertFalse(lock.receipt.exists())


class TransportTests(unittest.TestCase):
    def test_token_is_passed_only_in_header_and_api_error_bodies_are_suppressed(self):
        lock = MODULE.DeploymentLock("sample-staging", "sample-review-42", "github:one", "unused")
        error = urllib.error.HTTPError("https://api.cpln.io", 403, "private response", {}, io.BytesIO(b"secret-token"))
        with patch.dict("os.environ", {"CPLN_TOKEN": "secret-token"}), \
                patch.object(MODULE.urllib.request, "build_opener") as build:
            build.return_value.open.side_effect = error
            with self.assertRaises(MODULE.LockError) as failure:
                lock.request("POST", "/org/sample-staging/secret", {"name": lock.name})
            request = build.return_value.open.call_args.args[0]
            self.assertEqual(request.get_header("Authorization"), "Bearer secret-token")
            self.assertEqual(request.full_url, "https://api.cpln.io/org/sample-staging/secret")
            self.assertNotIn("secret-token", str(failure.exception))
            self.assertNotIn("private response", str(failure.exception))


if __name__ == "__main__":
    unittest.main()
