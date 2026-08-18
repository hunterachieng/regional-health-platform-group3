# =============================================================================
# terraform/variables.tf  (root)
# -----------------------------------------------------------------------------
# Every person fills these in via their own <name>.tfvars file (gitignored —
# see terraform/environments/*.tfvars.example for the template). This is what
# makes five people able to deploy five separate stacks from the same code.
# =============================================================================

variable "aws_region" {
  description = "Region to deploy into. Same for everyone on this lab."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Per-member stack prefix, e.g. rh-wairimu. Drives resource naming."
  type        = string
}

# --- passed straight through to modules/data -------------------------------

variable "db_name" {
  description = "Initial database (schema) name."
  type        = string
  default     = "capacity_lab"
}

variable "db_username" {
  description = "Master username for the MySQL instance."
  type        = string
  default     = "app"
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated RDS storage in GiB."
  type        = number
  default     = 20
}

variable "engine_version" {
  description = "MySQL engine version."
  type        = string
  default     = "8.0"
}

variable "secret_name" {
  description = "Secrets Manager secret name. Must be unique per person, e.g. regional-health/wairimu/db — two people sharing a name means the second apply overwrites the first person's secret."
  type        = string
}

# --- passed straight through to modules/service (once it's implemented) ---

variable "instance_type" {
  description = "EC2 instance type running the app."
  type        = string
  default     = "t3.small"
}

variable "app_ami_id" {
  description = "AMI tag CI produced, form localstack-ec2/app:ami-<sha12>. No default on purpose — you must supply this deliberately, it changes on every image rebuild."
  type        = string
}
