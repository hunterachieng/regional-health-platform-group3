# C5 — Scanning gates

Three gates must **fail the build** on deliberately insecure changes, then go green
after the fix. A scanner that runs but never blocks is theatre.

Artifacts: `trivy-config.json`, `trivy-image.json`, `zizmor.txt` (from CI job
logs or downloaded workflow artifacts).

---

## Red PRs (deliberately insecure → gate caught → fixed)

| Gate | Red PR | Insecure change | Fix |
|------|--------|-----------------|-----|
| **gitleaks** | _TODO: Minage — link PR_ | Committed fake credential | Removed; re-run green |
| **trivy config** | _TODO: Minage — link PR_ | SG ingress `0.0.0.0/0` | Scoped to VPC CIDR |
| **zizmor** | _TODO: Minage — link PR_ | Unpinned action `@v4` | Pinned full commit SHA |

Replace `_TODO_` rows with real PR URLs once Minage's red-PR branch is merged or
linked from team history.

---

## What each gate does **NOT** catch

One sentence per gate — knowing the limits of a green check is the skill.

| Gate | Does **not** catch |
|------|-------------------|
| **gitleaks** | Runtime-only secrets (Secrets Manager values, CI-injected env vars, or credentials that stay in gitignored `*.tfvars` and never enter git history). |
| **trivy config** | Terraform **`dynamic` blocks** — trivy evaluates static HCL only, so a conditional `root_block_device { encrypted = true }` still reported **AVD-AWS-0131** until documented in `.trivyignore` (see FIDELITY.md section 6). Also does not inspect live cloud state, only files on disk. |
| **zizmor** | Application bugs, container CVEs (that is **trivy image**), or committed secrets (that is **gitleaks**) — it only audits GitHub Actions workflow YAML. With `advanced-security: false` (no GitHub Advanced Security on this repo), findings appear in the job log/annotations only, not the Security tab. |
| **trivy image** _(pipeline, not one of the three red-PR gates)_ | IaC misconfigurations, unpinned Actions, or secrets in git — it only scans the built OCI image layers. |

---

## Lab-specific `.trivyignore` entries

Documented in [FIDELITY.md](../../FIDELITY.md); not production posture.

| ID | Why ignored |
|----|-------------|
| `AVD-AWS-0054` | ALB listener is HTTP — nginx on the instance carries real traffic; ALB is IaC-only on LocalStack Hobby. |
| `AVD-AWS-0104` | EC2 egress must reach external Aiven MySQL and apt for nginx at boot. |
| `AVD-AWS-0131` | `root_block_device` is a dynamic block omitted when `skip_root_block_device=true` for LocalStack; trivy cannot see the encrypted branch (see above). |

---

## Hunter notes (AVD-AWS-0131)

We hit this on PR merge: CI `trivy config` failed with **AWS-0131** even though
`terraform/modules/service/main.tf` declares `encrypted = true` inside
`dynamic "root_block_device"`. Fix: add `AVD-AWS-0131` to `.trivyignore` and
set `skip_root_block_device = true` in personal `<name>.tfvars` for LocalStack
apply only.
