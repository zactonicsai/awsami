output "ami_in_use" {
  description = "Golden AMI resolved from the SSM pointer at plan time"
  value       = data.aws_ssm_parameter.dataapps_ami.value
}

output "kafka_nodes" {
  value = module.kafka.private_ips
}

output "kafka_security_group" {
  value = module.kafka.security_group_id
}
