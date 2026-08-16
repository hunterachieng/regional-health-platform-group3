# Regional Health Platform — Group 3

Assignment 2 group platform repo: Terraform on LocalStack, RDS MySQL, Secrets Manager, CI gates, and observability for the Regional Health capacity lab.

**Team:** Hunter, Joyce, Lwam, Minage, Wairimu

## Repos

| Repo | Purpose |
|------|---------|
| **This repo** (`regional-health-platform-group3`) | Shared modules, CI, conventions — group graded |
| [db-capacity-engineering-lab](https://github.com/hunterachieng/db-capacity-engineering-lab) | Hunter's Assignment 1 individual work (journal, SCARS, A1 evidence) |
| Each member's fork / individual repo | Individual rehost deploy + personal evidence (if separate from group) |

**Clone (team):**

```bash
git clone git@github.com:hunterachieng/regional-health-platform-group3.git
cd regional-health-platform-group3
```

## Local folder layout (Hunter's machine)

```
~/dev-ops/
├── db-capacity-engineering-lab/          # A1 individual repo (keep as-is)
└── regional-health-platform-group3/    # A2 group repo (this project)
```

## Before you start

1. Read `ASSIGNMENT-A2.md` and `TEAM_PLAN.md`
2. LocalStack Hobby token → `LOCALSTACK_AUTH_TOKEN` (shell + GitHub Actions secret)
3. Use **Codespace 4-core / 16 GB** or Linux VM — not Mac Docker Desktop
4. Fill your row in `CONTRIBUTIONS.md` as PRs merge

## Quick start (when implemented)

```bash
make up      # stand stack from zero
make verify  # grader check — must pass before submit
```

## What each folder is

| Path | Owner | Notes |
|------|-------|-------|
| `terraform/modules/data/` | Joyce | RDS + Secrets Manager |
| `terraform/modules/service/` | Lwam | EC2 + nginx + ALB IaC |
| `terraform/environments/*.tfvars` | Each person | Individual deploy vars |
| `.github/workflows/` | Minage | gitleaks, trivy, zizmor |
| `Makefile`, bootstrap | Wairimu | `make up`, `make verify` |
| `api/secrets.js`, health endpoints | Hunter | C3 + C4 |
| `evidence/` | Everyone | A2 artifacts — see `evidence/README.md` |
| `load-tests/`, `monitoring/` | From A1 | Incident replay + alerts |

## Individual naming

Use per-person tfvars under `terraform/environments/`:

```
hunter.tfvars
joyce.tfvars
lwam.tfvars
minage.tfvars
wairimu.tfvars
```

Apply example (once root module exists):

```bash
terraform apply -var-file=terraform/environments/hunter.tfvars
```

## Links

- Assignment brief: `ASSIGNMENT-A2.md`
- Task breakdown: `TEAM_PLAN.md`
- LocalStack fidelity notes: `FIDELITY.md`
- PR authorship log: `CONTRIBUTIONS.md`
