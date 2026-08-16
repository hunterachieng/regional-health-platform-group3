# Assignment 2 — Team Plan

**Team:** Hunter, Joyce, Lwam, Minage, Wairimu  
**Due:** Wednesday 19 August 2026, 09:00 EAT  
**Group repo:** `git@github.com:hunterachieng/regional-health-platform-group3.git`  
**Brief:** `ASSIGNMENT-A2.md` in this repo

## Repo layout on disk

```
~/dev-ops/
├── db-capacity-engineering-lab/          # A1 individual (journal, SCARS — do not merge here)
└── regional-health-platform-group3/      # A2 group platform (this repo)
```

**Clone for teammates:**

```bash
git clone git@github.com:hunterachieng/regional-health-platform-group3.git
cd regional-health-platform-group3
```

Add all five members as **Collaborators** (Write) on GitHub. Each person adds their own `LOCALSTACK_AUTH_TOKEN` as a GitHub Actions secret on this repo (personal Hobby tokens — do not share).

Assignment 1 taught us how the service breaks. Assignment 2 makes it safe to run and change — Terraform on LocalStack, RDS MySQL, Secrets Manager, CI gates that actually block, and observability that catches the same four bugs in a cloud-shaped environment.

---

## How grading splits

| Half | What | Graded on |
|------|------|-----------|
| **Group (platform)** | `modules/data`, `modules/service`, golden CI, bootstrap, conventions | Module quality, pipeline, **git PR authorship + reviews** |
| **Individual (rehost)** | Your root Terraform, deploy, alerts, incident replay, red PRs, evidence | Your service standing up green, your artifacts |

**Anti-free-rider rule:** Every member must **author ≥1 module/platform PR** and **approve ≥2 others**. `CONTRIBUTIONS.md` is a summary — git history is the evidence.

**If a group module slips:** fork it, document the divergence in your README, carry on. No individual penalty for a teammate's delay.

---

## Role assignments

| Person | Group ownership (author PR) | Primary reviews | Individual focus |
|--------|----------------------------|-----------------|------------------|
| **Joyce** | `terraform/modules/data` (RDS + Secrets Manager) | Lwam, Minage | Alerts for OPS-2201 + OPS-2203, replay evidence |
| **Lwam** | `terraform/modules/service` (EC2 + nginx + ALB IaC + user-data) | Joyce, Hunter | Alerts for OPS-2202 + OPS-2204, **Loom walk-through** |
| **Minage** | Golden CI workflow (gitleaks → trivy → zizmor → build → apply) | Wairimu, Joyce | 3 red PRs (one per gate) + `evidence/05-gates/README.md` |
| **Wairimu** | Bootstrap (S3 state + DynamoDB lock) + `Makefile` + `make verify` | Minage, Lwam | Seed/migrate (`02-data/`), `FIDELITY.md` |
| **Hunter** | Repo conventions (evidence layout, `.gitignore`, pre-commit gitleaks hook) + app boot wiring | Minage, Wairimu | `api/secrets.js`, `/healthz` `/readyz`, root Terraform, full deploy |

---

## PR review matrix

| Author | PR topic | Reviewer 1 | Reviewer 2 |
|--------|----------|------------|------------|
| Joyce | `modules/data` | Lwam | Minage |
| Lwam | `modules/service` | Joyce | Hunter |
| Minage | Golden CI workflow | Wairimu | Joyce |
| Wairimu | Makefile + bootstrap + verify | Minage | Lwam |
| Hunter | Conventions + app boot wiring | Minage | Wairimu |

---

## Architecture (target)

```
GitHub Actions (per PR, LocalStack runs inside the runner)
  gitleaks → trivy config → zizmor → docker build → trivy image
                                                          │
                                                          ▼
                                            tag as AMI: localstack-ec2/app:ami-<sha12>
                                                          │
                                                          ▼
                                                    tflocal apply
                                                          │
        ┌─────────────────────────────────────────────────┘
        ▼
   EC2 instance (Docker-backed, Ubuntu 22.04 AMI)
     ├─ nginx  ──▶ app  (/healthz  /readyz  /metrics)
     └─ user-data: reads DB creds from Secrets Manager at boot (ARN only, never value)
        │
        ├──▶ RDS MySQL 8.0
        ├──▶ Secrets Manager
        └──▶ ECR

   docker-compose:  Prometheus ─ Grafana ─ Alertmanager   (provided, pre-wired)
```

**Important:** nginx carries real traffic and real health checks. ALB Terraform is graded as IaC but nginx is what makes `/readyz` testable on LocalStack.

---

## Module interfaces (agree before coding)

### `modules/data` outputs (Joyce)

```
db_endpoint, db_port, secret_arn, secret_name
```

### `modules/service` inputs (Lwam)

```
secret_arn, db_endpoint, db_port, app_ami_id, instance_type (default t3.small)
```

### Secrets Manager envelope (exact keys)

```json
{
  "engine": "mysql",
  "username": "...",
  "password": "...",
  "host": "...",
  "port": 3306,
  "dbname": "capacity_lab"
}
```

### Individual naming convention

Each person deploys their own stack via tfvars:

```
rh-hunter-*, rh-joyce-*, rh-lwam-*, rh-minage-*, rh-wairimu-*
```

### Terraform sizing (declare in IaC, one-line justification each in README)

| Resource | Value | Rationale |
|----------|-------|-----------|
| RDS instance class | `db.t3.micro` | 10k patients is tiny |
| RDS storage | 20 GiB gp3 | RDS MySQL minimum |
| RDS engine | MySQL 8.0 | matches A1 |
| Multi-AZ | false | lab trade-off — document in FIDELITY |
| EC2 instance type | `t3.small` | headroom for nginx + app |
| App container memory | `--memory=512m` | makes OPS-2204 OOM reproducible |

---

## Phase 0 — Setup (everyone, ~2 hours)

**Nothing else starts until this is done.**

### Environment (each person)

- [ ] Sign up LocalStack Hobby → generate **personal** auth token
- [ ] Export `LOCALSTACK_AUTH_TOKEN` in shell
- [ ] Add `LOCALSTACK_AUTH_TOKEN` as GitHub Actions secret on **group repo**
- [ ] Use **Codespace 4-core / 16 GB** — do not use Mac Docker Desktop

### Repo setup (Hunter leads, all approve)

- [ ] Pick one **group platform repo** (this repo or org fork)
- [ ] Copy starter stubs from `/Downloads/rehosting-capacity-lab`:
  - `terraform/modules/data/main.tf`
  - `terraform/modules/service/main.tf`
  - `api/secrets.js`
  - `evidence/README.md`
  - `FIDELITY.md`, `CONTRIBUTIONS.md` templates
- [ ] Create evidence folder tree (`01-iac` through `07-incidents`)
- [ ] Protect `main` — require 1 approval on PRs

### Group sync meeting (30 min, all 5)

- [ ] Confirm module interfaces above
- [ ] Confirm individual naming convention
- [ ] Decide: MongoDB in readiness scope? (Recommend: **MySQL only** for `/readyz`; Mongo optional)
- [ ] Fill first row of `CONTRIBUTIONS.md`

---

## Phase 1 — Platform skeleton (Sat–Sun)

### Joyce — `modules/data` → PR #1

1. Create `variables.tf`, `outputs.tf`, `main.tf`
2. `random_password` for DB master password (24 chars, `special = false`)
3. `aws_db_instance`: MySQL 8.0, `db.t3.micro`, 20 GiB gp3, multi-AZ false
4. `aws_secretsmanager_secret` + `aws_secretsmanager_secret_version` with JSON envelope
5. Outputs: `db_endpoint`, `db_port`, `secret_arn`, `secret_name` — **never output password**
6. `terraform fmt`, `validate`, `tflint` clean
7. Open PR → Lwam + Minage review

### Lwam — `modules/service` → PR #2

1. `aws_security_group` — ingress 80 + app port; **no `0.0.0.0/0`**
2. `aws_instance` with `user_data` template — **secret ARN + db endpoint only, never the value**
3. nginx: proxy to app, use `/readyz` for upstream health
4. ALB topology as IaC: `aws_lb`, target group, listener (nginx carries real traffic)
5. Note SG caveats in PR description (LocalStack only honours default SG; rules apply at creation only)
6. Open PR → Joyce + Hunter review

### Minage — Golden CI workflow → PR #3

1. Reusable workflow `.github/workflows/platform.yml`
2. Job order:
   ```
   gitleaks → trivy config → zizmor → docker build → trivy image → tag AMI → tflocal apply
   ```
3. LocalStack starts **in-runner** (not ephemeral Cloud Sandbox)
4. Pin every action to **full commit SHA**
5. Scan jobs: `permissions: contents: read`, **no secrets**
6. Add `step-security/harden-runner` for egress audit
7. AMI tag: `localstack-ec2/app:ami-<sha12>`
8. Open PR → Wairimu + Joyce review

### Wairimu — Bootstrap + Makefile → PR #4

1. Wire bootstrap script → S3 remote state + DynamoDB lock
2. `Makefile` targets:
   - `make up` — stand entire stack from clean clone
   - `make verify` — exit non-zero on any failure (see C8 below)
   - `make destroy` — tear down, capture `destroy.log`
3. Root `terraform/main.tf` skeleton calling both modules
4. Open PR → Minage + Lwam review

### Hunter — Conventions + app boot → PR #5

1. Evidence structure, `.gitignore` (state files, large binaries), pre-commit gitleaks hook
2. Implement `api/secrets.js` (`@aws-sdk/client-secrets-manager`, `AWS_ENDPOINT_URL`, **no `isLocalStack` branch**)
3. Wire boot in `server.js`: load creds before pool starts
4. Endpoints:
   - `GET /healthz` → 200 (process alive)
   - `GET /readyz` → 200 or **503** (DB unreachable / pool saturated / secret failed)
   - `GET /debug/secret-source` → `{ arn, versionId }` only
5. Remove hardcoded password defaults from `database.js` for cloud path
6. Open PR → Minage + Wairimu review

---

## Phase 2 — Integrate + first green deploy (Sun–Mon)

**Goal:** `make up` works on Codespace from fresh clone.

| Step | Who drives | Action |
|------|------------|--------|
| 2.1 | Wairimu | Merge bootstrap + Makefile |
| 2.2 | Joyce | Merge `data` module |
| 2.3 | Lwam | Merge `service` module |
| 2.4 | Minage | Merge CI workflow |
| 2.5 | Hunter | Merge app secrets + health endpoints |
| 2.6 | Wairimu | `mysqldump` from A1 → restore to RDS (10k patients) |
| 2.7 | Each person | Individual root / tfvars |
| 2.8 | Each person | `make up` → `evidence/01-iac/apply.log` |
| 2.9 | Each person | Post-apply plan → **empty** → `plan-after-apply.txt` |
| 2.10 | Each person | `GET /healthz` 200, `GET /readyz` 200 |

### Evidence — data (Wairimu, C2)

- [ ] `evidence/02-data/seed.log`
- [ ] `evidence/02-data/row-counts.txt`

### Evidence — secrets (Hunter, C3)

- [ ] `evidence/03-secrets/gitleaks.json` (zero findings, full history)
- [ ] `evidence/03-secrets/image-env.txt`
- [ ] `evidence/03-secrets/user-data.txt` (ARN only)
- [ ] `evidence/03-secrets/boot.log` (ARN + version logged, never password)

---

## Phase 3 — Gates + health + observability (Tue)

### Minage — scanning gates (C5)

Three deliberate **red PRs**, then fix:

| Gate | Insecure change | Fix |
|------|-----------------|-----|
| **gitleaks** | Commit fake credential | Remove, re-run green |
| **trivy config** | SG with `0.0.0.0/0` ingress | Scope to VPC CIDR |
| **zizmor** | Unpinned action `@v4` | Pin full SHA |

Also document in `evidence/05-gates/README.md`: 3 PR links + **one sentence per gate on what it does NOT catch**.

- [ ] `trivy-image.json`, `trivy-config.json`, `zizmor.txt`

### Hunter — readiness proof (C4) — highest-signal artifact

- [ ] Rotate secret to wrong password → `/readyz` returns **503**
- [ ] Confirm nginx drops upstream
- [ ] Fix secret → `/readyz` recovers to 200
- [ ] Capture in `evidence/04-health/readyz-degraded.txt`

### Joyce + Lwam — observability (C6)

| Person | Alerts + panels |
|--------|-----------------|
| **Joyce** | OPS-2201 (search p95), OPS-2203 (lock wait timeout) |
| **Lwam** | OPS-2202 (pool saturation), OPS-2204 (memory / restart) |

Each person adds rules to `evidence/06-observability/alert-rules.yml` and panel screenshots under `panels/`.

---

## Phase 4 — Incident replay + submit (Tue night / Wed AM)

### Incident replay (C7) — everyone runs all 4

| Incident | k6 script | Signal |
|----------|-----------|--------|
| OPS-2201 | `load-tests/reproduce-OPS-2201.js` | p95, payload size |
| OPS-2202 | `load-tests/reproduce-OPS-2202.js` | pool saturation, DB idle |
| OPS-2203 | `load-tests/reproduce-OPS-2203.js` | `ER_LOCK_WAIT_TIMEOUT` |
| OPS-2204 | `load-tests/reproduce-OPS-2204.js` | memory vs limit, restarts |

- **One full Loom (3–5 min):** Lwam leads — recommend **OPS-2204** (kill process → alert fires → name mechanism)
- **Other three:** inject fault → alert **firing** → fix → alert clears (screenshot/log only)

Each person: `evidence/07-incidents/2201/` … `2204/`

### Wairimu — FIDELITY.md (C9)

Document each LocalStack caveat with **how you detected it** (not guesses):

- Custom SGs ignored — only default SG honoured
- SG ingress rules apply only at instance creation
- IMDS has no `iam/security-credentials/` endpoint
- RDS `storage_encrypted` returned but not applied
- Docker socket mounted inside EC2 (sibling containers)
- ELBv2 health checking undocumented

### Final checklist — `make verify` (everyone, before 09:00 EAT Wed)

```bash
make verify   # must pass
```

Checks (C8):

- [ ] `terraform plan` empty after apply
- [ ] `GET /healthz` → 200
- [ ] `GET /readyz` → 200
- [ ] App resolved DB creds from Secrets Manager (boot log or `/debug/secret-source`)
- [ ] gitleaks on repo and image → zero findings

### Submission

- [ ] Push group platform repo + share link
- [ ] Each person: individual repo/deploy link (if separate)
- [ ] Loom link (one incident end-to-end)
- [ ] `CONTRIBUTIONS.md` filled with PR links
- [ ] Slack message: repo links + what surprised you / what you learned

### E2 — OIDC design (after Core is green)

- [ ] Commented `configure-aws-credentials` block in deploy job
- [ ] IAM trust policy JSON with `sub` scoped to `repo:<org>/<repo>:ref:refs/heads/main`
- [ ] README answer: *what breaks if `sub` is `repo:<org>/*`?*

---

## Evidence bundle (required structure)

```
evidence/
  01-iac/           apply.log  plan-after-apply.txt (must be empty)  destroy.log
  02-data/          seed.log  row-counts.txt
  03-secrets/       gitleaks.json  image-env.txt  user-data.txt  boot.log
  04-health/        readyz-degraded.txt
  05-gates/         README.md (3 red PR links)  trivy-image.json  trivy-config.json  zizmor.txt
  06-observability/ alert-rules.yml  dashboards/  panels/
  07-incidents/     2201/ 2202/ 2203/ 2204/
FIDELITY.md
CONTRIBUTIONS.md
```

**Highest-signal artifacts:**

1. `04-health/readyz-degraded.txt` — readiness flip when secret breaks
2. `05-gates/README.md` — three PRs that went red, then fixed

---

## The four things that will break first

Read these before writing Terraform:

1. **App can't reach MySQL.** RDS endpoint is `localhost:<port>` — use bridge address or `localhost.localstack.cloud`, not bare `localhost` from inside EC2.
2. **`InvalidAMIID.NotFound`.** AMI must be tagged `localstack-ec2/app:ami-<12 hex chars>`.
3. **Port not reachable after SG change.** Ingress rules apply only at instance **creation** — recreate the instance.
4. **RDS/ECR "doesn't exist".** `LOCALSTACK_AUTH_TOKEN` not set → silent fallback to community image.

---

## Dependency graph

```
Phase 0 (env + repo)
    ↓
Joyce: data module ──────────────────┐
    ↓                                  ↓
Lwam: service module ←────────── Wairimu: bootstrap/Makefile
    ↓                                  ↓
Minage: CI (needs AMI tag spec) ──→ make up
    ↓
Hunter: secrets.js + healthz/readyz
    ↓
Wairimu: seed RDS
    ↓
Each: individual root + deploy + evidence
    ↓
Minage: red PRs │ Hunter: readyz degraded │ Joyce/Lwam: alerts
    ↓
All: incident replay + make verify + submit
```

---

## Daily standup (15 min, async Slack OK)

Each person posts:

1. **Yesterday:** what merged / what evidence captured
2. **Today:** one PR or one evidence folder
3. **Blocker:** module interface? AMI tag? RDS endpoint?

---

## Who to ping for what

| Blocker | Ping |
|---------|------|
| RDS endpoint / secret ARN wrong | Joyce |
| EC2 won't start / nginx / AMI tag | Lwam |
| CI red / scanner config | Minage |
| `make up` fails / seed / verify script | Wairimu |
| App can't connect DB / health endpoints | Hunter |

---

## Grading weights (reference)

| Area | Weight |
|------|--------|
| Cloud incident replay — bugs caught, alerts fired | 20% |
| Managed data + secrets | 20% |
| Observability, health & readiness | 15% |
| Scanning gates (three red PRs) | 15% |
| IaC quality & reproducibility | 15% |
| Pipeline & runtime hardening + OIDC design | 10% |
| FIDELITY.md | 5% |

---

*Share this doc with the team. Update `CONTRIBUTIONS.md` as PRs merge.*
