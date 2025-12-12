# Terraform variables.tf
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "devops-webapp"
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "production"
}

variable "key_name" {
  description = "SSH key name"
  type        = string
  default     = "devops-key"
}