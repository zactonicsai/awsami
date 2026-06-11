output "instance_ids" {
  value = { for k, v in aws_instance.this : k => v.id }
}

output "private_ips" {
  value = { for k, v in aws_instance.this : k => v.private_ip }
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "iam_role_name" {
  value = aws_iam_role.this.name
}
