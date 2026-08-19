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

# --- passed straight through to modules/data --------------------------------
# UPDATED: RDS sizing variables (instance_class, allocated_storage,
# engine_version) are gone — the database is Aiven MySQL now, provisioned
# outside Terraform on their dashboard, not sized here.

variable "db_name" {
  description = "Database (schema) name inside your Aiven MySQL service."
  type        = string
  default     = "capacity_lab"
}

variable "secret_name" {
  description = "Secrets Manager secret name. Must be unique per person, e.g. regional-health/wairimu/db — two people sharing a name means the second apply overwrites the first person's secret."
  type        = string
}

variable "aiven_host" {
  description = "Aiven MySQL hostname, from your Aiven service Overview page."
  type        = string
}

variable "aiven_port" {
  description = "Aiven MySQL port, from your Aiven service Overview page."
  type        = number
}

variable "aiven_user" {
  description = "Aiven MySQL username. Default is avnadmin."
  type        = string
  default     = "avnadmin"
}

variable "aiven_password" {
  description = "Aiven MySQL password, from your Aiven service Overview page."
  type        = string
  sensitive   = true
}

variable "aiven_ca_cert" {
  description = "Contents of Aiven's CA certificate .pem file, pasted as a string."
  type        = string
  sensitive   = true
}

# --- passed straight through to modules/service (once it's implemented) ---

variable "instance_type" {
  description = "EC2 instance type running the app."
  type        = string
  default     = "t3.small"
}

variable "app_ami_id" {
  description = "AMI id CI produces, form ami-<sha12> (12 lowercase hex chars). Not the Docker tag — CI strips the localstack-ec2/app: prefix before setting TF_VAR_app_ami_id. No default on purpose — you must supply this deliberately, it changes on every image rebuild."
  type        = string
}

variable "skip_root_block_device" {
  description = "Omit root_block_device on the EC2 instance. Set true in <name>.tfvars for LocalStack + custom Docker AMIs — Terraform's DescribeImages pre-check fails even though RunInstances succeeds."
  type        = bool
  default     = false
}
