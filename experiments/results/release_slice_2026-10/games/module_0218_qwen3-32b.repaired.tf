resource "aws_s3_bucket" "registry-k8s-io" {
  bucket = "${var.prefix}registry-k8s-io-${data.aws_region.current.name}"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
      }
    }
  }

  versioning {
    enabled = true
  }

  logging {
    target_bucket = self.id
    target_prefix = "logs/"
  }

  lifecycle_rule {
    id      = "default"
    enabled = true
    expiration {
      days = 365
    }
  }

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Deny",
        "Principal": "*",
        "Action": "s3:PutACL",
        "Resource": [
          "${aws_s3_bucket.registry-k8s-io.arn}",
          "${aws_s3_bucket.registry-k8s-io.arn}/*"
        ],
        "Condition": {
          "StringNotEquals": {
            "aws:SourceOwner": "self"
          }
        }
      },
      {
        "Effect": "Deny",
        "Principal": "*",
        "Action": "s3:PutObject",
        "Resource": "${aws_s3_bucket.registry-k8s-io.arn}/*",
        "Condition": {
          "StringNotEquals": {
            "aws:SourceOwner": "self"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_acl" "registry-k8s-io" {
  bucket = aws_s3_bucket.registry-k8s-io.bucket
  acl    = "private"
}

resource "aws_s3_bucket_policy" "registry-k8s-io-public-read" {
  bucket = aws_s3_bucket.registry-k8s-io.bucket

  policy = jsonencode({
    "Id" : "Public-Access",
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "s3:ListBucket",
        "Effect" : "Allow",
        "Resource" : "${aws_s3_bucket.registry-k8s-io.arn}",
        "Principal" : "*"
      },
      {
        "Action" : "s3:GetObject",
        "Effect" : "Allow",
        "Resource" : "${aws_s3_bucket.registry-k8s-io.arn}/*",
        "Principal" : "*"
      },
      {
        "Sid" : "AllowSSLRequestsOnly",
        "Action" : "s3:*",
        "Effect" : "Deny",
        "Resource" : "${aws_s3_bucket.registry-k8s-io.arn}/*",
        "Condition" : {
          "Bool" : {
            "aws:SecureTransport" : "false"
          }
        },
        "Principal" : "*"
      }
    ]
  })
}

resource "aws_s3_bucket_ownership_controls" "registry-k8s-io" {
  bucket = aws_s3_bucket.registry-k8s-io.bucket

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
  depends_on = [
    aws_s3_bucket.registry-k8s-io,
    aws_s3_bucket_acl.registry-k8s-io,
    aws_s3_bucket_policy.registry-k8s-io-public-read
  ]
}

resource "aws_s3_bucket_versioning" "registry-k8s-io" {
  bucket = aws_s3_bucket.registry-k8s-io.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_replication_configuration" "registry-k8s-io" {
  count = length(var.s3_replication_rules) > 0 ? 1 : 0

  depends_on = [aws_s3_bucket_versioning.registry-k8s-io]

  role = var.s3_replication_iam_role_arn

  bucket = aws_s3_bucket.registry-k8s-io.id

  dynamic "rule" {
    for_each = var.s3_replication_rules

    content {
      id = rule.value.id

      status = rule.value.status

      priority = rule.value.priority

      filter {}

      delete_marker_replication {
        status = "Enabled"
      }

      destination {
        bucket        = rule.value.destination_bucket_arn
        storage_class = rule.value.destination_bucket_storage_class

        metrics {
          status = "Enabled"
        }
      }
    }
  }
}

data "aws_region" "current" {}

variable "prefix" {
  type    = string
  default = ""
}

variable "s3_replication_iam_role_arn" {
  description = "IAM role assumed by S3 service for replication"
  type        = string
  default     = ""
}

variable "s3_replication_rules" {
  description = "List of maps for S3 replication rules"
  type        = list(map(string))
  default     = []
}