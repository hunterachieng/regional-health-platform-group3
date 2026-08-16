# ☁️ Assignment 2 — Rehost Regional Health to the Cloud (on LocalStack)

**Due: Wednesday 19 August 2026, 09:00 EAT**

Assignment 1 taught you how the service breaks under load. This one makes it safe to run and change — infrastructure as code, a managed database, secrets that never touch the repo, scanning gates that actually block a bad change, and observability that catches the same four bugs in a cloud-shaped environment.

You will build against **[LocalStack](https://www.localstack.cloud/localstack-for-aws)**, a local emulator of the AWS APIs. The Terraform you write is real AWS Terraform; only the endpoints point at LocalStack.

> **Read this first.** The point is not "get it deployed." The point is the *guardrails* — and proving they hold. Every claim needs an artifact: a scan report, a `terraform plan`, an image digest, an alert that actually fired. A scanner that runs but never fails the build is theatre.

---

## 🧾 Scope

The graded set is **Core plus one Extended reach (E2, OIDC design)**. Incident replay is **one full walk-through plus alert-only for the other three**. Anything not listed under Core or E2 is out of scope — don't spend time on it. Build the guardrails, prove they hold, submit.

There is no ALB traffic path, no ECS/Fargate, no CloudWatch alarms, no RDS Proxy, no autoscaling: those either don't emulate faithfully on LocalStack or cost more time than they teach. Every piece that remains is verifiable.

---

## 🖥️ Environment — read before you start

### Linux is required

LocalStack's Docker-backed EC2 instances are not reachable from the host on macOS, because Docker Desktop does not expose the bridge network. This is documented by LocalStack, not a bug you can work around.

**Your options, in order of preference:**

1. **GitHub Codespaces** — a `.devcontainer/` is provided in the starter repo. Zero setup, works from any laptop.
2. A Linux VM (multipass, UTM, WSL2 with Docker Engine — *not* Docker Desktop).
3. A native Linux machine.

Do not spend a day fighting a Mac. Use Codespaces.

### Licence — free Hobby tier

Everything this lab uses (**RDS, ECR, EC2, Secrets Manager, S3, DynamoDB**) is included in LocalStack's **free Hobby tier**. You do **not** need a paid plan.

- **Sign up for a free LocalStack account** and generate a **Hobby auth token** at **app.localstack.cloud → Settings → Auth Tokens**.
- Set it as `LOCALSTACK_AUTH_TOKEN` in your shell and as a GitHub Actions repository secret. It is the only real secret in this assignment.
- **Non-commercial / fair use:** the Hobby tier is licensed for individual, non-commercial use — which is exactly what your learning here is. Use your **own personal** Hobby account and token; don't share one across the group.
- Hobby does not include Cloud Pods, Cloud Sandbox / ephemeral instances, or state persistence. This lab needs none of them: CI starts LocalStack fresh inside the runner every time.

### Required resources & right-sizing

Two layers. LocalStack runs everything as containers on your dev box, so **your machine is the real hardware**. The AWS sizes you declare in Terraform are graded as IaC and matter for real-AWS transfer, but LocalStack does **not** enforce them — note that in `FIDELITY.md`.

**Dev environment — this is what actually has to be big enough:**

| Resource | Minimum | Recommended | Why |
|---|---|---|---|
| CPU | 2 vCPU | **4 vCPU** | The 2202 replay drives ~2000 k6 VUs alongside MySQL + LocalStack; 2 cores bottleneck and skew your latency numbers |
| RAM | 8 GB | **16 GB** | LocalStack + the RDS MySQL container + the EC2 instance container + Prometheus/Grafana/Alertmanager + k6 all run at once |
| Disk | 32 GB | 32 GB | LocalStack Pro, MySQL 8.0, Node and observability images total several GB |
| Machine | Codespaces 2-core | **Codespaces 4-core / 16 GB** (or a Linux VM ≥ 4 vCPU / 16 GB) | Pick the 4-core option from the Codespace "⋯ → Change machine type" menu |

> Under-provisioning doesn't fail the build, but it inflates your incident latencies. If 2201/2202 p95 looks wild, check host headroom before blaming the code.

**Declared AWS resources — right-size these in Terraform, one line of justification each in your README:**

| Resource | Value | Rationale |
|---|---|---|
| RDS instance class | `db.t3.micro` (2 vCPU / 1 GiB) | 10,000 patients is tiny; the smallest general-purpose class is plenty |
| RDS storage | `20` GiB `gp3` | 20 GiB is the RDS-MySQL minimum; the dataset is a few MB |
| RDS engine | MySQL `8.0` | matches A1; real InnoDB behaviour for 2202/2203 |
| Multi-AZ | `false` | single-AZ for a lab — state the availability trade-off you're accepting |
| EC2 instance type | `t3.small` (2 vCPU / 2 GiB) | headroom for nginx + app; `t3.micro` is too tight |
| App container memory | `--memory=512m` (set for you) | the cgroup ceiling that makes 2204 OOM reproducible: small enough to fail under the unbounded export, large enough for normal traffic |

**README requirement:** state the class / size / storage you chose and why. "Because it's the smallest that fits the workload" is a fine answer if it's true — right-sizing is about *matching the load*, not picking big.

### One command to stand it all up

```bash
make up
```

That must work on a clean LocalStack from a fresh clone. If a grader can't run it and get a green service, the assignment isn't done.

---

## 🏗️ Target architecture

```
GitHub Actions (per PR, LocalStack runs inside the runner)
  gitleaks ─▶ trivy config ─▶ zizmor ─▶ docker build ─▶ trivy image
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
     └─ user-data: reads DB creds from Secrets Manager at boot
        │
        ├──▶ RDS MySQL 8.0   (a real MySQL server in a container)
        ├──▶ Secrets Manager (DB creds — ARN passed in, value never)
        └──▶ ECR             (image built, scanned, digest recorded)

   docker-compose:  Prometheus ─ Grafana ─ Alertmanager   (provided, pre-wired)
```

**Why nginx and not an ALB.** LocalStack's ELBv2 routes traffic but does not document active health checking or unhealthy-target removal, and its target registration is IP-based against Docker gateway addresses. Your readiness gate would be untestable. You will still *write* the `aws_lb` Terraform — it's graded as IaC and scanned — but nginx carries the real traffic and the real health checks.

**CI model — LocalStack runs inside the runner. Do not use hosted/ephemeral instances.** Your workflow starts LocalStack in the GitHub Actions runner (`setup-localstack` in its in-runner mode), then applies, verifies, and replays incidents in the same job; the runner is discarded at the end. Do **not** deploy to a hosted LocalStack **Ephemeral Instance / preview URL**: your app runs on nginx on a Docker-backed EC2 instance whose port is reachable only from the Linux host, so `/readyz` (C4) and the k6 replay (C7) have no path through a remote preview endpoint — and ephemeral minutes are credit-metered. In-runner is the only supported CI model for this lab.

---

## 🧑‍🤝‍🧑 How this runs

**Groups build a shared platform. Each of you rehosts your own service on it.** Both halves are graded separately; you cannot earn the individual half on a teammate's deploy.

| Group owns (built once, reviewed, reused) | You own individually |
|---|---|
| `modules/data` — RDS MySQL + Secrets Manager | A Terraform **root** composing the modules for *your* service |
| `modules/service` — EC2 + nginx + user-data + health wiring | Your image hardening + secret wiring |
| The golden CI workflow (reusable workflow) | Your alert rules + dashboards |
| Bootstrap scripts and repo conventions | Your incident replay evidence |

**Anti-free-rider rule — graded from git, not from a self-report:** every group member must be **sole author of at least one module PR** and **approving reviewer on at least two others**. `CONTRIBUTIONS.md` is still required but it is a summary, not the evidence.

**If the group module isn't ready in time**, fork it, document the divergence in your README, and carry on. You lose no individual marks for a teammate's delay.

---

## ✅ CORE — required to pass

Every item below has a named evidence artifact. No artifact, no credit.

### C1. Terraform stands the stack up from zero
- Two group modules (`data`, `service`) composed by your root. No copy-pasted resource blocks.
- `terraform fmt`, `validate`, `tflint` clean.
- Remote state on S3 + DynamoDB lock (the bootstrap script is provided — you don't write it).
- **Evidence:** `evidence/01-iac/apply.log`, `evidence/01-iac/plan-after-apply.txt` (must be empty), `evidence/01-iac/destroy.log`

### C2. RDS MySQL with schema and seed
- MySQL 8.0 via the `data` module. Schema + seed migrated (10,000 patients — the row count is a documented variable, don't hardcode).
- Seed via `mysqldump` restore or a direct SQL load. Cloud Pods and RDS snapshots aren't available on the Hobby tier, so don't use those routes.
- **Evidence:** `evidence/02-data/seed.log`, `evidence/02-data/row-counts.txt`

### C3. Secrets — managed, injected, never in code
Keep three things straight; only the third is graded here:

| Layer | Value | Secret? |
|---|---|---|
| CI | `LOCALSTACK_AUTH_TOKEN` | Yes — GitHub Actions secret |
| Cloud auth | `AWS_ACCESS_KEY_ID=test` | No — LocalStack default, account `000000000000` |
| **Application** | **DB username / password** | **Yes — this is the graded one** |

- Terraform generates the DB password, creates the RDS instance, and writes a Secrets Manager secret with the standard envelope: `engine`, `username`, `password`, `host`, `port`, `dbname`.
- User-data receives **the secret ARN and the endpoint. Never the value.** On real EC2, user-data is readable via IMDS by anything on the box; on LocalStack it sits in a world-readable file at `/var/lib/cloud/instances/<id>/`. Same discipline either way.
- The app calls `GetSecretValue` at boot, caches in memory, logs the **ARN and version** only.
- The app uses `AWS_ENDPOINT_URL` so the SDK points at LocalStack. **There must be no `if (isLocalStack)` branch in your application code.** The same binary would run against real AWS with that variable unset.
- **Evidence:** `evidence/03-secrets/gitleaks.json` (zero findings, full history), `evidence/03-secrets/image-env.txt`, `evidence/03-secrets/user-data.txt`, `evidence/03-secrets/boot.log`

> **On Terraform state.** `aws_db_instance.password` lands in state in cleartext. There is no arrangement of `random_password` that avoids this. The rule is therefore: **no plaintext secret in git or in the image**, and **treat the state file as a credential store** — encrypted bucket, versioned, non-public, `.gitignore`'d. Prove the bucket properties with `trivy config`.

### C4. Liveness and readiness that mean different things
- `/healthz` — process is alive.
- `/readyz` — **503 when the DB is unreachable, the pool is saturated, or the secret failed to resolve.**
- nginx uses `/readyz` for upstream health; a not-ready instance receives no traffic.
- **Evidence:** `evidence/04-health/readyz-degraded.txt` — break the secret (rotate to a wrong password), show `/readyz` flip to 503 and nginx pull the upstream, then fix it and show recovery.

C4's evidence is the single highest-signal artifact in Core. Anyone can produce a clean scan report; only working wiring produces a readiness flip when you break the secret behind it.

### C5. Gates that actually block
Three tools, three jobs:

| Tool | Covers |
|---|---|
| `gitleaks` | secrets in repo + full git history — pre-commit hook **and** CI gate |
| `trivy` | image vulns (fail HIGH/CRITICAL), Terraform misconfig, Dockerfile misconfig |
| `zizmor` | GitHub Actions security flaws, including unpinned action tags |

Image hardening: minimal base, non-root user, no build tools in the final layer, base pinned by **digest**, every action pinned to a full commit **SHA**.

**Guard the guards (supply chain).** Your scanners are themselves attack surface — in 2025 a popular action's tags were repointed to steal CI secrets (tj-actions/changed-files). Pinning is necessary but **not sufficient**: it doesn't stop a malicious commit already at your SHA, a compromised maintainer, or a zero-day in the tool's own logic. So layer it — *contain and detect, don't just prevent*:
- **Integrity:** pin actions/images/scanners by digest/SHA; bump via reviewed Renovate/Dependabot PRs, never `@latest`.
- **Blast radius:** scan jobs run `permissions: contents: read` with **no secrets** — a compromised scanner can't exfiltrate what the job can't see.
- **Detection:** add `step-security/harden-runner` (egress audit) so a compromised step phoning home is visible. You can't prevent an unknown zero-day; you contain and detect it.
- **Limits:** in `05-gates/README.md`, one sentence per gate on what it does **NOT** catch. Knowing the limits of a green check is the skill.

- **Evidence — the artifact I care most about:** for **each** of the three gates, a **link to a PR that went red**, the scanner output, and the fix commit. Introduce the insecure change deliberately (`0.0.0.0/0` security group, a committed fake credential, an unpinned action), let the gate catch it, then fix it. Put the three PR links + the "what each gate misses" lines in `evidence/05-gates/README.md`.

### C6. Observability with alerts that fire
The Prometheus / Grafana / Alertmanager stack is **provided pre-wired** with one worked dashboard and one worked alert rule. You are not graded on standing it up. You are graded on what you add:

- Four alert rules, one per incident.
- A Grafana panel per incident showing the signal.
- **Evidence:** `evidence/06-observability/alert-rules.yml`, dashboard JSON, panel screenshots.

### C7. Cloud incident replay
Re-run the four k6 incident scripts against the deployed stack.

| Incident | Signal |
|---|---|
| **2201** | per-route p95 + rows-examined / payload size |
| **2202** | pool saturation while the DB is idle |
| **2203** | `ER_LOCK_WAIT_TIMEOUT` / lock-wait time |
| **2204** | memory vs limit + process restart count |

- **One incident gets the full treatment:** induce it, the alert fires → dashboard shows it → you name the mechanism in prose.
- **All of them share one catch:** an alert only fires when its failure is actually present, and you fixed these in A1 — replaying against a healthy app won't trip the rules. To prove an alert, **inject the fault**, confirm it reaches `firing`, then confirm the fix clears it. A green alert on a healthy system proves nothing. The most deterministic injection is killing the process: `up{job="capacity-api"} == 0` trips OPS-2204 with no load tuning. Load-based rules (2201/2202) need sustained concurrency to cross their thresholds.
- **Evidence:** `evidence/07-incidents/<id>/` per incident.

Note what the managed tier changed versus your local run in A1. RDS MySQL is a **real MySQL server**, so lock waits, InnoDB behaviour and connection limits are genuine — 2202 and 2203 should reproduce faithfully. 2204 depends on the container memory limit (`EC2_DOCKER_FLAGS=--memory=512m`, set for you).

### C8. `make verify` passes
One command the grader runs. It must exit non-zero if any of these fail:

```
terraform plan is empty after apply
GET /healthz  → 200
GET /readyz   → 200
app resolved DB creds from Secrets Manager (log line or /debug/secret-source)
gitleaks on repo and image → zero findings
```

### C9. `FIDELITY.md` — where the emulator lied to you
A short document: **which behaviours did LocalStack not reproduce, how did you detect it, and what would you have to verify in a real AWS account before trusting this?**

Starters you'll hit (verify each yourself rather than copying this list):

- Only the `default` security group is supported; your custom SGs govern nothing at runtime.
- SG ingress rules apply **only at instance creation** — modifying a group opens no ports on a running instance.
- IMDS has no `iam/security-credentials/` endpoint, so instance-profile credentials cannot be demonstrated at all.
- `storage_encrypted` on RDS is returned as configured but no encryption is applied.
- The Docker socket is mounted **inside** each EC2 instance, so a `docker run` there creates a sibling on the host, not a child of the instance.
- ELBv2 health checking is undocumented and may not exist.

This is the most transferable thing in the assignment. Not trusting your test environment is a senior skill.

---

## 🔷 EXTENDED — the one reach (only after Core is green)

- **E2.** OIDC as a **design deliverable**: the deploy job carries a commented `configure-aws-credentials` block showing the production path, plus the actual IAM trust policy JSON with `sub` scoped to `repo:<org>/<repo>:ref:refs/heads/main`. In your README, answer: *what breaks if `sub` is `repo:<org>/*`?* No infrastructure — this is writing, and it's the only Extended item graded this run.

---

## 📁 Evidence bundle

Fixed structure. Screenshots only where nothing else works (Grafana panels).

```
evidence/
  01-iac/          apply.log  plan-after-apply.txt  destroy.log
  02-data/         seed.log  row-counts.txt
  03-secrets/      gitleaks.json  image-env.txt  user-data.txt  boot.log
  04-health/       readyz-degraded.txt
  05-gates/        README.md (3 PR links)  trivy-image.json  trivy-config.json  zizmor.txt
  06-observability/ alert-rules.yml  dashboards/  panels/
  07-incidents/    2201/ 2202/ 2203/ 2204/
  FIDELITY.md
  CONTRIBUTIONS.md
```

---

## 🚨 The four things that will break first

Read these now; they'll save you hours.

1. **The app can't reach MySQL.** RDS returns an endpoint on `localhost:<port>` — from inside the instance container, `localhost` is the instance itself. Use the bridge address or `localhost.localstack.cloud`.
2. **`InvalidAMIID.NotFound`.** You skipped the `docker tag` step, or the tag isn't in the form `localstack-ec2/<name>:ami-<12 hex chars>`.
3. **Your port isn't reachable after changing the security group.** Ingress rules apply only at instance creation. Re-create the instance.
4. **RDS or ECR "doesn't exist".** Your `LOCALSTACK_AUTH_TOKEN` isn't set and you silently fell back to the community image.

---

## 🧮 Grading

| Area | Weight |
|---|--:|
| Cloud incident replay — bugs caught, alerts fired | 20% |
| Managed data + secrets (RDS, Secrets Manager, runtime injection, zero hardcoded) | 20% |
| Observability, health & readiness | 15% |
| Scanning gates that actually block (the three red PRs) | 15% |
| IaC quality & reproducibility | 15% |
| Pipeline & runtime hardening (SHA/digest pinning, masking, OIDC design) | 10% |
| `FIDELITY.md` | 5% |

**Group platform** is graded on module quality, the golden pipeline, and PR review discipline. **Individual rehost** is graded on your service standing up green and your incident replay.

---

## 📤 Submission

Push to the group platform repo and your individual repo. Share both links, plus a **3–5 minute Loom** of one incident being caught end-to-end: alert → dashboard → you naming the mechanism.

---

*Assignment 2 of the Stateful Systems track.*
