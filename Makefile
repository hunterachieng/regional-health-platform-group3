# =============================================================================
# Makefile
# -----------------------------------------------------------------------------
# One command to stand the whole thing up, one to check it's actually
# healthy, one to tear it down. This is what a grader (or a teammate, or you
# in three days) runs — they should never need to know the backend-config
# flags or which folder terraform lives in.
#
# Usage:
#   make up      NAME=wairimu
#   make verify  NAME=wairimu
#   make destroy NAME=wairimu
#
# NAME is required and deliberately has no default. This Makefile is shared
# by all five people — hardcoding one person's name as the default would
# mean whoever forgets to pass NAME= silently deploys into (or destroys!)
# someone else's stack. Better to fail loudly than guess wrong.
# =============================================================================

TF_DIR          := terraform
EVIDENCE_DIR    := evidence
STATE_BUCKET    := regional-health-tfstate
LOCK_TABLE      := regional-health-tflock
REGION          := us-east-1
LOCALSTACK_URL  := http://localhost:4566

# LocalStack's fake credentials — Terraform's S3 backend still requires *some*
# creds in the environment even with skip_credentials_validation=true.
export AWS_ACCESS_KEY_ID         ?= test
export AWS_SECRET_ACCESS_KEY     ?= test
export AWS_DEFAULT_REGION        ?= $(REGION)
export AWS_EC2_METADATA_DISABLED ?= true

# LocalStack's fake credentials — Terraform's S3 backend still requires *some*
# creds in the environment even with skip_credentials_validation=true.
export AWS_ACCESS_KEY_ID         ?= test
export AWS_SECRET_ACCESS_KEY     ?= test
export AWS_DEFAULT_REGION        ?= $(REGION)
export AWS_EC2_METADATA_DISABLED ?= true

.PHONY: up verify destroy bootstrap _check-name _tf-init

# -----------------------------------------------------------------------------
# Guard: every target that touches Terraform needs NAME set. This runs first
# and fails with a clear message instead of a confusing Terraform error three
# steps later.
# -----------------------------------------------------------------------------
_check-name:
ifndef NAME
	$(error NAME is not set. Usage: make up NAME=wairimu (use your own name, matching your <name>.tfvars file))
endif
	@test -f $(TF_DIR)/$(NAME).tfvars || \
	  (echo "!! $(TF_DIR)/$(NAME).tfvars not found. Copy it from environments/$(NAME).tfvars.example first." && exit 1)

# -----------------------------------------------------------------------------
# Creates the shared S3 bucket + DynamoDB lock table (Step 1). Safe to call
# every time — it checks before creating, so this never fails on a repeat run.
# -----------------------------------------------------------------------------
bootstrap:
	@./bootstrap/bootstrap.sh

# -----------------------------------------------------------------------------
# terraform init, pointed at the shared backend but YOUR OWN state key. This
# is the one place the per-person key gets built — nobody has to remember
# these flags or type your name into nine separate places by hand.
# -----------------------------------------------------------------------------
_tf-init: _check-name bootstrap
	cd $(TF_DIR) && terraform init -reconfigure \
	  -backend-config="bucket=$(STATE_BUCKET)" \
	  -backend-config="dynamodb_table=$(LOCK_TABLE)" \
	  -backend-config="region=$(REGION)" \
	  -backend-config="key=rh/$(NAME)/terraform.tfstate" \
	  -backend-config='endpoints={s3="$(LOCALSTACK_URL)",dynamodb="$(LOCALSTACK_URL)"}' \
	  -backend-config="skip_credentials_validation=true" \
	  -backend-config="skip_metadata_api_check=true" \
	  -backend-config="skip_region_validation=true" \
	  -backend-config="skip_requesting_account_id=true" \
	  -backend-config="use_path_style=true"

# -----------------------------------------------------------------------------
# C1 — stands the whole stack up from zero and proves it's stable:
#   1. init against your own state key
#   2. apply (creates real resources in LocalStack)
#   3. plan again right after — this MUST come back empty. A non-empty
#      post-apply plan means Terraform thinks something is still different
#      from what it just built, which is a sign of a config bug, not a
#      one-off fluke to shrug off.
# -----------------------------------------------------------------------------
up: _tf-init
	@mkdir -p $(EVIDENCE_DIR)/01-iac
	@echo ">> Applying Terraform for $(NAME)..."
	cd $(TF_DIR) && terraform apply -auto-approve -var-file=$(NAME).tfvars 2>&1 \
	  | tee ../$(EVIDENCE_DIR)/01-iac/apply.log
	@echo ">> Capturing post-apply plan (must be empty)..."
	@cd $(TF_DIR) && terraform plan -var-file=$(NAME).tfvars -detailed-exitcode \
	  > ../$(EVIDENCE_DIR)/01-iac/plan-after-apply.txt 2>&1; \
	  code=$$?; \
	  if [ $$code -eq 2 ]; then \
	    echo "!! Post-apply plan is NOT empty — see $(EVIDENCE_DIR)/01-iac/plan-after-apply.txt"; \
	    exit 1; \
	  elif [ $$code -eq 1 ]; then \
	    echo "!! terraform plan errored — see $(EVIDENCE_DIR)/01-iac/plan-after-apply.txt"; \
	    exit 1; \
	  fi
	@echo ">> make up complete. Outputs:"
	@cd $(TF_DIR) && terraform output

# -----------------------------------------------------------------------------
# C8 — the grader check. Exits non-zero the moment ANY check fails, so CI
# actually blocks on a broken deploy instead of reporting green regardless.
#
# app_url comes straight from Terraform's own output — never hardcoded —
# so this checks the box actually standing right now, on your own state key,
# not last week's IP or someone else's stack.
# -----------------------------------------------------------------------------
verify: _check-name
	@echo ">> Running make verify for $(NAME)..."
	@fail=0; \
	echo "-- terraform plan is empty --"; \
	cd $(TF_DIR) && terraform plan -var-file=$(NAME).tfvars -detailed-exitcode > /tmp/verify-plan.txt 2>&1; \
	code=$$?; \
	if [ $$code -eq 0 ]; then \
	  echo "PASS: plan is empty"; \
	elif [ $$code -eq 2 ]; then \
	  echo "FAIL: plan is not empty"; cat /tmp/verify-plan.txt; fail=1; \
	else \
	  echo "FAIL: terraform plan errored"; cat /tmp/verify-plan.txt; fail=1; \
	fi; \
	cd - >/dev/null; \
	echo "-- gitleaks (zero findings expected) --"; \
	if command -v gitleaks >/dev/null 2>&1; then \
	  gitleaks detect --source=. --no-git -v || { echo "FAIL: gitleaks found something"; fail=1; }; \
	else \
	  echo "SKIP: gitleaks not installed locally — CI (Minage's pipeline) runs this"; \
	fi; \
	echo "-- app health --"; \
	app_url=$$(cd $(TF_DIR) && terraform output -raw app_url 2>/dev/null); \
	if [ -z "$$app_url" ]; then \
	  echo "FAIL: could not read app_url from terraform output — has 'make up' finished successfully?"; \
	  fail=1; \
	else \
	  echo "   target: $$app_url"; \
	  code=$$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$$app_url/healthz" || echo "000"); \
	  if [ "$$code" = "200" ]; then echo "PASS: /healthz ($$code)"; \
	  else echo "FAIL: /healthz returned $$code"; fail=1; fi; \
	  code=$$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$$app_url/readyz" || echo "000"); \
	  if [ "$$code" = "200" ]; then echo "PASS: /readyz ($$code)"; \
	  else echo "FAIL: /readyz returned $$code — DB or secret resolution likely broken, see boot.log"; fail=1; fi; \
	fi; \
	if [ $$fail -ne 0 ]; then \
	  echo ">> make verify: FAILED"; exit 1; \
	fi; \
	echo ">> make verify: ALL CHECKS PASSED"

# -----------------------------------------------------------------------------
# Tear-down. Also re-inits first — if you're destroying on a fresh clone or
# a different day, Terraform needs to reconnect to your state before it can
# know what to destroy.
# -----------------------------------------------------------------------------
destroy: _tf-init
	@mkdir -p $(EVIDENCE_DIR)/01-iac
	cd $(TF_DIR) && terraform destroy -auto-approve -var-file=$(NAME).tfvars 2>&1 \
	  | tee ../$(EVIDENCE_DIR)/01-iac/destroy.log