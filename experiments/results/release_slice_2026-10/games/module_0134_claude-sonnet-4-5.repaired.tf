variable "fqdn"          { }
variable "sub_domain"    { }
variable "route_zone_id" { }
variable "index_page"    { default = "index.html" }
variable "error_page"    { default = "error.html" }

resource "aws_kms_key" "website" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 10
}

resource "aws_s3_bucket" "website_logs" {
  bucket        = "${var.fqdn}-logs"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website_logs" {
  bucket = aws_s3_bucket.website_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "website_logs" {
  bucket = aws_s3_bucket.website_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "website" {
  bucket        = "${var.fqdn}"
  force_destroy = true
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "${var.index_page}"
  }

  error_document {
    key = "${var.error_page}"
  }
}

resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "website" {
  bucket = aws_s3_bucket.website.id

  target_bucket = aws_s3_bucket.website_logs.id
  target_prefix = "log/"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.website.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    id     = "default"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_notification" "website" {
  bucket = aws_s3_bucket.website.id
}

resource "aws_s3_bucket_replication_configuration" "website" {
  bucket = aws_s3_bucket.website.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "replication"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.website_replica.arn
      storage_class = "STANDARD"
    }
  }

  depends_on = [aws_s3_bucket_versioning.website]
}

resource "aws_s3_bucket" "website_replica" {
  bucket   = "${var.fqdn}-replica"
  provider = aws.replica
}

resource "aws_s3_bucket_versioning" "website_replica" {
  bucket   = aws_s3_bucket.website_replica.id
  provider = aws.replica

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "replication" {
  name = "${var.fqdn}-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "replication" {
  name = "${var.fqdn}-replication"
  role = aws_iam_role.replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.website.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl"
        ]
        Resource = "${aws_s3_bucket.website.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Resource = "${aws_s3_bucket.website_replica.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = ""
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.website.arn
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_object" "index" {
  bucket  = "${aws_s3_bucket.website.id}"
  key     = "${var.index_page}"
  content = <<EOF
You've reached the ${var.fqdn} index page
EOF

  content_type      = "text/plain"
  kms_key_id        = aws_kms_key.website.arn
  server_side_encryption = "aws:kms"
}

resource "aws_s3_bucket_object" "error" {
  bucket  = "${aws_s3_bucket.website.id}"
  key     = "${var.error_page}"
  content = <<EOF
You've reached the ${var.fqdn} error page
EOF

  content_type      = "text/plain"
  kms_key_id        = aws_kms_key.website.arn
  server_side_encryption = "aws:kms"
}

resource "aws_iam_user" "website" {
  name = "${var.fqdn}"
}

resource "aws_iam_access_key" "website" {
  user = "${aws_iam_user.website.name}"
}

resource "aws_iam_group" "website" {
  name = "${var.fqdn}"
}

resource "aws_iam_user_group_membership" "website" {
  user = aws_iam_user.website.name

  groups = [
    aws_iam_group.website.name
  ]
}

resource "aws_iam_group_policy" "website" {
  name  = "${var.fqdn}"
  group = aws_iam_group.website.name
  policy = <<EOF
{
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::${aws_s3_bucket.website.id}/*"
    }
  ]
}
EOF
}

resource "aws_route53_record" "website" {
  zone_id = "${var.route_zone_id}"
  name    = "${var.sub_domain}"
  type    = "A"

  alias {
    name                   = "${aws_s3_bucket_website_configuration.website.website_domain}"
    zone_id                = "${aws_s3_bucket.website.hosted_zone_id}"
    evaluate_target_health = false
  }
}

output "domain"         { value = "${aws_s3_bucket_website_configuration.website.website_domain}" }
output "hosted_zone_id" { value = "${aws_s3_bucket.website.hosted_zone_id}" }
output "endpoint"       { value = "${aws_s3_bucket_website_configuration.website.website_endpoint}" }
output "fqdn"           { value = "${aws_route53_record.website.fqdn}" }

provider "aws" {
  alias = "replica"
}