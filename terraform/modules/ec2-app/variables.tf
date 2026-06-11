variable "app_name" {
  type        = string
  description = "Application name (kafka, zookeeper, nifi, opensearch, postgres, <java-app>)"
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "ami_id" {
  type        = string
  description = "Resolved AMI id. Root module reads the SSM pointer /dataapps/ami/<family>/latest"
}

variable "nodes" {
  description = "Map of node-name => { subnet_id, optional instance_type }. Map keys are STABLE addresses."
  type = map(object({
    subnet_id     = string
    instance_type = optional(string)
  }))
}

variable "default_instance_type" {
  type    = string
  default = "m6i.large"
}

variable "key_name" {
  type        = string
  default     = null
  description = "EC2 key pair. Leave null for SSM-only access (recommended)."
}

variable "root_volume_gb" {
  type    = number
  default = 30
}

variable "data_volume_gb" {
  type        = number
  default     = 0
  description = "0 = no data volume; >0 attaches encrypted gp3 at /dev/xvdb (delete_on_termination=false)"
}

variable "data_volume_iops" {
  type    = number
  default = 3000
}

variable "data_volume_throughput" {
  type    = number
  default = 125
}

variable "kms_key_id" {
  type    = string
  default = null
}

variable "ingress_rules" {
  description = "App ingress. Intra-cluster self-traffic is always allowed."
  type = list(object({
    description     = string
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string), [])
    security_groups = optional(list(string), [])
  }))
  default = []
}

variable "extra_policy_arns" {
  type        = list(string)
  default     = []
  description = "Additional IAM policy ARNs (e.g., S3 read for app artifacts)"
}

variable "tags" {
  type    = map(string)
  default = {}
}
