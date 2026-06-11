# =============================================================================
# al2023-base.pkr.hcl — Golden AMI for Data Applications platform
# Base: latest Amazon Linux 2023 (resolved at build time via SSM public param)
# Patch policy: approved-only (versionlock) + denied-package removal (fail-closed)
# Build:   packer init . && packer validate . && packer build -var-file=dev.pkrvars.hcl .
# Windows: run from cmd/PowerShell or via scripts\windows\build-ami.bat
# =============================================================================

packer {
  required_version = ">= 1.11.0"
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.large" # build instance only; not the runtime size
}

variable "ami_family" {
  type        = string
  default     = "al2023-base"
  description = "Logical family name; consumed by SSM pointer /dataapps/ami/<family>/latest"
}

variable "vpc_id" {
  type        = string
  default     = "" # empty = default VPC; set for builds in a build-VPC
}

variable "subnet_id" {
  type    = string
  default = ""
}

variable "kms_key_id" {
  type        = string
  default     = "" # empty = aws/ebs default key; set alias/arn for a CMK
  description = "KMS key for encrypted boot volume"
}

variable "deprecate_after_days" {
  type        = number
  default     = 90
  description = "Auto-set EC2 AMI deprecation date this many days after build"
}

variable "iam_instance_profile" {
  type        = string
  default     = ""
  description = "Optional instance profile for the build instance (needed if scripts pull from S3)"
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}

# ---------------------------------------------------------------------------
# Data: resolve the LATEST AL2023 AMI from AWS's public SSM parameter
# (same pointer pattern your own consumers will use for YOUR AMIs)
# ---------------------------------------------------------------------------
data "amazon-parameterstore" "al2023" {
  name   = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  region = var.region
}

locals {
  timestamp    = formatdate("YYYYMMDD-hhmmss", timestamp())
  ami_name     = "${var.ami_family}-${local.timestamp}"
  deprecate_at = timeadd(timestamp(), "${var.deprecate_after_days * 24}h")

  base_tags = merge({
    Name        = local.ami_name
    AmiFamily   = var.ami_family
    Project     = "dataapps"
    ManagedBy   = "packer"
    BaseAmi     = data.amazon-parameterstore.al2023.value
    BuildDate   = local.timestamp
    OS          = "al2023"
  }, var.extra_tags)
}

# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------
source "amazon-ebs" "al2023" {
  region        = var.region
  instance_type = var.instance_type
  source_ami    = data.amazon-parameterstore.al2023.value

  ami_name        = local.ami_name
  ami_description = "DataApps golden AMI (${var.ami_family}) from latest AL2023, approved-patch policy applied"

  # Security posture of the produced image & the build instance
  encrypt_boot  = true
  kms_key_id    = var.kms_key_id != "" ? var.kms_key_id : null
  ena_support   = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2
  }

  # Networking for the BUILD instance
  vpc_id                      = var.vpc_id != "" ? var.vpc_id : null
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : null
  associate_public_ip_address = true # set false + use SSM/session-manager interface in locked-down VPCs
  ssh_username                = "ec2-user"
  ssh_interface               = "public_ip"

  iam_instance_profile = var.iam_instance_profile != "" ? var.iam_instance_profile : null

  # Lifecycle hygiene baked into the image record
  deprecate_at = local.deprecate_at

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 16
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags          = local.base_tags  # tags on the AMI
  snapshot_tags = local.base_tags  # tags on its snapshots (often forgotten!)
  run_tags      = merge(local.base_tags, { Purpose = "packer-build" }) # build instance
}

# ---------------------------------------------------------------------------
# Build: shell provisioners run our numbered scripts; files first
# ---------------------------------------------------------------------------
build {
  name    = "dataapps-al2023-base"
  sources = ["source.amazon-ebs.al2023"]

  # Ship the patch-policy lists onto the build instance
  provisioner "file" {
    source      = "patch-policy/"
    destination = "/tmp/patch-policy"
  }

  provisioner "shell" {
    scripts = [
      "scripts/00-os-update.sh",
      "scripts/01-baseline.sh",
      "scripts/02-patch-policy.sh",
      "scripts/99-cleanup.sh",
    ]
    execute_command = "chmod +x {{ .Path }}; sudo -E bash '{{ .Path }}'"
    # Fail the whole build on any script error (default, stated explicitly)
    expect_disconnect = false
  }

  # Manifest = machine-readable record of what was produced (feed to publish step)
  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
    custom_data = {
      ami_family = var.ami_family
      base_ami   = data.amazon-parameterstore.al2023.value
    }
  }
}
