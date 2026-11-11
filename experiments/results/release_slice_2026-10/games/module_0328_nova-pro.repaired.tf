resource "aws_s3_bucket" "access_logging" {
  bucket_prefix = var.name
  acl    = "private"
  force_destroy = true

  count = var.no_access_logs && (var.no_deletion_protection || var.older_ssl_policy) ? 1 : 0

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
      }
    }
  }

  public_access_block {
    block_public_acls    = true
    block_public_policy  = true
    ignore_public_acls   = true
    restrict_public_buckets = true
  }

  lifecycle_rule {
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }
  }

  replication_configuration {
    role = aws_iam_role.s3_replication.arn

    rule {
      status = "Enabled"

      destination {
        bucket = "arn:aws:s3:::destination-bucket"
      }

      delete_marker_replication {
        status = "Enabled"
      }
    }
  }
}

resource "aws_lb" "main" {
  load_balancer_type = "application"
  enable_deletion_protection =!var.no_deletion_protection
  subnets = ["${var.main_subnet_id}","${var.secondary_subnet_id}"]

  access_logs {
    bucket  = aws_s3_bucket.access_logging[0].bucket_prefix
    enabled =!var.no_access_logs
  }

  count = (var.older_ssl_policy || var.no_access_logs || var.no_deletion_protection)? 1 : 0

  dynamic "listener" {
    for_each = var.older_ssl_policy ? [1] : []
    content {
      port              = "443"
      protocol          = "HTTPS"
      ssl_policy        = var.older_ssl_policy? "ELBSecurityPolicy-TLS-1-0-2015-04" : "ELBSecurityPolicy-TLS-1-2-Ext-2018-06"
      certificate_arn   = aws_iam_server_certificate.main[0].arn

      default_action {
        type             = "forward"
        target_group_arn = aws_lb_target_group.main[0].arn
      }
    }
  }
}

resource "aws_lb_target_group" "main" {
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  count = var.older_ssl_policy? 1 : 0
}

resource "aws_iam_server_certificate" "main" {
  name = "test_cert"
  certificate_body = file(
    "${path.root}/static/example.crt.pem",
  )
  private_key = file(
    "${path.root}/static/example.key.pem",
  )

  count = var.older_ssl_policy ? 1 : 0
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main[0].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = var.older_ssl_policy? "ELBSecurityPolicy-TLS-1-0-2015-04" : "ELBSecurityPolicy-TLS-1-2-Ext-2018-06"
  certificate_arn   = aws_iam_server_certificate.main[0].arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main[0].arn
  }

  count = var.older_ssl_policy? 1 : 0
}

resource "aws_wafregional_web_acl" "main" {
  name        = "waf-acl"
  metric_name = "waf-acl"

  default_action {
    type = "ALLOW"
  }
}

resource "aws_wafregional_web_acl_association" "main" {
  resource_arn = aws_lb.main[0].arn
  web_acl_id   = aws_wafregional_web_acl.main.id
}

resource "aws_iam_role" "s3_replication" {
  name = "s3_replication_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_replication" {
  name = "s3_replication_policy"
  role = aws_iam_role.s3_replication.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.access_logging[0].bucket}",
          "arn:aws:s3:::${aws_s3_bucket.access_logging[0].bucket}/*"
        ]
      }
    ]
  })
}

variable "name" {
  description = "elbv2 name"
  type        = string
  default     = "sadelb"
}

variable "vpc_id" {
  description = "ID of created VPC"
  default = "default_vpc_id"
}

variable "main_subnet_id" {
  description = "ID of main subnet"
  default = "default_main_subnet_id"
}

variable "secondary_subnet_id" {
  description = "ID of secondary subnet"
  default = "default_secondary_subnet_id"
}

variable "no_access_logs" {
  description = "No elbv2 access logs configured"
  type        = bool
  default     = false
}

variable "no_deletion_protection" {
  description = "No elbv2 deletion protection"
  type        = bool
  default     = false
}

variable "older_ssl_policy" {
  description = "No elbv2 deletion protection"
  type        = bool
  default     = false
}