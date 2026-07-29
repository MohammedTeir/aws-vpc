output "bastion_private_ip" {
  description = "Private IP address of the bastion EC2 instance"
  value       = aws_instance.bastion_ec2.private_ip
}


output "vpc_id" {
  description = "ID of the deployed VPC"
  value       = aws_vpc.production_vpc.id
}
