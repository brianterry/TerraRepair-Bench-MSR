#--------------------------------------------------------------
# This module is used to create an S3 bucket website
#--------------------------------------------------------------

variable "fqdn"          { }
variable "sub_domain"    { }
variable "route_zone_id" { }
variable "index_page"    { default = "index.html" }
variable "error_page"    { default = "error.html" }

resource "aws_kms_key" "s3_encryption_key" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 10
}

resource "aws_s3_bucket" "website" {
  bucket = "${var.fqdn}"
  force_destroy = true

  website {
    index_document = "${var.index_page}"
    error_document = "${var.error_page}"
  }

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPublicRead",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${var.fqdn}/*"
    }
  ]
}
EOF

  versioning {
    enabled = true
  }

  logging {
    target_bucket = self.bucket
    target_prefix = "logs/"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3_encryption_key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_object" "index" {
  bucket  = "${aws_s3_bucket.website.id}"
  key     = "${var.index_page}"
  content =  <<EOF
You've reached the ${var.fqdn} index page
EOF

  content_type = "text/plain"
  server_side_encryption = "aws:kms"
  kms_key_id = aws_kms_key.s3_encryption_key.arn
}

resource "aws_s3_bucket_object" "error" {
  bucket  = "${aws_s3_bucket.website.id}"
  key     = "${var.error_page}"
  content =  <<EOF
You've reached the ${var.fqdn} error page
EOF

  content_type = "text/plain"
  server_side_encryption = "aws:kms"
  kms_key_id = aws_kms_key.s3_encryption_key.arn
}

resource "aws_iam_user" "website" {
  name = "${var.fqdn}"
}

resource "aws_iam_access_key" "website" {
  user = "${aws_iam_user.website.name}"
}

resource "aws_iam_user_policy" "website" {
  name = "${var.fqdn}"
  user = "${aws_iam_user.website.name}"
  policy = <<EOF
{
  "Version": "2012-10-17",
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
    name                   = "${aws_s3_bucket.website.website_domain}"
    zone_id                = "${aws_s3_bucket.website.hosted_zone_id}"
    evaluate_target_health = false
  }
}

output "domain"         { value = "${aws_s3_bucket.website.website_domain}" }
output "hosted_zone_id" { value = "${aws_s3_bucket.website.hosted_zone_id}" }
output "endpoint"       { value = "${aws_s3_bucket.website.website_endpoint}" }
output "fqdn"           { value = "${aws_route53_record.website.fqdn}" }