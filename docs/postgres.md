# Migrating PostgreSQL from Heroku to RDS

This guide covers a database move from Heroku Postgres to AWS RDS using dump and
restore or Bucardo replication. Rehearse the chosen method with your database before
scheduling a production cutover.

For other PostgreSQL tasks, use these guides:

- [PostgreSQL for disposable review apps](./postgres-review-apps.md): create and
  clean up review-app helpers.
- [Private RDS/Aurora networking](./rds-private-networking.md): connect Control Plane
  workloads through the Cloud Wormhole agent.
- [Control Plane PostgreSQL Template Catalog](https://shakadocs.controlplane.com/template-catalog/templates/postgres):
  run PostgreSQL on Control Plane with persistent storage and optional backups.

## Choose a migration method

| Method | Application downtime | Main tradeoff |
| --- | --- | --- |
| Dump and restore | Writers stay stopped through the final dump and restore | Fewer moving parts; downtime grows with database size |
| Bucardo replication | Writers stop for the final catch-up and connection switch | More setup; the initial copy runs while the app stays online |

Bucardo uses triggers to copy data and replicate later changes. It needs permission
to install its objects on the source database. Confirm that your Heroku plan and
target database support the required permissions before choosing it.

Do not treat example timings as a downtime guarantee. Measure backup, restore, and
replication performance during a rehearsal. For background on the trigger-based
approach, see [AWS's Bucardo migration example](https://aws.amazon.com/blogs/database/migrating-legacy-postgresql-databases-to-amazon-rds-or-aurora-postgresql-using-bucardo/).

## Prepare the databases and network

Before either migration method:

1. Inventory database versions, extensions, storage, and every application or job
   that writes to the database.
2. Create the RDS database with compatible schema support and enough storage for
   the data and expected growth.
3. Establish connectivity from the migration host and the application's eventual
   deployment location. Prefer private networking; see the
   [RDS/Aurora networking guide](./rds-private-networking.md).
4. Restrict security groups to the hosts and ports that need access. If temporary
   public access is necessary, restrict it to the migration host and remove it afterward.
5. Take a source backup and agree on validation, cutover, and rollback criteria.

For Bucardo, also check that each replicated table has a primary key. Freeze schema
changes from the schema copy through cutover. Plan separately for objects Bucardo
does not replicate, including materialized views.

### Set up a migration host

Use a temporary host, such as an EC2 instance, that can reach both databases. Choose
its region, capacity, and disk space based on measured latency and copy requirements.
Restrict SSH access and protect the private key:

```sh
chmod 600 ~/Downloads/bucardo.pem
ssh -i ~/Downloads/bucardo.pem ubuntu@MIGRATION_HOST
```

Run long foreground operations in a detachable session such as `screen`, and save
logs so you can inspect errors after reconnecting.

### Install database tools

Install PostgreSQL clients compatible with the source and target versions. Follow
the [PostgreSQL installation instructions](https://www.postgresql.org/download/)
and [supported-version policy](https://www.postgresql.org/support/versioning/).

For replication, install Bucardo and its dependencies using the
[Bucardo installation guide](https://bucardo.org/Bucardo/Installation/) and
[requirements](https://bucardo.org/Bucardo/installation/requirements). Bucardo needs
a local PostgreSQL database for its control metadata, plus Perl database modules
and the required PostgreSQL procedural languages.

Configure authenticated local access to that control database, then initialize it:

```sh
bucardo install
```

Test your chosen versions and authentication settings during rehearsal. The steps
below describe the replication flow; they do not replace Bucardo's installation guide.

### Configure source and target connections

Create `~/.pg_service.conf` on the migration host. Replace the placeholders with
credentials for the source and target databases:

```ini
[heroku]
host=HEROKU_HOST
port=5432
dbname=SOURCE_DATABASE
user=SOURCE_USER
password=SOURCE_PASSWORD
sslmode=require

[rds]
host=RDS_HOST
port=5432
dbname=TARGET_DATABASE
user=TARGET_USER
password=TARGET_PASSWORD
sslmode=require
```

Protect this file and confirm that both connections work. Use your provider's
certificate settings if your environment requires server identity verification.

```sh
chmod 600 ~/.pg_service.conf
psql service=heroku -c 'SELECT current_database();'
psql service=rds -c 'SELECT current_database();'
```

## Option A: dump and restore

For a migration that can tolerate the measured restore time:

1. Enable maintenance mode and stop **all database writers**, including background
   jobs and external services. Maintenance mode alone does not stop writes.
2. Wait for active writes to finish, then create and download the final source dump.
3. Restore the dump into RDS and check every restore error.
4. Validate the target data and application connection.
5. Follow the [cutover steps](#switch-the-application-to-rds) below.

Keep writers stopped throughout the final dump and restore. The
[Heroku PGBackups guide](https://devcenter.heroku.com/articles/heroku-postgres-backups)
covers backup capture and download; choose and rehearse a restore procedure suitable
for your dump format and database size.

## Option B: Bucardo replication

### Copy the schema

Freeze DDL changes and reduce avoidable write traffic. Copy the source schema into
the empty target database, retaining logs and checking for errors:

```sh
pg_dump service=heroku --schema-only --no-acl --no-owner -v > schema.sql
psql --single-transaction -v ON_ERROR_STOP=1 -f schema.sql service=rds
```

The restore runs in one transaction and rolls back on error. Investigate any
unsupported extensions or other schema incompatibilities before retrying.

### Configure the sync

Register the source and target with Bucardo. Replace the named placeholders with
the connection values for each database. These commands contain credentials; protect your terminal
history and any logs that capture them.

```sh
bucardo add db from_db dbhost=HEROKU_HOST dbport=5432 dbuser=SOURCE_USER dbpass=SOURCE_PASSWORD dbname=SOURCE_DATABASE
bucardo add db to_db dbhost=RDS_HOST dbport=5432 dbuser=TARGET_USER dbpass=TARGET_PASSWORD dbname=TARGET_DATABASE

bucardo add all tables db=from_db --relgroup=migration
bucardo add all sequences db=from_db --relgroup=migration
bucardo add sync mysync relgroup=migration dbs=from_db:source,to_db:target onetimecopy=1
```

Inspect the registered tables, sequences, and source/target roles before starting.
See the [Bucardo tutorial](https://bucardo.org/Bucardo/pgbench_example) for its
registration and inspection commands.
The `onetimecopy=1` setting requests an initial data copy, followed by replication
of subsequent changes.

### Start and monitor replication

```sh
bucardo start
bucardo status
bucardo status mysync
```

Bucardo runs as a daemon. You can disconnect from SSH and reconnect to inspect its
status and logs. To inspect its database activity:

```sh
psql service=heroku -c 'SELECT * FROM pg_stat_activity' | grep -i bucardo
psql service=rds -c 'SELECT * FROM pg_stat_activity' | grep -i bucardo
```

Wait for the initial copy to finish and investigate replication errors. Keep schema
changes frozen until cutover completes.

### Validate before cutover

Compare source and target data with checks suited to the application:

- Row counts and representative records.
- Minimum and maximum primary keys or timestamps, where meaningful.
- Sequence values and application-specific invariants.
- Objects outside replication, including refreshed materialized views.

Checks taken while writes continue can differ. Repeat the final validation after
stopping writers and waiting for replication to catch up.

## Switch the application to RDS

Rehearse these steps with the application's deployment process. If you are also
moving the app to Control Plane, prepare its database secret and workloads before
the cutover window.

1. Enable maintenance mode. For a Heroku-hosted app, use `heroku maintenance:on -a APP`.
2. Stop all writers: web dynos, workers, scheduled jobs, and external services.
3. Wait for active writes to finish. With Bucardo, wait for the final replication
   catch-up and verify the target again.
4. Save the old connection configuration and add-on attachment details for recovery.
   For a Heroku-hosted app, detach the attachment that owns `DATABASE_URL` before
   setting the RDS connection. For classic Heroku Postgres, this is typically
   `heroku addons:detach DATABASE -a APP`; confirm the attachment name first.
   Advanced databases use a different attachment command. See the
   [Heroku CLI attachment reference](https://devcenter.heroku.com/articles/heroku-cli-commands#heroku-addons-detach-attachment_name)
   and [database-type-specific credential instructions](https://devcenter.heroku.com/articles/heroku-postgresql-credentials#detach-a-credential).
   Keep the source database itself; do not destroy the add-on.
5. With Bucardo, stop replication with `bucardo stop` after the final catch-up,
   before any application writes reach RDS. Confirm that the sync has stopped and
   keep source writers disabled.
6. Update the app's database connection to RDS using its deployment secret/configuration
   mechanism.
7. Start the application and check readiness, database connectivity, and key operations.
   For Heroku dynos, `heroku ps:wait -a APP` can check process readiness.
8. End maintenance only after those checks pass. On Heroku, use `heroku maintenance:off -a APP`.
9. Resume background jobs and scheduled writers. Lift the schema freeze once
   replication is no longer needed.

**Rollback boundary:** before RDS accepts new application writes, the source can
remain the authoritative database. After new writes reach RDS, switching back to
Heroku requires a data reconciliation plan; changing the connection string alone
would lose those writes.

## Finish the migration

1. Retain a final Heroku backup according to your recovery policy. Keep the source
   available until the agreed recovery window closes.
2. Verify RDS backups, monitoring, storage, and application performance.
3. Remove Bucardo's temporary replication objects when they are no longer needed,
   following its cleanup procedure. Do not restart the old sync against the live target.
4. Remove temporary network access, migration credentials, and the migration host.

To capture and locate a final Heroku backup, use a remaining source attachment or
add-on identifier for `SOURCE_ADDON`:

```sh
heroku pg:backups:capture SOURCE_ADDON -a APP
heroku pg:backups:url BACKUP_ID -a APP
```

Download it to protected storage. If your retention destination is S3, use your
normal AWS credentials and bucket policy to upload the dump. Verify the stored
backup before removing the source database.
