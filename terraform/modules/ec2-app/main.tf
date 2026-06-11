# =============================================================================
# modules/ec2-app — opinionated EC2 cluster for a Data Application
# - AMI id passed IN (resolve the SSM pointer in the calling root module)
# - per-node map => stable addresses (adding node-4 never rebuilds node-1)
# - SSM-managed (no SSH ingress by default), IMDSv2, encrypted gp3, CW agent IAM
# =============================================================================

# ---------------------------------------------------------------------------
# Security group — least privilege: app ports only from allowed CIDRs/SGs
# ---------------------------------------------------------------------------
resource "aws_security_group" "this" {
  name_prefix = "${var.app_name}-${var.environment}-"
  description = "App traffic for ${var.app_name} (${var.environment})"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      description     = ingress.value.description
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      cidr_blocks     = ingress.value.cidr_blocks
      security_groups = ingress.value.security_groups
    }
  }

  # Intra-cluster: nodes talk to each other on any port (Kafka/ZK/OS clustering)
  ingress {
    description = "intra-cluster"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.app_name}-${var.environment}" })

  lifecycle {
    create_before_destroy = true # name_prefix exists so SG swaps don't deadlock
  }
}

# ---------------------------------------------------------------------------
# IAM — SSM core (Session Manager + Ansible-over-SSM) + CloudWatch agent
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name_prefix        = "${var.app_name}-${var.environment}-"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Extra app policies (e.g., S3 artifact bucket read for java_app) attach by ARN
resource "aws_iam_role_policy_attachment" "extra" {
  for_each   = toset(var.extra_policy_arns)
  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "this" {
  name_prefix = "${var.app_name}-${var.environment}-"
  role        = aws_iam_role.this.name
  tags        = var.tags
}

# ---------------------------------------------------------------------------
# Instances — one per entry in var.nodes (map key = stable node name)
# ---------------------------------------------------------------------------
resource "aws_instance" "this" {
  for_each = var.nodes

  ami                    = var.ami_id
  instance_type          = coalesce(each.value.instance_type, var.default_instance_type)
  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name
  key_name               = var.key_name # null => SSM-only access (preferred)

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_gb
    encrypted             = true
    kms_key_id            = var.kms_key_id
    delete_on_termination = true
    tags                  = merge(var.tags, { Name = "${var.app_name}-${each.key}-root" })
  }

  # Optional dedicated data volume (Kafka logs, OpenSearch data, PG data...)
  dynamic "ebs_block_device" {
    for_each = var.data_volume_gb > 0 ? [1] : []
    content {
      device_name           = "/dev/xvdb"
      volume_type           = "gp3"
      volume_size           = var.data_volume_gb
      iops                  = var.data_volume_iops
      throughput            = var.data_volume_throughput
      encrypted             = true
      kms_key_id            = var.kms_key_id
      delete_on_termination = false # data survives instance replacement
    }
  }

  user_data_replace_on_change = false # config changes via Ansible, not rebuilds

  tags = merge(var.tags, {
    Name = "${var.app_name}-${var.environment}-${each.key}"
    App  = var.app_name      # drives Ansible dynamic-inventory grouping
    Node = each.key
  })

  lifecycle {
    ignore_changes = [ami] # AMI pointer moving must NOT replace nodes; rotate deliberately
  }
}
