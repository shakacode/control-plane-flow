# Migrating Postgres database from Heroku infrastructure

One of the biggest problems that will appear when moving from Heroku infrastructure is migrating the database. And
despite it being rather easy if done between Heroku-hosted databases or non-Heroku-hosted databases (as Postgres has
tools to do that naturally) it is not easily possible between Heroku and anything outside Heroku,
**as Heroku doesn't allow setting up WAL replication for Postgres**. Period. No... any... replication outside of
Heroku infrastructure for Postgres.

Previously, it was said to be possible to ask Heroku support to manually set up WAL log shipping, but they
don't want to do that anymore. Which leaves only 2 options:

### Option A: dump and restore way

Nothing problematic here in general **if you can withstand long application maintenance time**.
You basically need to:

1. enable maintenance
2. stop the application completely and wait for all the database writes to finish
3. dump database on Heroku
4. restore the database on RDS
5. start the application
6. disable maintenance

And if the database is small or it is a hobby app, this should not be looked any further.
However, this is not acceptable for 99% of production apps as their databases are huge and maintenance time
should be as small as possible.

Rough timing for a 1Tb database can be (but your mileage may vary):

- 2.5h creating Heroku backup
- 0.5h downloading backup to EC2
- 13h restoring a backup on RDS (in 4 threads)

**~16h total time, equals maintenance downtime**

### Option B: logical replication way

There are several logical replication solutions exist for Postgres - Slony, Bucardo, Londiste, Mimeo, but... when
you try to dig deeper, the only viable and up-to-date solution for purpose of migrating from Heroku to RDS is Bucardo.

The migration process with Bucardo looks as follows:

1. setup Bucardo on the dedicated EC2 instance
2. dump Heroku database schema and restore it on RDS - rather fast as there is no data
3. start Bucardo replication - this will install triggers and special schema to your database
4. wait for replication to catch up - this may take a long time, but the application can continue working as usual
5. enable maintenance
6. stop the application completely and wait for replication to finally finish
7. switch the database connection strings
8. start the application
9. disable maintenance

Maintenance downtime here can be minutes not hours or days like in p1, but no free lunches - the process is more complex.

Rough timing for a 1Tb database can be (but your mileage may vary):

- whatever setup time, no hurry
- 1.5 days for onetimecopy (in 1 thread) - DDL changes not allowed, but no downtime
- 1-2 min for database switch, maintenance downtime

**~2 days total time, ~1-2 min maintenance downtime**

### Some considerations:

- DDL changes should be "frozen and postponed" while Bucardo replication. There is also a way to stop replication,
update DDL in both databases, and restart replication, however, as well no-DDL for a day or two seems a
reasonable restriction for production databases vs potential errors.

- there is a "speed up" option to restore dump (with threads) and then run Bucardo to catch up only deltas, but it
looks unnecessary as speed gain is minimal vs potential errors. It will not speed up things dramatically, but will just
save a couple of hours of non-maintenance time (which most probably be spent on the command line) so not worth doing.

## Before replication

### Application code changes

Before everything, we need to recheck the database schema and ensure **that every table has a primary key (PK)
in place** as Bucardo is using PKs for replication.

> NOTE: theoretically Bucardo can work with uniq indexes as well, but having a PK on each table is easy and avoids
unnesessary complications

So, please stop, and do whatever is needed for your application.

### Choosing database location and EC2 location

All Heroku Postgres databases for location US are running in AWS on `us-east-1`. Control Plane, on the other side,
recommends `us-east-2` as a default. So we need to choose:

- either simple setup - main database in `us-east-2`
- or a bit more complex - main database in `us-east-2`, replica in `us-east-1` (which can be removed later)

This makes sense if your application supports working with replicas. Then read-only `SELECT` queries will go to the
read replica and write `INSERT/UPDATE` queries will go to the main write-enabled database.
This way we can keep most reading latency to the minimum.

Anyway, it is worth to consider developing such a mode in the application if you want to scale in more than 1 region.

### Create new EC2 instance which we will use for database replication

- better if it will be in the same AWS location where RDS database will be (most probably `us-east-2`)
- choose Ubuntu as OS
- use some bigger instance, e.g. `m6i.4xlarge` - price doesn't matter much, as such instance will not run long time
- if you will be copying backup via this instance, choose sufficient space for both OS and backup and some free space
- create security group `public-access` with all inbound and outbound traffic allowed. this will be handy as well for
database setup. if you need tighter access controls, up to you
- generate a new certificate and save it locally (e.g. `bucardo.pem`), will be used for SSH connection. Do not forget to
update correct permissions e.g. `chown TODO ~/Dowloads/bucardo.pem`

After the instance will be running on AWS, you can connect to it via SSH as follows:
```sh
ssh ubuntu@1.2.3.4 -i ~/Downloads/bucardo.pem
```

### Creating RDS instance

- check `public` box
- pick `public-access` security group (or whatever you need)
- if you will be restoring from backup, it is possible to choose temporary bigger instance e.g. `db.r6i.4xlarge`, which
can be downgraded later.
- if you will be using bucardo onetimecopy, then it is ok to select any instance you may need, as bucardo does copying
in a single thread
- it is fairly easy to switch database instance type afterwards and requires only minimal downtime
- storage space. this needs a good pick, as it is a) not possible to shrink and b) auto-expanding which AWS offers and
which should be enabled by default can block database modifications for quite long periods (days)

### Running commands in detached mode on the EC2 instance

Some commands that run on EC2 may take a long time and we may want to disconnect from the SSH session while the command
will continue running. And we want to reconnect to the session and see the progress. Possibly without installing
special tools. This can be accomplished with `screen` command, e.g.:

```sh
# this will start a backround process and return to terminal (which can be closed)
screen -dmL ...your command...

# checking if screen is still running in the background
ps aux | grep -i screen

# see the output log
cat screenlog.0
```

### Installing Postgres and Bucardo on EC2

Now, when RDS is running and EC2 is running we can start installing local Postgres and Bucardo itself. Let's install
Postgres 13 first. It may be possible to install the latest Postgres, but 13 seems the best choice atm.

```sh
# update all your packages
sudo apt update
sudo apt upgrade -y

# add postgres repository key
sudo sh -c 'echo "deb [arch=$(dpkg --print-architecture)] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

# update again
sudo apt-get update

# install packages
sudo apt-get -y install make postgresql-13 postgresql-client-13 postgresql-plperl-13 libdbd-pg-perl libdbix-safe-perl
```

Postgres Perl language `plperl` as well as DBD and DBIx packages are needed for Bucardo.

Now, as all dependencies are installed, we can install Bucardo from latest tarball.

```sh
# install Bucardo itself
wget https://bucardo.org/downloads/Bucardo-5.6.0.tar.gz
tar xzf Bucardo-5.6.0.tar.gz
cd Bucardo-5.6.0
perl Makefile.PL
sudo make install

# create dirs and fix permissions
sudo mkdir /var/run/bucardo
sudo mkdir /var/log/bucardo
sudo chown ubuntu /var/run/bucardo/
sudo chown ubuntu /var/log/bucardo
```

After that, Bucardo is physically installed as a package and runnable but we need to configure everything.
Let's start with Postgres. As this is a temporary installation (only for the period of replication),
it is rather safe to set `trust` localhost connections (or set up another way if you want this).


For this, we need to edit `pg_hba.conf` as follows:
```sh
# edit pg config to make postgres trusted
sudo nano /etc/postgresql/13/main/pg_hba.conf
```

in that file change the following lines to `trust`
```sh
# in pg_hba.conf
local   all             postgres                                trust
local   all             all                                     trust
```

and restart Postgres to pick up changes
```sh
# restart postgres
sudo systemctl restart postgresql
```

And finally-finally we can install Bucardo service database on local Postgres and see if everything runs.

```sh
# this will create local bucardo "service" database
bucardo install

# for option 3 pick `postgres` as a user
# for option 4 pick `postgres` as a database from where initial connection should be attempted
```

:tada: :tada: :tada: now we have local Postgres and Bucardo running, and can continue with external services
configuration.

### Configuring external (Heroku, RDS) database connections

For this, we will use `pg_service.conf`. It will not work in all places, and sometimes we will need to provide
connection properties manually, but for many commands, it is very useful.

```sh
# create and edit .pg_service.conf
touch ~/.pg_service.conf
nano ~/.pg_service.conf
```

```ini
# ~/.pg_service.conf

[heroku]
host=ec2-xxx.compute-1.amazonaws.com
port=5432
dbname=xxx
user=xxx
password=xxx

[rds]
host=xxx.us-east-2.rds.amazonaws.com
port=5432
dbname=xxx
user=postgres
password=xxx
```

Test connectivity to databases with:
```sh
psql service=heroku -c '\l+'
psql service=rds -c '\l+'
```

You will see all databases set up on each server (and can see their size):
```console
       Name        |  Owner   | Encoding |   Collate   |    Ctype    |   Access privileges   |   Size    | Tablespace |                Description
-------------------+----------+----------+-------------+-------------+-----------------------+-----------+------------+--------------------------------------------
 my-production-db  | xxx      | UTF8     | en_US.UTF-8 | en_US.UTF-8 |                       | 821 GB    | pg_default |
 postgres          | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 |                       | 8205 kB   | pg_default | default administrative connection database
 rdsadmin          | rdsadmin | UTF8     | en_US.UTF-8 | en_US.UTF-8 | rdsadmin=CTc/rdsadmin+| No Access | pg_default |
                   |          |          |             |             | rdstopmgr=Tc/rdsadmin |           |            |
 template0         | rdsadmin | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/rdsadmin          +| 8033 kB   | pg_default | unmodifiable empty database
                   |          |          |             |             | rdsadmin=CTc/rdsadmin |           |            |
 template1         | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +| 8205 kB   | pg_default | default template for new databases
                   |          |          |             |             | postgres=CTc/postgres |           |            |
(5 rows)
```

After both databases are connectable, we can proceed with replication itself.

## Performing replication

:fire: :fire: :fire: **IMPORTANT: from this step, DDL changes are not allowed** :fire: :fire: :fire:

### Application changes

- temporary freeze all DDL changes till replication will finish
- temporary disable all background jobs or services that are possible to stop. This will help to lessen database
load and especially, where possible, to decrease database write operations that will decrease replication pipe as well.

### Dump and restore the initial schema

This step doesn't take much time (as it is only a database schema without data),
but it is definitely handy to save all output, and closely check for any errors.

```sh
# save heroku schema to `schema.sql`
pg_dump service=heroku --schema-only --no-acl --no-owner -v > schema.sql

# restore `schema.sql` on RDS
psql service=rds < schema.sql
```

### Configure Bucardo replication

After we have all databases connectable and all same schema, we can tell Bucardo what it needs to replicate:
```sh
# add databases
bucardo add db from_db dbhost=xxx dbport=5432 dbuser=xxx dbpass=xxx dbname=xxx
bucardo add db to_db dbhost=xxx dbport=5432 dbuser=postgres dbpass=xxx dbname=xxx

# mark all tables and sequences for replication
bucardo add all tables
bucardo add all sequences
```
Here, Bucardo will connect to databases and collect object metadata for replication.
After that, we can add sync as well:

```sh
# add sync itself
bucardo add sync mysync tables=all dbs=from_db,to_db onetimecopy=1
```

The most important option here is `onetimecopy=1` which will tell Bucardo to perform initial data copying
(when sync will start). Such a copying is done *in a single thread* by creating a pipe (via Bucardo) as follows:
```SQL
-- on heroku
COPY xxx TO STDOUT
-- on rds
COPY xxx FROM STDIN
```

### Run sync

And now, when everything is ready, we can push the button and go for a long :coffee: or maybe even a weekend.

```sh
# starts Bucardo sync daemon
bucardo start
```

As well it is ok to disconnect from SSH as Bucardo daemon will continue working in background.

### Monitor status

To check the progress of sync (from Bucardo perspective):
```sh
# overall progress of all syncs
bucardo status

# single sync progress
bucardo status mysync
```

To check what's going on in databases directly:
```sh
# Bucardo adds a comment to it's queries, so it is fairly easy to grep those
psql service=heroku -c 'select * from pg_stat_activity' | grep -i bucardo
psql service=rds -c 'select * from pg_stat_activity' | grep -i bucardo
```

### After replication will catch up, but before databases switch

1. Please do a sanity check of data in tables. E.g. check:

- table `COUNT`
- min/max of PK ids where applicable
- min/max of `created_at/updated_at` where applicable

2. For p1 it is possible to use our checker script that will do this automatically (TODO)

3. Refresh materialized views manually (as they are not synced by Bucardo).
Just go to `psql` and `REFRESH MATERIALIZED VIEW ...`

## Switch databases

:fire: :fire: :fire: **This is final non reverisble step now** :fire: :fire: :fire:
Before this point, all changes can be easily removed or reversed and database can stay on Heroku as it was before,
afther this switch it is not possible (at least easily).

So... after sync will catch up, basically it is needed to:

1. start maintenance mode on heroku `heroku maintenance:on`
2. scale down and stop all the dynos
3. wait a bit for all queries to finish and replication catch up latest changes
4. detach heroku postgres from DATABASE_URL
5. set `DATABASE_URL` to RDS url (plaintext now)
6. start dynos
7. wait for their readiness with `heroku ps:wait`
8. stop maintenance with `heroku maintenance:off`
9. :fire: **Now we are fully on RDS, so DDL changes are allowed** :fire:
10. you could gradually enable all background jobs and services which were temporary stopped

## After switch

As we now running on RDS, there is only single task left to do on Heroku - make a final backup of database and save it.

```sh
# to capture backup (will take lots of time), can be disconnected
heroku pg:backups:capture -a example-app

# to get url of backup
heroku pg:backups:url bXXXX -a example-app
```

Now you can download it locally or copy to S3 via EC2 as it will take quite some time and traffic.

```sh
# download dump to EC2
screen -dmL time curl 'your-url' -o latest.dump

# install aws cli (in a way reccomended by Amazon)
# ...TODO...

# configure aws credentials
aws configure

# check S3 access
aws s3 ls

# upload to S3
screen -dmL time aws s3 cp latest.dump s3://my-dumps-bucket/ --region us-east-1
```

# Refs

https://bucardo.org

https://stackoverflow.com/questions/22264753/linux-how-to-install-dbdpg-module

https://gist.github.com/luizomf/1a7994cf4263e10dce416a75b9180f01

https://www.waytoeasylearn.com/learn/bucardo-installation/

https://gist.github.com/knasyrov/97301801733a31c60521

https://www.cloudnation.nl/inspiratie/blogs/migrating-heroku-postgresql-to-aurora-rds-with-almost-minimal-downtime

https://blog.porter.run/migrating-postgres-from-heroku-to-rds/

https://www.endpointdev.com/blog/2017/06/amazon-aws-upgrades-to-postgres-with/

https://aws.amazon.com/blogs/database/migrating-legacy-postgresql-databases-to-amazon-rds-or-aurora-postgresql-using-bucardo/
