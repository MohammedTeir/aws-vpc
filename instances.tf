resource "aws_instance" "bastion_ec2" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true
  metadata_options {
  http_tokens = "required"
  }
  root_block_device {
  encrypted = true
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

resource "aws_launch_template" "production_launch_template" {
  name_prefix   = "production-launch-template-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.private_sg.id]
  }

  user_data = base64encode(<<-EOF
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
  )
}

resource "aws_db_instance" "production_rds" {
  identifier                  = "production-rds"
  allocated_storage           = 20
  engine                      = "mysql"
  engine_version              = "8.0"
  instance_class              = "db.t3.micro"
  username                    = var.db_credentials[0]
  parameter_group_name        = "default.mysql8.0"
  skip_final_snapshot         = true
  publicly_accessible         = false
  multi_az                    = true
  vpc_security_group_ids      = [aws_security_group.rds_sg.id]
  db_subnet_group_name        = aws_db_subnet_group.production_db_subnet_group.name
  manage_master_user_password = true
  tags = {
    Name = "production-rds"
  }
}

/* After apply, AWS automatically creates a Secrets Manager secret (you can find its ARN via aws_db_instance.production_rds.master_user_secret[0].secret_arn) — your ASG instances would then need an IAM role permission (secretsmanager:GetSecretValue) scoped to that specific ARN to retrieve it at runtime, completing the least-privilege chain. */

resource "aws_elasticache_cluster" "production_elasticache" {
  cluster_id         = "production-elasticache"
  engine             = "redis"
  node_type          = "cache.t3.micro"
  num_cache_nodes    = 1
  subnet_group_name  = aws_elasticache_subnet_group.production_elasticache_subnet_group.name
  security_group_ids = [aws_security_group.elasticache_sg.id]
}

resource "aws_elasticache_replication_group" "production_elasticache_replication" {
  replication_group_id       = "production-elasticache-replication"
  description                = "Replication group for production ElastiCache"
  node_type                  = "cache.t3.micro"
  num_cache_clusters         = 2
  automatic_failover_enabled = true
  engine                     = "redis"
  subnet_group_name          = aws_elasticache_subnet_group.production_elasticache_subnet_group.name
  security_group_ids         = [aws_security_group.elasticache_sg.id]
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "production_s3_bucket" {
  bucket = "production-s3-bucket-${random_id.bucket_suffix.hex}"
  tags = {
    Name = "production-s3-bucket"
  }
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "production_s3_bucket_versioning" {
  bucket = aws_s3_bucket.production_s3_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "production_s3_bucket_encryption" {
  bucket = aws_s3_bucket.production_s3_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "production_s3_bucket_public_access" {
  bucket = aws_s3_bucket.production_s3_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "production_s3_bucket_lifecycle" {
  bucket = aws_s3_bucket.production_s3_bucket.id

  rule {
    id     = "transition-to-glacier-after-30-days"
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_event_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.production_s3_bucket.arn

}

resource "aws_s3_bucket_notification" "production_s3_bucket_notification" {
  bucket     = aws_s3_bucket.production_s3_bucket.id
  depends_on = [aws_lambda_permission.allow_s3]
  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_event_processor.arn
    events              = ["s3:ObjectCreated:*"]
  }


}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "s3_event_policy" {
  name        = "s3_event_processor_policy"
  path        = "/"
  description = "s3 event processor policy"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowReadFromBucket"
        Action   = ["s3:GetObject"]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.production_s3_bucket.arn}/*"
      },
      {
        Sid      = "AllowSendToQueue"
        Action   = ["sqs:SendMessage"]
        Effect   = "Allow"
        Resource = aws_sqs_queue.s3_event_queue.arn
      }
    ]
  })
}

resource "aws_sqs_queue" "s3_event_dead_letter_queue" {
  name = "s3_event_dead_letter_queue"


}

resource "aws_sqs_queue" "s3_event_queue" {
  name = "s3_event_queue"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.s3_event_dead_letter_queue.arn
    maxReceiveCount     = 3
  })

}

resource "aws_iam_role_policy" "s3_event_processor_policy" {
  name   = "s3_event_processor_policy"
  role   = aws_iam_role.lambda_role.id
  policy = aws_iam_policy.s3_event_policy.policy

}


resource "aws_lambda_function" "s3_event_processor" {
  function_name = "s3_event_processor"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  filename      = "lambda_function_payload.zip"

  source_code_hash = filebase64sha256("lambda_function_payload.zip")
}

resource "aws_iam_role" "config_role" {
  name = "config_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "config_policy" {
  name        = "config_policy"
  path        = "/"
  description = "Policy for AWS Config"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetBucketAcl",
          "s3:GetBucketLocation"
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.production_s3_bucket.arn}/*"
      },
      {
        Action = [
          "sns:Publish"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })

}


resource "aws_iam_role_policy" "iam_role_policy" {
  name   = "config_role_policy"
  role   = aws_iam_role.config_role.id
  policy = aws_iam_policy.config_policy.policy
}

resource "aws_iam_role_policy_attachment" "config_managed_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "config_recorder" {
  name     = "config_recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported = true
  }

}

resource "aws_config_configuration_recorder_status" "recorder_status" {
  name       = aws_config_configuration_recorder.config_recorder.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.config_delivery_channel]
}

resource "aws_config_delivery_channel" "config_delivery_channel" {
  name           = "config_delivery_channel"
  s3_bucket_name = aws_s3_bucket.production_s3_bucket.bucket

}

resource "aws_config_config_rule" "restricted_ssh" {
  name = "restricted-ssh"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
}

resource "aws_config_config_rule" "s3_bucket_public_read_prohibited" {
  name = "s3-bucket-public-read-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

}


resource "aws_config_config_rule" "rds_instance_public_access_check" {
  name = "rds-instance-public-access-check"

  source {
    owner             = "AWS"
    source_identifier = "RDS_INSTANCE_PUBLIC_ACCESS_CHECK"
  }

}
resource "aws_guardduty_detector" "guardduty_detector" {
  enable = true
  datasources {
    s3_logs {
      enable = true
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }
}

resource "aws_cloudtrail" "cloudtrail" {
  name                          = "cloudtrail"
  s3_bucket_name                = aws_s3_bucket.production_s3_bucket.bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  depends_on                    = [aws_s3_bucket_policy.combined_bucket_policy]

}

resource "aws_s3_bucket_policy" "combined_bucket_policy" {
  bucket = aws_s3_bucket.production_s3_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.production_s3_bucket.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.production_s3_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Sid       = "AWSConfigBucketPermissionsCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.production_s3_bucket.arn
      },
      {
        Sid       = "AWSConfigBucketExistenceCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.production_s3_bucket.arn
      },
      {
        Sid       = "AWSConfigBucketDelivery"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.production_s3_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "target_response_time_alarm" {
  alarm_name          = "TargetResponseTimeAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Alarm when the target response time exceeds 1 seconds"
  dimensions = {
    LoadBalancer = aws_lb.production_alb.arn_suffix
    TargetGroup  = aws_lb_target_group.production_lb_target_group_http.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "http_code_target_5xx_count_alarm" {
  alarm_name          = "HTTPCodeTarget5XXCountAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alarm when the number of HTTP 5XX responses exceeds 5"
  dimensions = {
    LoadBalancer = aws_lb.production_alb.arn_suffix
    TargetGroup  = aws_lb_target_group.production_lb_target_group_http.arn_suffix
  }
}

