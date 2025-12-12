variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "key_name" {
  description = "SSH key name"
  type        = string
  default     = "devops-webapp-key"
}