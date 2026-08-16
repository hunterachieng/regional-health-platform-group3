# =============================================================================
# modules/data — RDS MySQL + Secrets Manager        (GROUP-OWNED: you build this)
#
# Create a managed MySQL instance and publish its credentials to Secrets Manager
# using the shared envelope. NO plaintext secret in git, in the image, or in any
# output that gets logged.
#
# Expected inputs  (put these in variables.tf):
#   db_name (default "capacity_lab"), db_username (default "app"),
#   instance_class (default "db.t3.micro"), allocated_storage (default 20),
#   engine_version (default "8.0"), secret_name (default "regional-health/db")
#
# Expected outputs (put these in outputs.tf — the root module depends on them):
#   db_endpoint, db_port, secret_arn, secret_name
# =============================================================================

# TODO: generate the DB master password.
#   hint: resource "random_password" "db" { length = 24, special = false }

# TODO: resource "aws_db_instance" "mysql" — engine "mysql", *_version /
#   instance_class / allocated_storage from vars, storage_type "gp3",
#   db_name / username from vars, password = random_password.db.result,
#   skip_final_snapshot = true. Decide publicly_accessible + storage_encrypted —
#   your `trivy config` gate WILL have opinions; note in FIDELITY.md what
#   LocalStack actually enforces vs. just echoes back.

# TODO: resource "aws_secretsmanager_secret" "db" { name = var.secret_name }
# TODO: resource "aws_secretsmanager_secret_version" "db" — secret_string is the
#   JSON envelope, keys EXACTLY: engine, username, password, host, port, dbname
#   (host/port come from the aws_db_instance address/port attributes).
