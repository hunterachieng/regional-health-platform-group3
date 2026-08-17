# =============================================================================
# modules/data — inputs
# =============================================================================

variable "project_name" {
  description = "Per-member stack prefix, e.g. rh-joyce. Used to name the DB instance."
  type        = string
}

variable "db_name" {
  description = "Initial database (schema) name created inside the MySQL instance."
  type        = string
  default     = "capacity_lab"
}

variable "db_username" {
  description = "Master username for the MySQL instance."
  type        = string
  default     = "app"
}

variable "instance_class" {
  description = "RDS instance class. 10k patients is tiny, so the smallest general-purpose class is plenty."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GiB. 20 GiB is the RDS-MySQL minimum; the dataset is a few MB."
  type        = number
  default     = 20
}

variable "engine_version" {
  description = "MySQL engine version. Matches A1 for real InnoDB behaviour in the 2202/2203 replays."
  type        = string
  default     = "8.0"
}

variable "secret_name" {
  description = "Secrets Manager secret name holding the DB credential envelope."
  type        = string
  default     = "regional-health/db"
}
