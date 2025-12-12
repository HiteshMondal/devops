# Terraform outputs.tf
output "instance_public_ip" {
  description = "Public IP of EC2 instance"
  value       = aws_instance.webapp.public_ip
}

output "instance_id" {
  description = "ID of EC2 instance"
  value       = aws_instance.webapp.id
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}