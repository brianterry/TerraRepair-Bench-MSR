/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/License-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

data "aws_region" "current" {}

resource "aws_kms_key" "artifacts-k8s-io" {
  description             = "CMK for artifacts-k8s-io bucket encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_s3_bucket" "artifacts-k8s-io" {
  bucket = "${var.prefix}artifacts-k8s-io-${data.aws_region.current.name}"
}

resource "aws_s3_bucket_acl" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.bucket
  # This clears the ACL list, so we can apply object_ownership = "BucketOwnerEnforced"
  acl = "private"
}

resource "aws_s3_bucket_public_access_block" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [aws_s3_bucket_policy.artifacts-k8s-io-public-read]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.artifacts-k8s-io.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  target_bucket = aws_s3_bucket.artifacts-k8s-io.id
  target_prefix = "logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  rule {
    id     = "default"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_sns_topic" "artifacts-k8s-io" {
  name              = "${var.prefix}artifacts-k8s-io-${data.aws_region.current.name}-events"
  kms_master_key_id = aws_kms_key.artifacts-k8s-io.id
}

resource "aws_sns_topic_policy" "artifacts-k8s-io" {
  arn = aws_sns_topic.artifacts-k8s-io.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Publish"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.artifacts-k8s-io.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.artifacts-k8s-io.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id

  topic {
    topic_arn = aws_sns_topic.artifacts-k8s-io.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.artifacts-k8s-io]
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
      },
      {
        "Sid" : "S3ServerAccessLogsPolicy",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "logging.s3.amazonaws.com"
        },
        "Action" : "s3:PutObject",
        "Resource" : "${aws_s3_bucket.artifacts-k8s-io.arn}/logs/*",
        "Condition" : {
          "ArnLike" : {
            "aws:SourceArn" : aws_s3_bucket.artifacts-k8s-io.arn
          }
        }
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

# Versioning must be enabled for S3 replication
resource "aws_s3_bucket_versioning" "artifacts-k8s-io" {
  bucket = aws_s3_bucket.artifacts-k8s-io.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "artifacts-k8s-io-replica" {
  bucket = "${var.prefix}artifacts-k8s-io-r-${data.aws_region.current.name}"
}

resource "aws_s3_bucket_versioning" "artifacts-k8s-io-replica" {
  bucket = aws_s3_bucket.artifacts-k8s-io-replica.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts-k8s-io-replica" {
  bucket = aws_s3_bucket.artifacts-k8s-io-replica.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts-k8s-io-replica" {
  bucket = aws_s3_bucket.artifacts-k8s-io-replica.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.artifacts-k8s-io.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "artifacts-k8s-io-replica" {
  bucket = aws_s3_bucket.artifacts-k8s-io-replica.id

  target_bucket = aws_s3_bucket.artifacts-k8s-io.id
  target_prefix = "replica-logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts-k8s-io-replica" {
  bucket = aws_s3_bucket.artifacts-k8s-io-replica.id

  rule {
    id     = "default"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_notification" "artifacts-k8s-io-replica" {
  bucket = aws_s3_bucket.artifacts-k8s-io-replica.id

  topic {
    topic_arn = aws_sns_topic.artifacts-k8s-io.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.artifacts-k8s-io]
}

resource "aws_iam_role" "replication" {
  name = "${var.prefix}artifacts-k8s-io-${data.aws_region.current.name}-replication"

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

resource "aws_iam_role_policy" "replication" {
  name = "${var.prefix}artifacts-k8s-io-${data.aws_region.current.name}-replication"
  role = aws_iam_role.replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.artifacts-k8s-io.arn,
          aws_s3_bucket.artifacts-k8s-io-replica.arn
        ]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.artifacts-k8s-io.arn}/*",
          "${aws_s3_bucket.artifacts-k8s-io-replica.arn}/*"
        ]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.artifacts-k8s-io.arn}/*",
          "${aws_s3_bucket.artifacts-k8s-io-replica.arn}/*"
        ]
      },
      {
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Effect   = "Allow"
        Resource = aws_kms_key.artifacts-k8s-io.arn
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "artifacts-k8s-io" {
  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.artifacts-k8s-io]

  role = var.s3_replication_iam_role_arn != null ? var.s3_replication_iam_role_arn : aws_iam_role.replication.arn

  bucket = aws_s3_bucket.artifacts-k8s-io.id

  dynamic "rule" {
    for_each = length(var.s3_replication_rules) > 0 ? var.s3_replication_rules : [
      {
        id                               = "default"
        status                           = "Enabled"
        priority                         = "0"
        destination_bucket_arn           = aws_s3_bucket.artifacts-k8s-io-replica.arn
        destination_bucket_storage_class = "STANDARD"
      }
    ]

    content {
      id = rule.value.id

      status = rule.value.status

      # Set priority, filter and delete_marker_replication to use V2 schema for multiple
      # destination bucket rules
      priority = rule.value.priority

      filter {}

      delete_marker_replication {
        status = "Enabled"
      }

      destination {
        bucket        = rule.value.destination_bucket_arn
        storage_class = rule.value.destination_bucket_storage_class

        encryption_configuration {
          replica_kms_key_id = aws_kms_key.artifacts-k8s-io.arn
        }

        metrics {
          status = "Enabled"
        }
      }

      source_selection_criteria {
        sse_kms_encrypted_objects {
          status = "Enabled"
        }
      }
    }
  }
}

resource "aws_s3_bucket_replication_configuration" "artifacts-k8s-io-replica" {
  depends_on = [aws_s3_bucket_versioning.artifacts-k8s-io-replica]

  role = var.s3_replication_iam_role_arn != null ? var.s3_replication_iam_role_arn : aws_iam_role.replication.arn

  bucket = aws_s3_bucket.artifacts-k8s-io-replica.id

  rule {
    id       = "replica-to-source"
    status   = "Enabled"
    priority = 0

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = aws_s3_bucket.artifacts-k8s-io.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.artifacts-k8s-io.arn
      }

      metrics {
        status = "Enabled"
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }
}


/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/License-2.0

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

    http://www.apache.org/licenses/License-2.0

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
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}