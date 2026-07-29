resource "aws_instance" "bastion_ec2" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              set -e
              sudo apt-get update -y
              sudo apt-get install -y nginx openssl
              sudo mkdir -p /etc/nginx/certs
              sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout /etc/nginx/certs/nginx.key \
                -out /etc/nginx/certs/nginx.crt \
                -subj "/CN=$(hostname)" \
                -addext "subjectAltName=DNS:$(hostname),IP:127.0.0.1"
              sudo tee /etc/nginx/sites-available/default > /dev/null <<'NGINX'
              server {
                  listen 80 default_server;
                  listen [::]:80 default_server;
                  server_name _;
                  root /var/www/html;
                  index index.html;
              }

              server {
                  listen 443 ssl default_server;
                  listen [::]:443 ssl default_server;
                  server_name _;

                  ssl_certificate /etc/nginx/certs/nginx.crt;
                  ssl_certificate_key /etc/nginx/certs/nginx.key;

                  root /var/www/html;
                  index index.html;
              }
              NGINX
              sudo systemctl enable nginx
              sudo systemctl restart nginx
              echo "Hello from Bastion Host" > /var/www/html/index.html
              EOF

  tags = {
    Name = "-bastion-ec2"
  }
}

resource "aws_instance" "private_ec2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.private_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              set -e
              sudo apt-get update -y
              sudo apt-get install -y nginx openssl
              sudo mkdir -p /etc/nginx/certs
              sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout /etc/nginx/certs/nginx.key \
                -out /etc/nginx/certs/nginx.crt \
                -subj "/CN=$(hostname)" \
                -addext "subjectAltName=DNS:$(hostname),IP:127.0.0.1"
              sudo systemctl enable nginx
              sudo systemctl restart nginx
              echo "Hello from Private Host" > /var/www/html/index.html
              EOF

  tags = {
    Name = "private-ec2"
  }
}

resource "aws_launch_template" "production_launch_template" {
  name_prefix   = "production-launch-template-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.private_sg.id]
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e
              sudo apt-get update -y
              sudo apt-get install -y nginx openssl
              sudo mkdir -p /etc/nginx/certs
              sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout /etc/nginx/certs/nginx.key \
                -out /etc/nginx/certs/nginx.crt \
                -subj "/CN=$(hostname)" \
                -addext "subjectAltName=DNS:$(hostname),IP:127.0.0.1"
              sudo systemctl enable nginx
              sudo systemctl restart nginx
              echo "Hello from Private Host" > /var/www/html/index.html
              EOF
}