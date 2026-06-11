terraform {
  backend "s3" {
    bucket = "REPLACE-dataapps-tfstate-<account-id>"   # versioned + encrypted bucket
    key    = "data-apps/dev/core.tfstate"
    region = "us-east-1"

    # S3-native locking (TF >= 1.10). The old dynamodb_table lock is deprecated.
    use_lockfile = true
    encrypt      = true
  }
}
# NOT GitLab-managed state: with two GitLab instances the state would live on
# one of them — S3 is neutral ground both CI systems and desktops can reach.
