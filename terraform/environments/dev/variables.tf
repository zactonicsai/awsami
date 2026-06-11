variable "region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "ami_family" {
  type        = string
  default     = "al2023-base"
  description = "Selects SSM pointer /dataapps/ami/<family>/latest"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "At least 3 subnets across AZs for quorum-based apps"
}

variable "client_cidr_blocks" {
  type    = list(string)
  default = ["10.0.0.0/8"]
}

variable "kafka_instance_type" {
  type    = string
  default = "m6i.large"
}

variable "owner" {
  type    = string
  default = "cloud-team"
}

variable "cost_center" {
  type    = string
  default = "data-apps"
}
