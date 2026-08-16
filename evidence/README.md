# Evidence bundle

Reproduce this exact structure in your repo. **No artifact, no credit.**
Screenshots only where nothing else works (Grafana panels). Keep committed
evidence small (logs, plans, small images) — large binaries are gitignored.

```
evidence/
  01-iac/           apply.log  plan-after-apply.txt (must be empty)  destroy.log
  02-data/          seed.log  row-counts.txt
  03-secrets/       gitleaks.json  image-env.txt  user-data.txt  boot.log
  04-health/        readyz-degraded.txt   # break the secret -> /readyz flips 503 -> fix -> recovers
  05-gates/         README.md (3 red-PR links)  trivy-image.json  trivy-config.json  zizmor.txt
  06-observability/ alert-rules.yml  dashboards/  panels/
  07-incidents/     2201/ 2202/ 2203/ 2204/
```

The two highest-signal artifacts:
- `04-health/readyz-degraded.txt` — only working wiring produces a readiness flip
  when you break the secret behind it.
- `05-gates/README.md` — three PRs that each went **red** on a deliberately
  insecure change, then the fix commit. A gate that never blocks is theatre.
