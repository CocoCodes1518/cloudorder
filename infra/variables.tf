variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix for cloud resources"
  type        = string
  default     = "cloudorder"
}
