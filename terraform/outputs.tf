# =============================================================================
# terraform/outputs.tf  (root)
# -----------------------------------------------------------------------------
# These are what `make verify` (Step 3) and the evidence-capture steps will
# read. Never add the DB password here — see modules/data/outputs.tf, it's
# not exposed at the module level either, so there's nothing to leak even by
# accident.
# =============================================================================

output "db_endpoint" {
  description = "RDS hostname. From inside the EC2 container, use localhost.localstack.cloud, not bare localhost."
  value       = module.data.db_endpoint
}

output "db_port" {
  value = module.data.db_port
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret. This is what evidence/03-secrets/user-data.txt should show being passed to the instance."
  value       = module.data.secret_arn
}

# TODO(blocked on Lwam — see main.tf): uncomment once modules/service has an
# outputs.tf with instance_id.
# output "instance_id" {
#   value = module.service.instance_id
# }
