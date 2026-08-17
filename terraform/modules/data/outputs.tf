# =============================================================================
# modules/data — outputs consumed by the root module and modules/service
#
# NEVER output the password. The plaintext credential lives only in the
# Secrets Manager secret (and, unavoidably, in Terraform state — treat state
# as a credential store: encrypted bucket, versioned, non-public, gitignored).
# =============================================================================

output "db_endpoint" {
  description = "RDS instance hostname (no port). From inside the EC2 container, reach it via localhost.localstack.cloud, not bare localhost."
  value       = aws_db_instance.mysql.address
}

output "db_port" {
  description = "RDS instance port."
  value       = aws_db_instance.mysql.port
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding the DB credential envelope. This is what user-data receives — never the value."
  value       = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret."
  value       = aws_secretsmanager_secret.db.name
}
