#!/usr/bin/env bash
# =============================================================================
# bootstrap/bootstrap.sh
# -----------------------------------------------------------------------------
# Creates the Terraform remote-state backend on LocalStack:
#   - S3 bucket for state (versioned)
#   - DynamoDB table for state locking
#
# This is deliberately NOT Terraform. The backend Terraform will use to store
# its own state cannot itself be created by that same Terraform run — you'd
# need a working backend to create the backend. So this is plain AWS CLI
# against the LocalStack endpoint, and it's idempotent: safe to call on every
# `make up`, from a laptop with state left over from yesterday, or from a
# GitHub Actions runner that started LocalStack fresh 30 seconds ago.
#
# Usage:
#   ./bootstrap/bootstrap.sh
#
# Env vars (all optional, sane defaults for this lab):
#   STATE_BUCKET   default: regional-health-tfstate
#   LOCK_TABLE     default: regional-health-tflock
#   AWS_REGION     default: us-east-1
#   AWS_ENDPOINT_URL default: http://localhost:4566
# =============================================================================
set -euo pipefail

STATE_BUCKET="${STATE_BUCKET:-regional-health-tfstate}"
LOCK_TABLE="${LOCK_TABLE:-regional-health-tflock}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"

# LocalStack's default test credentials. Never real AWS creds — if this ever
# points at a real account it fails safe (AccessDenied), not silently.
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

AWS=(aws --endpoint-url "${AWS_ENDPOINT_URL}" --region "${AWS_REGION}")

echo ">> Bootstrapping Terraform backend on ${AWS_ENDPOINT_URL}"
echo "   bucket=${STATE_BUCKET}  table=${LOCK_TABLE}  region=${AWS_REGION}"

# -----------------------------------------------------------------------------
# Wait for LocalStack to actually be answering before we probe it. In CI,
# `setup-localstack` returns as soon as the container is up, not once every
# service is ready — S3/DynamoDB can take a few extra seconds.
# -----------------------------------------------------------------------------
echo ">> Waiting for LocalStack..."
for i in $(seq 1 30); do
  if curl -s -o /dev/null -w '%{http_code}' "${AWS_ENDPOINT_URL}/_localstack/health" | grep -q "200"; then
    echo "   LocalStack is up."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "!! LocalStack did not become healthy in time" >&2
    exit 1
  fi
  sleep 2
done

# -----------------------------------------------------------------------------
# S3 bucket for state — idempotent create, then enforce the properties that
# matter because state is a credential store (see FIDELITY.md / C3): the DB
# master password lands in state in cleartext regardless of how it got there.
# -----------------------------------------------------------------------------
if "${AWS[@]}" s3api head-bucket --bucket "${STATE_BUCKET}" >/dev/null 2>&1; then
  echo ">> S3 bucket ${STATE_BUCKET} already exists, skipping create."
else
  echo ">> Creating S3 bucket ${STATE_BUCKET}..."
  "${AWS[@]}" s3api create-bucket --bucket "${STATE_BUCKET}" \
    --create-bucket-configuration LocationConstraint="${AWS_REGION}" \
    >/dev/null 2>&1 || "${AWS[@]}" s3api create-bucket --bucket "${STATE_BUCKET}" >/dev/null
fi

echo ">> Enforcing bucket properties (versioning, public-access-block, encryption)..."
"${AWS[@]}" s3api put-bucket-versioning \
  --bucket "${STATE_BUCKET}" \
  --versioning-configuration Status=Enabled >/dev/null

"${AWS[@]}" s3api put-public-access-block \
  --bucket "${STATE_BUCKET}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
  >/dev/null

"${AWS[@]}" s3api put-bucket-encryption \
  --bucket "${STATE_BUCKET}" \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
  >/dev/null

# -----------------------------------------------------------------------------
# DynamoDB table for state locking. Classic Terraform S3-backend locking
# (PK: LockID) — required if your `terraform` block pins a version before
# native S3 locking (`use_lockfile`) landed in 1.10, which is the safer
# assumption for a class that hasn't standardized everyone's TF version.
# -----------------------------------------------------------------------------
if "${AWS[@]}" dynamodb describe-table --table-name "${LOCK_TABLE}" >/dev/null 2>&1; then
  echo ">> DynamoDB lock table ${LOCK_TABLE} already exists, skipping create."
else
  echo ">> Creating DynamoDB lock table ${LOCK_TABLE}..."
  "${AWS[@]}" dynamodb create-table \
    --table-name "${LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    >/dev/null

  echo ">> Waiting for table to become ACTIVE..."
  "${AWS[@]}" dynamodb wait table-exists --table-name "${LOCK_TABLE}"
fi

echo ">> Bootstrap complete."
echo ""
echo "   backend \"s3\" config to pass at 'terraform init':"
echo "     -backend-config=\"bucket=${STATE_BUCKET}\""
echo "     -backend-config=\"dynamodb_table=${LOCK_TABLE}\""
echo "     -backend-config=\"region=${AWS_REGION}\""
echo "     -backend-config=\"key=rh/<your-name>/terraform.tfstate\"   # set per person, never shared"
echo "     -backend-config=\"endpoints={s3=\\\"${AWS_ENDPOINT_URL}\\\",dynamodb=\\\"${AWS_ENDPOINT_URL}\\\"}\""
echo "     -backend-config=\"skip_credentials_validation=true\""
echo "     -backend-config=\"skip_metadata_api_check=true\""
echo "     -backend-config=\"skip_region_validation=true\""
echo "     -backend-config=\"use_path_style=true\""