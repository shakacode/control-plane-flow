#!/usr/bin/env python3
"""Cross-runner deployment mutex. Interrupted owners retain their lock."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.request


class LockError(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class DeploymentLock:
    def __init__(self, org, app, owner, receipt):
        for value in (org, app):
            if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", value):
                raise LockError("The org and app must be valid Control Plane names.")
        if not owner or len(owner) > 200 or not owner.isprintable():
            raise LockError("A printable deployment owner of at most 200 characters is required.")
        self.org, self.app, self.owner = org, app, owner
        self.receipt = Path(receipt)
        self.name = "cpflow-deploy-lock-" + hashlib.sha256(app.encode()).hexdigest()[:32]
        self.path = f"/org/{org}/secret/{self.name}"

    def request(self, method, path, body=None):
        token = os.environ.get("CPLN_TOKEN", "")
        if not token:
            raise LockError("CPLN_TOKEN is required for deployment locking.")
        request = urllib.request.Request(
            "https://api.cpln.io" + path,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
            method=method,
        )
        try:
            opener = urllib.request.build_opener(NoRedirect())
            with opener.open(request, timeout=20) as response:
                expected = {"POST": 201, "GET": 200, "DELETE": 202}[method]
                if response.status != expected:
                    raise LockError(f"Lock {method} returned HTTP {response.status}; refusing to proceed.")
                return json.load(response) if method == "GET" else None
        except urllib.error.HTTPError as error:
            raise LockError(f"Lock {method} returned HTTP {error.code}; lock may be held or inaccessible.") from None
        except (OSError, ValueError):
            raise LockError(f"Lock {method} did not complete reliably; retain any existing lock.") from None

    def acquire(self):
        if self.receipt.exists():
            raise LockError("A lock receipt already exists; refusing to reuse another acquisition.")
        # POST creates only; apply/PUT would overwrite another runner's ownership.
        self.request("POST", f"/org/{self.org}/secret", {
            "name": self.name,
            "type": "opaque",
            "description": "Deployment mutex; stop the recorded owner before manual recovery.",
            "tags": {"cpflow/app": self.app, "cpflow/deploy-owner": self.owner},
            "data": {"encoding": "plain", "payload": "deployment mutex"},
        })
        current = self.request("GET", self.path)
        if (current.get("tags", {}).get("cpflow/app") != self.app
                or current.get("tags", {}).get("cpflow/deploy-owner") != self.owner
                or not isinstance(current.get("id"), str) or not current["id"]):
            raise LockError("Created lock ownership could not be verified; retain it for inspection.")
        receipt = {"org": self.org, "app": self.app, "owner": self.owner, "id": current["id"]}
        fd = os.open(self.receipt, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as handle:
            json.dump(receipt, handle)
        print("Acquired deployment lock for " + self.app, flush=True)

    def release(self):
        receipt = json.loads(self.receipt.read_text())
        if not isinstance(receipt.get("id"), str) or not receipt["id"]:
            raise LockError("Receipt has no verified resource identity; refusing to release.")
        if {key: receipt.get(key) for key in ("org", "app", "owner")} != {
                "org": self.org, "app": self.app, "owner": self.owner}:
            raise LockError("Receipt belongs to another deployment; refusing to release.")
        current = self.request("GET", self.path)
        if (current.get("id") != receipt.get("id")
                or current.get("tags", {}).get("cpflow/app") != self.app
                or current.get("tags", {}).get("cpflow/deploy-owner") != self.owner):
            raise LockError("Deployment lock ownership changed; refusing to release.")
        self.request("DELETE", self.path)
        self.receipt.unlink()
        print("Released deployment lock for " + self.app, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("operation", choices=("acquire", "release", "run"))
    parser.add_argument("--org", required=True)
    parser.add_argument("--app", required=True)
    parser.add_argument("--owner", required=True)
    parser.add_argument("--receipt", required=True)
    options, command = parser.parse_known_args()
    if options.operation == "run" and command[:1] != ["--"]:
        parser.error("run requires a command after --.")
    if command[:1] == ["--"]:
        command = command[1:]
    if (options.operation == "run") != bool(command):
        parser.error("Only run accepts a command, and it requires one after --.")
    lock = DeploymentLock(options.org, options.app, options.owner, options.receipt)
    if options.operation == "release":
        lock.release()
        return 0
    lock.acquire()
    if options.operation == "acquire":
        return 0
    try:
        result = subprocess.run(command, check=False)
    except BaseException:
        print("Deployment interrupted; retaining its lock for operator inspection.", file=sys.stderr)
        raise
    if result.returncode < 0:
        raise LockError("Deployment terminated by signal; retaining its lock for operator inspection.")
    lock.release()
    return result.returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (LockError, OSError, ValueError) as error:
        # API bodies, request headers and raw transport errors can contain credentials.
        message = str(error) if isinstance(error, LockError) else type(error).__name__
        print("Deployment lock failed: " + message, file=sys.stderr)
        sys.exit(1)
