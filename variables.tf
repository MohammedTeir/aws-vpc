variable "aws_region" {
  description = "AWS region for the deployment"
  type        = string
  default     = "us-east-1"
}

variable "aws_dr_region" {
  description = "AWS region for disaster recovery"
  type        = string
  default     = "eu-west-1"
}

variable "aws_alias_name" {

  description = "Alias name for the AWS provider"
  type        = string
  default     = "dr_region"

}

variable "db_credentials" {
  description = "Database credentials in the format username:password"
  type        = list(string)
  sensitive   = true
  default     = ["dbadmin", "SecurePass123"]

}

variable "aws_profile" {
  description = "AWS CLI profile used for authentication"
  type        = string
  default     = "midoprofile"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "dr_vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_cidr_dr" {
  description = "CIDR block for the public subnet"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}



variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "private_subnet_cidr_dr" {
  description = "CIDR block for the private subnet"
  type        = list(string)
  default     = ["10.1.3.0/24", "10.1.4.0/24"]

}
variable "ssh_cidr" {
  description = "Source CIDR allowed to reach the bastion over SSH"
  type        = string
  default     = "213.6.237.149/32"
}

variable "ami_id" {
  description = "AMI ID for the EC2 instances"
  type        = string
  default     = "ami-0f8a61b66d1accaee"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Key pair name for EC2 SSH access"
  type        = string
  default     = "mohammed-aws-key"
}
