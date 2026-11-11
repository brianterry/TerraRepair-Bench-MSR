#--------------------------------------------------------------
# This module is used to create an S3 bucket website
#--------------------------------------------------------------

variable "fqdn"          { }
variable "sub_domain"    { }
variable "route_zone_id" { }
variable "index_page"    { default = "index.html" }
variable "error_page"    { default = "error.html" }

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
        sse_algorithm = "aws:kms"
        kms_master_key_id = "alias/aws/s3"
      }
    }
  }

  lifecycle_rule {
    id      = "log-bucket-access"
    enabled = true

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }
  }

  public_access_block_configuration {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls       = true
    restrict_public_buckets = true
  }

  logging {
    target_bucket = "log-bucket"
    target_prefix = "logs/"
  }

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
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
}

resource "aws_s3_bucket_object" "index" {
  bucket  = "${aws_s3_bucket.website.id}"
  key     = "${var.index_page}"
  content =  <<EOF
You've reached the ${var.fqdn} index page
EOF

  content_type = "text/plain"
  server_side_encryption = "aws:kms"
  server_side_encryption_aws_kms_key_id = "alias/aws/s3"
}

resource "aws_s3_bucket_object" "error" {
  bucket  = "${aws_s3_bucket.website.id}"
  key     = "${var.error_page}"
  content =  <<EOF
You've reached the ${var.fqdn} error page
EOF

  content_type = "text/plain"
  server_side_encryption = "aws:kms"
  server_side_encryption_aws_kms_key_id = "alias/aws/s3"
}

resource "aws_iam_user" "website" {
  name = "${var.fqdn}"
}

resource "aws_iam_user_policy" "website" {
  name = "${var.fqdn}"
  user = "${aws_iam_user.website.name}"

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
    name                   = "${aws_s3_bucket.website.website_domain}"
    zone_id                = "${aws_s3_bucket.website.hosted_zone_id}"
    evaluate_target_health = false
  }
}

output "domain"         { value = "${aws_s3_bucket.website.website_domain}" }
output "hosted_zone_id" { value = "${aws_s3_bucket.website.hosted_zone_id}" }
output "endpoint"       { value = "${aws_s3_bucket.website.website_endpoint}" }
output "fqdn"           { value = "${aws_route53_record.website.fqdn}" }