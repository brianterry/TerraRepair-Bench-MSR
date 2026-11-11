#--------------------------------------------------------------
# This module is used to create an S3 bucket website
#--------------------------------------------------------------

variable "fqdn"          { }
variable "sub_domain"    { }
variable "route_zone_id" { }
variable "index_page"    { default = "index.html" }
variable "error_page"    { default = "error.html" }

resource "aws_kms_key" "website" {
  description         = "${var.fqdn} S3 encryption key"
  enable_key_rotation = true
}

resource "aws_s3_bucket" "logs" {
  bucket        = "${var.fqdn}-logs"
  acl           = "log-delivery-write"
  force_destroy = true

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  lifecycle_rule {
    enabled = true

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket" "replica" {
  bucket        = "${var.fqdn}-replica"
  acl           = "private"
  force_destroy = true

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = "${aws_kms_key.website.arn}"
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    enabled = true

    noncurrent_version_expiration {
      days = 90
    }
  }
}

resource "aws_iam_role" "replication" {
  name = "${var.fqdn}-replication"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "replication" {
  name = "${var.fqdn}-replication"
  role = "${aws_iam_role.replication.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetReplicationConfiguration",
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::${var.fqdn}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObjectVersionForReplication",
        "s3:GetObjectVersionAcl",
        "s3:GetObjectVersionTagging"
      ],
      "Resource": "arn:aws:s3:::${var.fqdn}/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateDelete",
        "s3:ReplicateTags"
      ],
      "Resource": "arn:aws:s3:::${var.fqdn}-replica/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "${aws_kms_key.website.arn}"
    }
  ]
}
EOF
}

resource "aws_s3_bucket" "website" {
  bucket        = "${var.fqdn}"
  acl           = "private"
  force_destroy = true

  website {
    index_document = "${var.index_page}"
    error_document = "${var.error_page}"
  }

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "${aws_s3_bucket.logs.id}"
    target_prefix = "logs/"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = "${aws_kms_key.website.arn}"
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    enabled = true

    noncurrent_version_expiration {
      days = 90
    }
  }

  replication_configuration {
    role = "${aws_iam_role.replication.arn}"

    rules {
      id     = "replica"
      status = "Enabled"
      prefix = ""

      destination {
        bucket             = "${aws_s3_bucket.replica.arn}"
        storage_class      = "STANDARD"
        replica_kms_key_id = "${aws_kms_key.website.arn}"
      }

      source_selection_criteria {
        sse_kms_encrypted_objects {
          enabled = true
        }
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = "${aws_s3_bucket.website.id}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = "${aws_s3_bucket.logs.id}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "replica" {
  bucket = "${aws_s3_bucket.replica.id}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_object" "index" {
  bucket  = "${aws_s3_bucket.website.id}"
  key     = "${var.index_page}"
  content = <<EOF
You've reached the ${var.fqdn} index page
EOF

  content_type           = "text/plain"
  server_side_encryption = "aws:kms"
  kms_key_id             = "${aws_kms_key.website.arn}"
}

resource "aws_s3_bucket_object" "error" {
  bucket  = "${aws_s3_bucket.website.id}"
  key     = "${var.error_page}"
  content = <<EOF
You've reached the ${var.fqdn} error page
EOF

  content_type           = "text/plain"
  server_side_encryption = "aws:kms"
  kms_key_id             = "${aws_kms_key.website.arn}"
}

resource "aws_sns_topic" "website" {
  name = "${replace(var.fqdn, ".", "-")}-notifications"
}

resource "aws_sns_topic_policy" "website" {
  arn = "${aws_sns_topic.website.arn}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "SNS:Publish",
      "Resource": "${aws_sns_topic.website.arn}",
      "Condition": {
        "ArnLike": {
          "aws:SourceArn": "${aws_s3_bucket.website.arn}"
        }
      }
    }
  ]
}
EOF
}

resource "aws_s3_bucket_notification" "website" {
  bucket = "${aws_s3_bucket.website.id}"

  topic {
    topic_arn = "${aws_sns_topic.website.arn}"
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = ["aws_sns_topic_policy.website"]
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