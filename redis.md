# Migrating Redis database from Heroku infrastructure

**General considerations:**

1. Heroku uses self-signed TLS certificates, which are not verifiable. It needs special handling by setting
TLS verification to `none`, otherwise most apps are not able to connect.

2. We are moving to private Redis that don't have a public URL, so have to do it from a Control Plane GVC container.

The tool that satisfies those criteria is [Redis-RIOT](https://developer.redis.com/riot/riot-redis/index.html)

**Heroku Redis:**

As Redis-RIOT says, master redis should have keyspace-notifications set to `KA` to be able to do live replication.
To do that:

```sh
heroku redis:keyspace-notifications -c KA -a my-app
```

Connect to heroku Redis CLI:
```sh
heroku redis:cli -a my-app
```

**Control Plane Redis:**

Connect to Control Plane Redis CLI:

```sh
# open cpl interactive shell
cpl run bash -a my-app

# install redis CLI if you don't have it in Docker
apt-get update
apt-get install redis -y

# connect to local cloud Redis
redis-cli -u MY_CONTROL_PLANE_REDIS_URL
```

**Useful Redis CLI commands:**

Quick-check keys qty:
```
info keyspace

# Keyspace
db0:keys=9496,expires=2941,avg_ttl=77670114535
```

**Create a Control Plane sync workload**

```
name: riot-redis

suspend: true
min/max scale: 1/1

firewall: all firewalls off

image: fieldengineering/riot-redis

CPU: 1 Core
RAM: 1 GB

command args:
  --info
  -u
  rediss://...your_heroku_redis_url...
  --tls-verify=NONE
  replicate
  -h
  ...your_control_plane_redis_host...
  --mode
  live
```

**Sync process**

1. open 1st terminal window with heroku redis CLI, check keys qty
2. open 2nd terminal window with controlplane redis CLI, check keys qty
3. start sync container
4. open logs with `cpl logs -a my-app -w riot-redis`
4. re-check keys sync qty again
5. stop sync container

Result:
```
Setting commit interval to default value (1)
Setting commit interval to default value (1)
Job: [SimpleJob: [name=snapshot-replication]] launched with the following parameters: [{}]
Executing step: [snapshot-replication]
Scanning   0% ╺━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━    0/8891 (0:00:00 / ?)Job: [SimpleJob: [name=scan-reader]] launched with the following parameters: [{}]
Executing step: [scan-reader]
Scanning  61% ━━━━━━━━━━━━━━━━╸━━━━━━━━━━ 5460/8891 (0:00:07 / 0:00:04) 780.0/sStep: [scan-reader] executed in 7s918ms
Closing with items still in queue
Job: [SimpleJob: [name=scan-reader]] completed with the following parameters: [{}] and the following status: [COMPLETED] in 7s925ms
Scanning 100% ━━━━━━━━━━━━━━━━━━━━━━━━━━━ 9482/9482 (0:00:11 / 0:00:00) 862.0/s
Step: [snapshot-replication] executed in 13s333ms
Executing step: [verification]
Verifying   0% ╺━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━    0/8942 (0:00:00 / ?)Job: [SimpleJob: [name=RedisItemReader]] launched with the following parameters: [{}]
Executing step: [RedisItemReader]
Verifying   2% ╺━━━━━━━━━━━━━━━━━  220/8942 (0:00:00 / 0:00:19) ?/s >0 T0 ≠Step: [RedisItemReader] executed in 7s521ms
Closing with items still in queue
Job: [SimpleJob: [name=RedisItemReader]] completed with the following parameters: [{}] and the following status: [COMPLETED] in 7s522ms
Verification completed - all OK
Step: [verification] executed in 7s776ms
Job: [SimpleJob: [name=snapshot-replication]] completed with the following parameters: [{}] and the following status: [COMPLETED] in 21s320ms
```

Total sync time ~1min
