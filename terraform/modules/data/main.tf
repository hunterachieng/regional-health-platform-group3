# =============================================================================
# modules/data — Secrets Manager only          (GROUP-OWNED: Joyce, PR #1)
#
# UPDATED per trainer guidance: RDS is not on LocalStack's free Hobby tier,
# so the managed database moved to Aiven for MySQL (real, free-forever,
# provisioned by hand outside Terraform — Aiven has no LocalStack presence,
# there's nothing to emulate). This module's job shrank to exactly one thing:
# take the Aiven credentials each person already has, and publish them to
# Secrets Manager in the same envelope shape the app already expects. The app
# (api/secrets.js) needed ZERO changes — it never cared where the values came
# from, only that the envelope has host/port/username/password/dbname.
#
# What got removed and why:
#   - aws_db_instance.mysql  -> gone. Aiven IS the database now; Terraform
#     doesn't provision it, it only stores its address.
#   - random_password.db     -> gone. Aiven generates and owns the password;
#     generating our own here would just be a second, wrong password.
#
# Inputs  -> variables.tf
# Outputs -> outputs.tf  (db_endpoint, db_port, secret_arn, secret_name)
# =============================================================================

resource "aws_secretsmanager_secret" "db" {
  name        = var.secret_name
  description = "Aiven MySQL credentials for ${var.project_name} (Regional Health capacity lab)."
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  # Envelope keys EXACTLY as api/secrets.js expects: engine, username,
  # password, host, port, dbname. ca_cert is new — the app doesn't read it
  # yet (database.js has no TLS config), but it's here so that's a one-line
  # follow-up for whoever owns database.js, not a second migration later.
  secret_string = jsonencode({
    engine   = "mysql"
    username = var.aiven_user
    password = var.aiven_password
    host     = var.aiven_host
    port     = var.aiven_port
    dbname   = var.db_name
    ca_cert  = var.aiven_ca_cert
  })
}
