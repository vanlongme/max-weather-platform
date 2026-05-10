variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
  default     = "max-weather"
}

variable "vpc_id" {
  description = "VPC ID for the Jenkins security group."
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID to place the Jenkins EC2 instance in."
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile name for Jenkins (provides AWS access without static keys)."
  type        = string
}

variable "key_name" {
  description = "EC2 key pair name for SSH access."
  type        = string
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to access Jenkins port 8080 and SSH port 22. Set to your operator IP /32."
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type for Jenkins."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
