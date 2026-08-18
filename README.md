# Regional Health Platform — Group 3

Assignment 2 group platform repo: Terraform on LocalStack, RDS MySQL, Secrets Manager, CI gates, and observability for the Regional Health capacity lab.

**Team:** Hunter, Joyce, Lwam, Minage, Wairimu  
**Repo:** `git@github.com:hunterachieng/regional-health-platform-group3.git`

## Repos — A1 vs A2

| Repo | Assignment | What's there |
|------|------------|--------------|
| [db-capacity-engineering-lab](https://github.com/hunterachieng/db-capacity-engineering-lab) | **A1 (individual)** | Incident investigation, fixes, `LAB_JOURNAL.md`, `SCARS.md` |
| **This repo** | **A2 (group + individual rehost)** | Terraform modules, CI, secrets/health wiring, per-person deploy + `evidence/` |

A1 taught how the service breaks; A2 rehosts it with guardrails. The same app and k6 scripts live here — you do **not** run A2 from the A1 repo.

### Individual submission links (Hunter)

| | Link |
|---|------|
| **A1** — fixes & investigation | https://github.com/hunterachieng/db-capacity-engineering-lab |
| **A2** — deploy & evidence | https://github.com/hunterachieng/regional-health-platform-group3 (branch `hunter/fix-runs`) |
| **Individual deploy** | `make up NAME=hunter` → evidence under `evidence/` |
| **Aiven DB seed** | `./data-seed/migrate-aiven.sh hunter` |

## Prerequisites

- **Node 22** (`cd api && nvm use` — see `api/.nvmrc`)
- **Docker** + Docker Compose
- **LocalStack Hobby token** → `LOCALSTACK_AUTH_TOKEN` (for cloud path; see `ASSIGNMENT-A2.md`)
- **Codespace 4-core / 16 GB** or Linux VM for LocalStack EC2 work (not Mac Docker Desktop)

## Run locally (now)

**Full guide:** [docs/LOCAL-DEV.md](./docs/LOCAL-DEV.md)

```bash
git clone git@github.com:hunterachieng/regional-health-platform-group3.git
cd regional-health-platform-group3

docker compose up -d --build
docker compose exec capacity-api bash /usr/local/bin/seed.sh   # first time

curl http://localhost:3010/healthz
curl http://localhost:3010/readyz
```

| Service | URL |
|---------|-----|
| API | http://localhost:**3010** |
| Grafana | http://localhost:**3003** |
| Prometheus | http://localhost:**9091** |

Host ports differ from the A1 repo so **both stacks can run on one machine** (`rh-g3-*` container names).

## Cloud path (LocalStack + Aiven)

```bash
export LOCALSTACK_AUTH_TOKEN='ls-...'   # personal Hobby token
docker run -d --name localstack-main --privileged \
  -e LOCALSTACK_AUTH_TOKEN -e EC2_VM_MANAGER=docker \
  -e SERVICES=ec2,secretsmanager,s3,dynamodb \
  -v /var/run/docker.sock:/var/run/docker.sock -p 4566:4566 \
  localstack/localstack:latest

make up NAME=hunter
make verify NAME=hunter
```

See [FIDELITY.md](./FIDELITY.md) for LocalStack caveats (RDS/ALB Hobby limits → Aiven MySQL; EC2 VM fidelity on Codespaces).

## Implemented so far

- [x] `api/secrets.js` — Secrets Manager at boot (+ `MYSQL_*` fallback for local)
- [x] `/healthz`, `/readyz`, `/debug/secret-source`
- [x] Docker compose + Prometheus alert rules (`monitoring/alert-rules.yml`)
- [x] `terraform/modules/data` — Secrets Manager + Aiven credentials
- [x] `terraform/modules/service` — EC2 + nginx IaC
- [x] `Makefile` / bootstrap / `make up`
- [ ] CI gates (Minage) — in progress

## Docs

| File | Purpose |
|------|---------|
| [docs/LOCAL-DEV.md](./docs/LOCAL-DEV.md) | How to run and test health today |
| [ASSIGNMENT-A2.md](./ASSIGNMENT-A2.md) | Full brief |
| [TEAM_PLAN.md](./TEAM_PLAN.md) | Task breakdown + PR owners |
| [CONTRIBUTIONS.md](./CONTRIBUTIONS.md) | Who authored/reviewed module PRs |
| [FIDELITY.md](./FIDELITY.md) | LocalStack caveats |
| [evidence/README.md](./evidence/README.md) | Evidence bundle layout |

## Individual deploy naming

Copy `terraform/environments/hunter.tfvars.example` → `hunter.tfvars` (gitignored) and adjust per person.
