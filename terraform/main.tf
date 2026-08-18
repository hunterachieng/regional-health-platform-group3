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

  project_name      = var.project_name
  db_name           = var.db_name
  db_username       = var.db_username
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  engine_version    = var.engine_version
  secret_name       = var.secret_name
}

# -----------------------------------------------------------------------------
# Service tier. The five inputs below are the agreed interface from
# TEAM_PLAN.md, unchanged.
#
# One addition to the originally-sketched block: project_name. Every resource in
# modules/service is named from it (SG, instance, ALB, target group) so the five
# of us can apply identical code without colliding on names — the same reason
# modules/data already takes it. aws_region is passed too so the app's Secrets
# Manager client and the provider cannot drift apart.
# -----------------------------------------------------------------------------
module "service" {
  source = "./modules/service"

  project_name  = var.project_name
  secret_arn    = module.data.secret_arn
  db_endpoint   = module.data.db_endpoint
  db_port       = module.data.db_port
  app_ami_id    = var.app_ami_id
  instance_type = var.instance_type
  aws_region    = var.aws_region
}
