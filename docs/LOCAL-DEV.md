# Local development — Group 3

How to run the app **today** (before `make up` / LocalStack exist).  
Requires **Node 22** and Docker.

---

## Ports (group repo vs A1)

This repo uses **different container names and host ports** so it can run alongside
`db-capacity-engineering-lab` on the same machine.

| Service | Container name | Host URL / port |
|---------|----------------|-----------------|
| API | `rh-g3-capacity-api` | http://localhost:**3010** |
| MySQL | `rh-g3-mysql-db` | localhost:**3308** |
| Mongo | `rh-g3-mongo-db` | localhost:**27018** |
| Prometheus | `rh-g3-prometheus` | http://localhost:**9091** |
| Grafana | `rh-g3-grafana` | http://localhost:**3003** (admin / admin) |

Inside the compose network, services still use names like `mysql-db` and `capacity-api`.

---

## Option A — Full stack with Docker (recommended)

```bash
cd ~/dev-ops/regional-health-platform-group3

docker compose up -d --build
docker compose exec capacity-api bash /usr/local/bin/seed.sh   # first time only
```

Health checks:

```bash
curl -i http://localhost:3010/healthz    # liveness  → 200
curl -i http://localhost:3010/readyz     # readiness → 200 when DB is up
curl -s http://localhost:3010/debug/secret-source
```

Stop:

```bash
docker compose down
```

---

## Option B — Run API on host (reuse A1 MySQL)

If A1 MySQL is already running on port **3307**:

```bash
cd api
nvm use          # Node 22 — see .nvmrc
npm install

PORT=3002 \
MYSQL_HOST=127.0.0.1 \
MYSQL_PORT=3307 \
MYSQL_USER=root \
MYSQL_PASSWORD=labpassword \
MYSQL_DATABASE=capacity_lab \
MONGO_URI=mongodb://127.0.0.1:27017 \
node server.js
```

```bash
curl http://localhost:3002/healthz
curl http://localhost:3002/readyz
```

If you see `EADDRINUSE`, something else is on that port:

```bash
lsof -i :3002
kill -9 <PID>
```

---

## Health endpoints (C4)

| Path | Meaning | Pass |
|------|---------|------|
| `GET /healthz` | Process alive | Always **200** while Node is running |
| `GET /readyz` | Can serve traffic | **200** if DB + secret OK; **503** otherwise |
| `GET /debug/secret-source` | Creds source (no password) | `{ "arn": "...", "versionId": "..." }` |

**Test readiness failure** (for `evidence/04-health/readyz-degraded.txt`):

1. Start API with wrong `MYSQL_PASSWORD` → `/healthz` still 200, `/readyz` → 503  
2. Or `docker stop rh-g3-mysql-db` → `/readyz` → 503, then restart and recover

Local fallback (no Secrets Manager): boot log shows `secret arn=env`.

---

## Load tests (k6)

Default base URL is **3010** (group Docker API):

```bash
k6 run load-tests/00-baseline.js
# or explicitly:
k6 run -e BASE_URL=http://localhost:3010 load-tests/reproduce-OPS-2201.js
```

For API on host port 3002:

```bash
k6 run -e BASE_URL=http://localhost:3002 load-tests/00-baseline.js
```

---

## Secrets Manager (after Joyce's module + LocalStack)

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL=http://localhost:4566
export DB_SECRET_ARN=arn:aws:secretsmanager:...
```

Boot log should show `DB credentials loaded from Secrets Manager arn=... version=...`  
and `/debug/secret-source` returns the real ARN (not `env`).

---

## Cloud deploy (later)

```bash
make up       # Wairimu — not implemented yet
make verify   # checks healthz, readyz, gitleaks, empty terraform plan
```

See `ASSIGNMENT-A2.md` and `TEAM_PLAN.md` for full deliverables.
