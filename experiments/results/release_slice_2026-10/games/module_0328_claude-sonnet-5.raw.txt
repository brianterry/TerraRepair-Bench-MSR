resource "aws_s3_bucket" "access_logging" {
  bucket_prefix = var.name
  acl    = "private"
  force_destroy = true

  count = var.no_access_logs && (var.no_deletion_protection || var.older_ssl_policy) ? 1 : 0
}

resource "aws_s3_bucket_versioning" "access_logging" {
  count  = length(aws_s3_bucket.access_logging)
  bucket = aws_s3_bucket.access_logging[count.index].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_kms_key" "access_logging" {
  count                   = length(aws_s3_bucket.access_logging)
  description             = "KMS key for access logging bucket encryption"
  deletion_window_in_days = 10
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logging" {
  count  = length(aws_s3_bucket.access_logging)
  bucket = aws_s3_bucket.access_logging[count.index].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.access_logging[count.index].arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logging" {
  count  = length(aws_s3_bucket.access_logging)
  bucket = aws_s3_bucket.access_logging[count.index].id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_logging" "access_logging" {
  count         = length(aws_s3_bucket.access_logging)
  bucket        = aws_s3_bucket.access_logging[count.index].id
  target_bucket = aws_s3_bucket.access_logging[count.index].id
  target_prefix = "log/"
}

resource "aws_s3_bucket_public_access_block" "access_logging" {
  count                   = length(aws_s3_bucket.access_logging)
  bucket                  = aws_s3_bucket.access_logging[count.index].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_notification" "access_logging" {
  count  = length(aws_s3_bucket.access_logging)
  bucket = aws_s3_bucket.access_logging[count.index].id

  eventbridge = true
}

resource "aws_iam_role" "replication" {
  count = length(aws_s3_bucket.access_logging)
  name  = "${var.name}-s3-replication-role"

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

resource "aws_s3_bucket" "access_logging_replica" {
  count         = length(aws_s3_bucket.access_logging)
  bucket_prefix = "${var.name}-replica"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "access_logging_replica" {
  count  = length(aws_s3_bucket.access_logging_replica)
  bucket = aws_s3_bucket.access_logging_replica[count.index].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_replication_configuration" "access_logging" {
  count      = length(aws_s3_bucket.access_logging)
  depends_on = [aws_s3_bucket_versioning.access_logging]
  bucket     = aws_s3_bucket.access_logging[count.index].id
  role       = aws_iam_role.replication[count.index].arn

  rule {
    id     = "replication-rule"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.access_logging_replica[count.index].arn
      storage_class = "STANDARD"
    }
  }
}

resource "aws_lb" "main" {
  load_balancer_type = "application"
  enable_deletion_protection = !var.no_deletion_protection
  subnets = ["${var.main_subnet_id}","${var.secondary_subnet_id}"]

  access_logs {
    bucket  = aws_s3_bucket.access_logging[0].id
    enabled = !var.no_access_logs
  }

  count = (var.older_ssl_policy || var.no_access_logs || var.no_deletion_protection) ? 1 : 0
}

resource "aws_wafv2_web_acl" "main" {
  count = length(aws_lb.main)
  name  = "${var.name}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "main" {
  count        = length(aws_lb.main)
  resource_arn = aws_lb.main[count.index].arn
  web_acl_arn  = aws_wafv2_web_acl.main[count.index].arn
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

############## Network ##############

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

############## Findings ##############

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