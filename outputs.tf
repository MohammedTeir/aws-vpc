output "bastion_public_ip" {
  description = "Public IP address of the bastion EC2 instance"
  value       = aws_eip.alb_eip.public_ip
}

output "bastion_private_ip" {
  description = "Private IP address of the bastion EC2 instance"
  value       = aws_instance.bastion_ec2.private_ip
}

output "private_instance_private_ip" {
  description = "Private IP address of the private EC2 instance"
  value       = aws_instance.private_ec2.private_ip
}

output "vpc_id" {
  description = "ID of the deployed VPC"
  value       = aws_vpc.production_vpc.id
}
