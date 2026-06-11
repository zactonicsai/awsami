# =============================================================================
# environments/dev/main.tf — example stack: 3-node Kafka on the golden AMI
# Pattern to copy for zookeeper / nifi / opensearch / java apps:
#   1) resolve AMI pointer from SSM   2) call modules/ec2-app   3) outputs
# =============================================================================

# --- 1. Resolve the golden AMI via the SSM pointer (single source of truth) ---
# The AMI factory publishes here; Terraform, CloudFormation, CLI and console
# all consume the SAME parameter => every method launches the same image.
data "aws_ssm_parameter" "dataapps_ami" {
  name = "/dataapps/ami/${var.ami_family}/latest"
}

# --- 2. Kafka cluster ---------------------------------------------------------
module "kafka" {
  source = "../../modules/ec2-app"
  # In terraform-live repos prefer a tagged remote source instead:
  # source = "git::https://gitlab.example.com/dataapps-cloud/terraform-modules.git//ec2-app?ref=v1.0.0"

  app_name    = "kafka"
  environment = var.environment
  vpc_id      = var.vpc_id
  ami_id      = data.aws_ssm_parameter.dataapps_ami.value

  # Map keys are stable: adding kafka-4 later won't touch kafka-1..3.
  nodes = {
    kafka-1 = { subnet_id = var.private_subnet_ids[0] }
    kafka-2 = { subnet_id = var.private_subnet_ids[1] }
    kafka-3 = { subnet_id = var.private_subnet_ids[2] }
  }

  default_instance_type = var.kafka_instance_type
  root_volume_gb        = 30
  data_volume_gb        = 200   # Kafka log dirs on dedicated encrypted gp3
  data_volume_throughput = 250

  ingress_rules = [
    {
      description = "Kafka clients (9092 plaintext-internal / 9094 TLS)"
      from_port   = 9092
      to_port     = 9094
      protocol    = "tcp"
      cidr_blocks = var.client_cidr_blocks
    }
  ]

  tags = local.common_tags
}

# --- (pattern) add further apps the same way -----------------------------------
# module "opensearch" { source = "../../modules/ec2-app"  app_name = "opensearch" ... }
# module "nifi"       { source = "../../modules/ec2-app"  app_name = "nifi" ... }

locals {
  common_tags = {
    Project     = "dataapps"
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    # ManagedBy is set by provider default_tags = "terraform"
  }
}
