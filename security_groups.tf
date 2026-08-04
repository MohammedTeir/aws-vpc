resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Allow SSH and outbound internet access"
  vpc_id      = aws_vpc.production_vpc.id

  tags = {
    Name = "bastion-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  security_group_id = aws_security_group.bastion_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_https_ipv4" {
  security_group_id = aws_security_group.bastion_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.bastion_sg.id
  cidr_ipv4         = var.ssh_cidr
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}


resource "aws_vpc_security_group_egress_rule" "allow_https_ipv4" {
  security_group_id = aws_security_group.bastion_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}
resource "aws_vpc_security_group_egress_rule" "allow_dns_tcp" {
  security_group_id = aws_security_group.bastion_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 53
  ip_protocol       = "tcp"
  to_port           = 53
}
resource "aws_vpc_security_group_egress_rule" "allow_dns_udp" {
  security_group_id = aws_security_group.bastion_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 53
  ip_protocol       = "udp"
  to_port           = 53
}

resource "aws_security_group" "private_sg" {
  name        = "private-sg"
  description = "Allow outbound internet access"
  vpc_id      = aws_vpc.production_vpc.id

  tags = {
    Name = "private-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_from_bastion" {
  security_group_id            = aws_security_group.private_sg.id
  referenced_security_group_id = aws_security_group.bastion_sg.id
  from_port                    = 22
  ip_protocol                  = "tcp"
  to_port                      = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4_private" {
  security_group_id = aws_security_group.private_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_from_alb" {
  security_group_id            = aws_security_group.private_sg.id
  referenced_security_group_id = aws_security_group.alb_sg.id
  from_port                    = 80
  ip_protocol                  = "tcp"
  to_port                      = 80
}

resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow inbound HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.production_vpc.id

  tags = {
    Name = "alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4_alb" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_https_ipv4_alb" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4_alb" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow inbound MySQL traffic from private instances"
  vpc_id      = aws_vpc.production_vpc.id

  tags = {
    Name = "rds-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_mysql_from_private" {
  security_group_id            = aws_security_group.rds_sg.id
  referenced_security_group_id = aws_security_group.private_sg.id
  from_port                    = 3306
  ip_protocol                  = "tcp"
  to_port                      = 3306
}

resource "aws_security_group" "elasticache_sg" {
  name        = "elasticache-sg"
  description = "Allow inbound Redis traffic from private instances"
  vpc_id      = aws_vpc.production_vpc.id

  tags = {
    Name = "elasticache-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_redis_from_private" {
  security_group_id            = aws_security_group.elasticache_sg.id
  referenced_security_group_id = aws_security_group.private_sg.id
  from_port                    = 6379
  ip_protocol                  = "tcp"
  to_port                      = 6379
}