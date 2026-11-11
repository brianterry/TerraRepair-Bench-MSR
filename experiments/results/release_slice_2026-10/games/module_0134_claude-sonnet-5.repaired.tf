#--------------------------------------------------------------
# This module is used to create an S3 bucket website
#--------------------------------------------------------------

variable "fqdn"          { }
variable "sub_domain"    { }
variable "route_zone_id" { }
variable "index_page"    { default = "index.html" }
variable "error_page"    { default = "error.html" }

resource "aws_kms_key" "website" {
  description         = "KMS key used to encrypt the website bucket"
  enable_key_rotation  = true
}

resource "aws_s3_bucket" "website" {
  bucket        = "${var.fqdn}"
  force_destroy = true

  website {
    index_document = "${var.index_page}"
    error_document = "${var.error_page}"
  }
}

resource "aws_s3_bucket_acl" "website" {
  bucket = "${aws_s3_bucket.website.id}"
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "website" {
  bucket = "${aws_s3_bucket.website.id}"

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = "${aws_s3_bucket.website.id}"

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = "${aws_kms_key.website.arn}"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = "${aws_s3_bucket.website.id}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "website" {
  bucket = "${aws_s3_bucket.website.id}"

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket" "website_logs" {
  bucket        = "${var.fqdn}-logs"
  force_destroy = true
}

resource "aws_s3_bucket_acl" "website_logs" {
  bucket = "${aws_s3_bucket.website_logs.id}"
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket_versioning" "website_logs" {
  bucket = "${aws_s3_bucket.website_logs.id}"

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "website_logs" {
  bucket = "${aws_s3_bucket.website_logs.id}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "website" {
  bucket = "${aws_s3_bucket.website.id}"

  target_bucket = "${aws_s3_bucket.website_logs.id}"
  target_prefix = "log/"
}

resource "aws_s3_bucket_object" "index" {
  bucket  = "${aws_s3_bucket.website.id}"
  key     = "${var.index_page}"
  content =  <<EOF
You've reached the ${var.fqdn} index page
EOF

  content_type            = "text/plain"
  server_side_encryption  = "aws:kms"
  kms_key_id              = "${aws_kms_key.website.arn}"
}

resource "aws_s3_bucket_object" "error" {
  bucket  = "${aws_s3_bucket.website.id}"
  key     = "${var.error_page}"
  content =  <<EOF
You've reached the ${var.fqdn} error page
EOF

  content_type            = "text/plain"
  server_side_encryption  = "aws:kms"
  kms_key_id              = "${aws_kms_key.website.arn}"
}

resource "aws_iam_user" "website" {
  name = "${var.fqdn}"
}

resource "aws_iam_access_key" "website" {
  user = "${aws_iam_user.website.name}"
}

resource "aws_iam_group" "website" {
  name = "${var.fqdn}-group"
}

resource "aws_iam_group_policy" "website" {
  name  = "${var.fqdn}"
  group = "${aws_iam_group.website.name}"
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

resource "aws_iam_group_membership" "website" {
  name  = "${var.fqdn}-group-membership"
  users = ["${aws_iam_user.website.name}"]
  group = "${aws_iam_group.website.name}"
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