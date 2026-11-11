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
        kms_master_key_id = aws_kms_key.s3.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    enabled = true

    noncurrent_version_transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    noncurrent_version_transition {
      days          = 60
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      days = 365
    }
  }

  logging {
    target_bucket = aws_s3_bucket.access_logging[0].id
    target_prefix = "/logs/"
  }

  replication_configuration {
    role = aws_iam_role.s3_replication.arn

    rule {
      id     = "foobar"
      prefix = ""
      status = "Enabled"

      destination {
        bucket        = aws_s3_bucket.replication.arn
        storage_class = "STANDARD"
      }
    }
  }

  public_access_block {
    block_public_acls   = true
    block_public_policy = true
    ignore_public_acls  = true
    restrict_public_buckets = true
  }
}

resource "aws_s3_bucket" "replication" {
  bucket_prefix = "${var.name}-replication"
  acl    = "private"
  force_destroy = true

  count = var.no_access_logs && (var.no_deletion_protection || var.older_ssl_policy) ? 1 : 0

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  public_access_block {
    block_public_acls   = true
    block_public_policy = true
    ignore_public_acls  = true
    restrict_public_buckets = true
  }
}

resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 10
}

resource "aws_iam_role" "s3_replication" {
  name        = "s3-replication"
  description = "IAM role for S3 replication"

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

resource "aws_iam_policy" "s3_replication" {
  name        = "s3-replication"
  description = "IAM policy for S3 replication"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.access_logging[0].arn,
          "${aws_s3_bucket.access_logging[0].arn}/*",
          aws_s3_bucket.replication[0].arn,
          "${aws_s3_bucket.replication[0].arn}/*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_replication" {
  role       = aws_iam_role.s3_replication.name
  policy_arn = aws_iam_policy.s3_replication.arn
}

resource "aws_wafv2_web_acl" "main" {
  name        = "main-web-acl"
  description = "WAFv2 web ACL for ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "main-web-acl"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_lb.main[0].arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

resource "aws_lb" "main" {
  load_balancer_type = "application"
  enable_deletion_protection = !var.no_deletion_protection
  subnets = ["${var.main_subnet_id}","${var.secondary_subnet_id}"]

  access_logs {
    bucket  = aws_s3_bucket.access_logging[0].id
    enabled = !var.no_access_logs
    prefix  = "/logs/"
  }

  count = (var.older_ssl_policy || var.no_access_logs || var.no_deletion_protection) ? 1 : 0
}

resource "aws_lb_target_group" "main" {
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  count = var.older_ssl_policy ? 1 : 0
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
  ssl_policy        = var.older_ssl_policy ? "ELBSecurityPolicy-TLS-1-0-2015-04" : "ELBSecurityPolicy-TLS-1-2-Ext-2018-06"
  certificate_arn   = aws_iam_server_certificate.main[0].arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main[0].arn
  }

  count = var.older_ssl_policy ? 1 : 0
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