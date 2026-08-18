# =============================================================================
# terraform/main.tf  (root)
# -----------------------------------------------------------------------------
# Composes the two group-owned modules into one person's deploy. This file
# should contain NO copy-pasted resource blocks of its own — its only job is
# wiring modules together. If you find yourself writing an aws_* resource
# directly in here, it probably belongs in modules/data or modules/service
# instead (that's the whole point of splitting them out).
# =============================================================================

module "data" {
  source = "./modules/data"

  project_name   = var.project_name
  db_name        = var.db_name
  secret_name    = var.secret_name
  aiven_host     = var.aiven_host
  aiven_port     = var.aiven_port
  aiven_user     = var.aiven_user
  aiven_password = var.aiven_password
  aiven_ca_cert  = var.aiven_ca_cert
}

# -----------------------------------------------------------------------------
# TODO(blocked on Lwam — modules/service is still a TODO stub, PR #2 not
# merged yet): uncomment this block once modules/service/variables.tf and
# outputs.tf exist. Until then this would fail `terraform validate` with
# "no variable named X" — that's not your bug, it's just sequencing. The
# inputs below are exactly the agreed interface from TEAM_PLAN.md, not a
# guess, so this should be a straight uncomment with no changes needed once
# his module catches up.
# -----------------------------------------------------------------------------
# module "service" {
#   source = "./modules/service"
#
#   secret_arn    = module.data.secret_arn
#   db_endpoint   = module.data.db_endpoint
#   db_port       = module.data.db_port
#   app_ami_id    = var.app_ami_id
#   instance_type = var.instance_type
# }
