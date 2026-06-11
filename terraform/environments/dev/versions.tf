terraform {
  # 1.10+ required for S3-native state locking (use_lockfile). 1.15.x current stable.
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"   # AWS provider v6 line (pin tighter in prod, e.g. "6.42.0")
    }
  }
}
