# Provider requirements for the data module. random_password needs the
# hashicorp/random provider declared here so `terraform validate` and tflint
# resolve it at the module level.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}
