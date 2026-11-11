#--------------------------------------------------------------
# This module is used to create an S3 bucket website
#--------------------------------------------------------------

variable "fqdn"          { }
variable "sub_domain"    { }
variable "route_zone_id" { }
variable "index_page"    { default = "index.html" }
variable "error_page"    { default = "error.html" }
variable "kms_key_id"    { }

resource "aws_kms_key" "website" {
  description             = "KMS key for S3 bucket"
  deletion_window_in_days = 10
}

resource "aws_s3_bucket" "website" {
  bucket = "${var.fqdn}"
  force_destroy = true

  website {
    index_document = "${var.index_page}"
    error_document = "${var.error_page}"
  }

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.website.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  logging {
    target_bucket = "${var.fqdn}-logs"
    target_prefix = "/logs/"
  }

  public_access_block {
    block_public_acls   = true
    block_public_policy = true
    ignore_public_acls  = true
    restrict_public_buckets = true
  }
}

resource "aws_s3_bucket_object" "index" {
  bucket  = "${aws_s3_bucket.website.id}"
  key     = "${var.index_page}"
  content =  <<EOF
You've reached the ${var.fqdn} index page
EOF

  content_type = "text/plain"
  server_side_encryption = "aws:kms"
  kms_key_id = aws_kms_key.website.arn
}

resource "aws_s3_bucket_object" "error" {
  bucket  = "${aws_s3_bucket.website.id}"
  key     = "${var.error_page}"
  content =  <<EOF
You've reached the ${var.fqdn} error page
EOF

  content_type = "text/plain"
  server_side_encryption = "aws:kms"
  kms_key_id = aws_kms_key.website.arn
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${var.fqdn}/*"
    }
  ]
}
EOF
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "website" {
  name = "${var.fqdn}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "website" {
  name        = "${var.fqdn}"
  description = "Policy for S3 bucket"

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

resource "aws_iam_role_policy_attachment" "website" {
  role       = aws_iam_role.website.name
  policy_arn = aws_iam_policy.website.arn
}

resource "aws_route53_record" "website" {
  zone_id = "${var.route_zone_id}"
  name    = "${var.sub_domain}"
  type    = "A"

  alias {
    name                   = "${aws_s3_bucket.website.website_domain}"
    zone_id                = "${aws_s3_bucket.website.hosted_zone_id}"
    evaluate_target_health = false
  }
}

output "domain"         { value = "${aws_s3_bucket.website.website_domain}" }
output "hosted_zone_id" { value = "${aws_s3_bucket.website.hosted_zone_id}" }
output "endpoint"       { value = "${aws_s3_bucket.website.website_endpoint}" }
output "fqdn"           { value = "${aws_route53_record.website.fqdn}" }