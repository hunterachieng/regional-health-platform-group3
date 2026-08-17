# Regional Health Platform — Group 3

Assignment 2 group platform repo: Terraform on LocalStack, RDS MySQL, Secrets Manager, CI gates, and observability for the Regional Health capacity lab.

**Team:** Hunter, Joyce, Lwam, Minage, Wairimu  
**Repo:** `git@github.com:hunterachieng/regional-health-platform-group3.git`

## Repos

| Repo | Purpose |
|------|---------|
| **This repo** | Shared modules, CI, conventions — group graded |
| [db-capacity-engineering-lab](https://github.com/hunterachieng/db-capacity-engineering-lab) | Assignment 1 individual work (journal, SCARS) |
| Personal repo / tfvars | Individual rehost evidence (if separate) |

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

## Cloud path (in progress)

```bash
make up       # stand stack from zero — Wairimu
make verify   # grader check — must pass before submit
```

Not implemented yet. See `TEAM_PLAN.md` for module ownership.

## Implemented so far

- [x] `api/secrets.js` — Secrets Manager at boot (+ `MYSQL_*` fallback for local)
- [x] `/healthz`, `/readyz`, `/debug/secret-source`
- [x] Docker compose with non-conflicting names/ports
- [ ] `terraform/modules/data` (Joyce)
- [ ] `terraform/modules/service` (Lwam)
- [ ] CI gates (Minage)
- [ ] `Makefile` / `make verify` (Wairimu)

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
