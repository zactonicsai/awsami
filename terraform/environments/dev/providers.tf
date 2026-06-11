provider "aws" {
  region = var.region

  # Stamped on every taggable resource — your cost/ops reports depend on these.
  default_tags {
    tags = {
      Project   = "dataapps"
      ManagedBy = "terraform"
    }
  }
}
