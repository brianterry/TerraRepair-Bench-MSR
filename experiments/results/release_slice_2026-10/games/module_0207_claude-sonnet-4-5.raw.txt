/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

data "aws_region" "current" {}

resource "aws_kms_key" "artifacts-k8s-io" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_s3_bucket" "artifacts-k8s-io" {
  bucket = "${var.prefix}artifacts-k8s-io-${data.aws_region.current.name}"
}

resource "aws_s3_bucket" "artifacts-k8s-io-logs" {
  bucket = "${var.prefix}artifacts-k8s-io-logs-${data.aws_region.current.name}"
}

resource "aws_s3_bucket_acl" "artifacts-k8s-io-logs" {
  bucket = aws_s3_bucket.artifacts-k8s-io-logs.bucket
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts-k8s-io-logs" {
  bucket = aws_s3_bucket.artifacts-k8s-io-logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts-k8s-io-logs" {
  bucket = aws_s3_bucket.artifacts-k8s-io-logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_acl" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.bucket
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  target_bucket = aws_s3_bucket.artifacts-k8s-io-logs.id
  target_prefix = "log/"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.artifacts-k8s-io.arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  rule {
    id     = "default"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_notification" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id
}

resource "aws_s3_bucket_policy" "artifacts-k8s-io-public-read" {
  bucket = aws_s3_bucket.artifacts-k8s-io.bucket

  policy = jsonencode({
    "Id" : "Public-Access",
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "s3:ListBucket",
        "Effect" : "Allow",
        "Resource" : aws_s3_bucket.artifacts-k8s-io.arn
        "Principal" : "*"
      },
      {
        "Action" : "s3:GetObject",
        "Effect" : "Allow",
        "Resource" : "${aws_s3_bucket.artifacts-k8s-io.arn}/*",
        "Principal" : "*"
      },
      {
        "Sid" : "RequireTLSForObjectAccess",
        "Action" : "s3:*",
        "Effect" : "Deny",
        "Resource" : "${aws_s3_bucket.artifacts-k8s-io.arn}/*",
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

resource "aws_s3_bucket_ownership_controls" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.bucket

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  depends_on = [
    aws_s3_bucket.artifacts-k8s-io,
    aws_s3_bucket_acl.artifacts-k8s-io,
    aws_s3_bucket_policy.artifacts-k8s-io-public-read
  ]
}

resource "aws_s3_bucket_versioning" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_replication_configuration" "artifacts-k8s-io" {
  count = length(var.s3_replication_rules) > 0 ? 1 : 0

  role = var.s3_replication_iam_role_arn

  bucket = aws_s3_bucket.artifacts-k8s-io.id

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

  depends_on = [aws_s3_bucket_versioning.artifacts-k8s-io]
}


/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

variable "prefix" {
  description = "Prefix added to bucket name"
  type        = string
  default     = ""
  nullable    = false
}

variable "s3_replication_iam_role_arn" {
  description = "IAM role assumed by S3 service for replication"
  type        = string
  default     = null
}

variable "s3_replication_rules" {
  description = "List of maps for S3 replication rules"
  type        = list(map(string))
  default     = []
  nullable    = false
}


/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

terraform {
  required_version = "~> 1.1"

  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}