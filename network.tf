resource "aws_vpc" "production_vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "production-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.production_vpc.id
  cidr_block        = var.public_subnet_cidr[0]
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "public-subnet"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.production_vpc.id
  cidr_block        = var.public_subnet_cidr[1]
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "public-subnet-2"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.production_vpc.id
  cidr_block        = var.private_subnet_cidr[0]
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "private-subnet"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.production_vpc.id
  cidr_block        = var.private_subnet_cidr[1]
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "private-subnet-2"
  }
}

resource "aws_internet_gateway" "production_igw" {
  vpc_id = aws_vpc.production_vpc.id

  tags = {
    Name = "production-igw"
  }
}

resource "aws_eip" "alb_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.production_igw]
}

resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.production_igw]
}

resource "aws_nat_gateway" "production_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id
  depends_on    = [aws_internet_gateway.production_igw]

  tags = {
    Name = "production-nat"
  }
}

resource "aws_route_table" "public_route" {
  vpc_id = aws_vpc.production_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.production_igw.id
  }
}

resource "aws_route_table" "private_route" {
  vpc_id = aws_vpc.production_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.production_nat.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route.id
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route.id
}

resource "aws_lb" "production_alb" {
  name                       = "production-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
  subnets                    = [aws_subnet.public_subnet.id, aws_subnet.public_subnet_2.id]
  enable_deletion_protection = true

  subnet_mapping {
    subnet_id     = aws_subnet.public_subnet.id
    allocation_id = aws_eip.alb_eip.id
  }
  subnet_mapping {
    subnet_id     = aws_subnet.public_subnet_2.id
    allocation_id = aws_eip.alb_eip.id
  }


  tags = {
    Name = "production-alb"
  }
}

resource "aws_lb_target_group" "production_lb_target_group_http" {
  name     = "production-target-group-http"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.production_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-299"
  }

  tags = {
    Name = "production-target-group-http"
  }
}

resource "aws_lb_target_group" "production_lb_target_group_https" {
  name     = "production-target-group-https"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.production_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-299"
  }

  tags = {
    Name = "production-target-group-https"
  }
}

resource "aws_lb_listener" "lb_listener_http" {
  load_balancer_arn = aws_lb.production_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.production_lb_target_group_http.arn
  }
}

resource "aws_lb_listener" "lb_listener_https" {
  load_balancer_arn = aws_lb.production_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:iam::187416307283:server-certificate/test_cert_rab3wuqwgja25ct3n4jdj2tzu4"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.production_lb_target_group_https.arn
  }
}

resource "aws_autoscaling_group" "production_asg" {
  desired_capacity          = 2
  max_size                  = 4
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  vpc_zone_identifier       = [aws_subnet.private_subnet.id, aws_subnet.private_subnet_2.id]
  target_group_arns         = [aws_lb_target_group.production_lb_target_group_http.arn, aws_lb_target_group.production_lb_target_group_https.arn]
  launch_template {
    id      = aws_launch_template.production_launch_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "production-asg"
    propagate_at_launch = true
  }
}

