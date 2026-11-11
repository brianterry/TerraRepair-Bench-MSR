/*
Copyright 2022 The Kubernetes Authors.

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


provider "aws" {
  profile = "default"
  region  = "us-west-2"
  alias   = "origin"
}


/*
Copyright 2022 The Kubernetes Authors.

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

locals {
  expiration_period = 90
}

data "aws_iam_policy_document" "access_log_policy" {
  statement {
    sid    = "S3ServerAccessLogsPolicy"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    actions = [
      "s3:PutObject",
    ]

    resources = ["${aws_s3_bucket.access_log.arn}/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.origin.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values = [
        data.aws_caller_identity.current.id
      ]
    }
  }

  statement {
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    actions = [
      "s3:GetBucketAcl",
    ]
    resources = [aws_s3_bucket.access_log.arn]
  }
}

resource "aws_s3_bucket" "access_log" {
  provider = aws.origin

  bucket        = "${aws_s3_bucket.origin.bucket}-access-log"
  force_destroy = false

  depends_on = [
    aws_s3_bucket.origin
  ]
}

resource "aws_s3_bucket_policy" "access_log_policy" {
  bucket = aws_s3_bucket.access_log.id
  policy = data.aws_iam_policy_document.access_log_policy.json
}

resource "aws_s3_bucket_ownership_controls" "access_log" {
  bucket = aws_s3_bucket.access_log.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_log" {
  provider = aws.origin

  bucket = aws_s3_bucket.access_log.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.access_log.arn
    }
  }
}

resource "aws_kms_key" "access_log" {
  provider = aws.origin

  description             = "KMS key for access_log bucket encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "access_log" {
  provider = aws.origin

  name          = "alias/access-log-key"
  target_key_id = aws_kms_key.access_log.key_id
}

resource "aws_s3_bucket_versioning" "access_log" {
  provider = aws.origin

  bucket = aws_s3_bucket.access_log.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_log" {
  provider = aws.origin

  bucket = aws_s3_bucket.access_log.id

  rule {
    id     = "auto-delete"
    status = "Enabled"

    filter {}

    expiration {
      days = local.expiration_period
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_notification" "access_log" {
  provider = aws.origin

  bucket = aws_s3_bucket.access_log.id

  topic {
    topic_arn     = aws_sns_topic.access_log.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".log"
  }
}

resource "aws_sns_topic" "access_log" {
  provider = aws.origin

  name = "access-log-notifications"
}

resource "aws_s3_bucket_public_access_block" "access_log" {
  provider = aws.origin

  bucket                  = aws_s3_bucket.access_log.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_replication_configuration" "access_log" {
  provider = aws.origin

  bucket = aws_s3_bucket.access_log.id
  role   = aws_iam_role.replication_access_log.arn

  rule {
    id     = "replication"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.access_log_replica.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.access_log_replica.arn
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }
}

resource "aws_s3_bucket" "access_log_replica" {
  provider = aws.origin

  bucket = "${aws_s3_bucket.origin.bucket}-access-log-replica"
}

resource "aws_s3_bucket_versioning" "access_log_replica" {
  provider = aws.origin

  bucket = aws_s3_bucket.access_log_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_log_replica" {
  provider = aws.origin

  bucket = aws_s3_bucket.access_log_replica.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.access_log_replica.arn
    }
  }
}

resource "aws_kms_key" "access_log_replica" {
  provider = aws.origin

  description             = "KMS key for access_log_replica bucket encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_iam_role" "replication_access_log" {
  provider = aws.origin

  name = "access-log-replication-role"

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

resource "aws_iam_role_policy" "replication_access_log" {
  provider = aws.origin

  name = "access-log-replication-policy"
  role = aws_iam_role.replication_access_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = [aws_s3_bucket.access_log.arn]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Effect   = "Allow"
        Resource = ["${aws_s3_bucket.access_log.arn}/*"]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Effect   = "Allow"
        Resource = ["${aws_s3_bucket.access_log_replica.arn}/*"]
      },
      {
        Action = [
          "kms:Decrypt"
        ]
        Effect   = "Allow"
        Resource = [aws_kms_key.access_log.arn]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.us-west-2.amazonaws.com"
          }
        }
      },
      {
        Action = [
          "kms:Encrypt"
        ]
        Effect   = "Allow"
        Resource = [aws_kms_key.access_log_replica.arn]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.us-west-2.amazonaws.com"
          }
        }
      }
    ]
  })
}


/*
Copyright 2022 The Kubernetes Authors.

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

data "aws_caller_identity" "current" {
  provider = aws.origin
}

resource "random_pet" "bucket" {
  length = 5
}

data "aws_iam_policy_document" "origin_policy" {
  provider = aws.origin

  statement {
    actions = ["s3:*"]
    effect  = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }

    resources = [
      aws_s3_bucket.origin.arn,
      "${aws_s3_bucket.origin.arn}/*"
    ]

  }

  statement {
    actions = ["s3:GetObject"]
    effect  = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      "${aws_s3_bucket.origin.arn}/*"
    ]
  }
}

resource "aws_s3_bucket" "origin" {
  provider = aws.origin

  bucket = "${random_pet.bucket.id}-image-layers"
}

resource "aws_s3_bucket_policy" "allow_public_access" {
  provider = aws.origin

  bucket = aws_s3_bucket.origin.id
  policy = data.aws_iam_policy_document.origin_policy.json
}

resource "aws_s3_bucket_cors_configuration" "origin" {
  provider = aws.origin

  bucket                = aws_s3_bucket.origin.id
  expected_bucket_owner = data.aws_caller_identity.current.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_versioning" "origin" {
  provider = aws.origin

  bucket                = aws_s3_bucket.origin.id
  expected_bucket_owner = data.aws_caller_identity.current.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "origin" {
  provider = aws.origin

  bucket = aws_s3_bucket.origin.bucket
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_logging" "origin_access_log" {
  provider = aws.origin

  bucket = aws_s3_bucket.origin.id

  target_bucket = aws_s3_bucket.access_log.id
  target_prefix = ""
}

resource "aws_s3_bucket_public_access_block" "origin" {
  provider = aws.origin

  bucket                  = aws_s3_bucket.origin.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "origin" {
  provider = aws.origin

  bucket = aws_s3_bucket.origin.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.origin.arn
    }
  }
}

resource "aws_kms_key" "origin" {
  provider = aws.origin

  description             = "KMS key for origin bucket encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "origin" {
  provider = aws.origin

  name          = "alias/origin-key"
  target_key_id = aws_kms_key.origin.key_id
}

resource "aws_s3_bucket_lifecycle_configuration" "origin" {
  provider = aws.origin

  bucket = aws_s3_bucket.origin.id

  rule {
    id     = "auto-delete"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_notification" "origin" {
  provider = aws.origin

  bucket = aws_s3_bucket.origin.id

  topic {
    topic_arn     = aws_sns_topic.origin.arn
    events        = ["s3:ObjectCreated:*"]
  }
}

resource "aws_sns_topic" "origin" {
  provider = aws.origin

  name = "origin-notifications"
}

resource "aws_s3_bucket_replication_configuration" "origin" {
  provider = aws.origin

  bucket = aws_s3_bucket.origin.id
  role   = aws_iam_role.replication_origin.arn

  rule {
    id     = "replication"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.origin_replica.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.origin_replica.arn
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }
}

resource "aws_s3_bucket" "origin_replica" {
  provider = aws.origin

  bucket = "${random_pet.bucket.id}-image-layers-replica"
}

resource "aws_s3_bucket_versioning" "origin_replica" {
  provider = aws.origin

  bucket = aws_s3_bucket.origin_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "origin_replica" {
  provider = aws.origin

  bucket = aws_s3_bucket.origin_replica.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.origin_replica.arn
    }
  }
}

resource "aws_kms_key" "origin_replica" {
  provider = aws.origin

  description             = "KMS key for origin_replica bucket encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_iam_role" "replication_origin" {
  provider = aws.origin

  name = "origin-replication-role"

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

resource "aws_iam_role_policy" "replication_origin" {
  provider = aws.origin

  name = "origin-replication-policy"
  role = aws_iam_role.replication_origin.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = [aws_s3_bucket.origin.arn]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Effect   = "Allow"
        Resource = ["${aws_s3_bucket.origin.arn}/*"]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Effect   = "Allow"
        Resource = ["${aws_s3_bucket.origin_replica.arn}/*"]
      },
      {
        Action = [
          "kms:Decrypt"
        ]
        Effect   = "Allow"
        Resource = [aws_kms_key.origin.arn]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.us-west-2.amazonaws.com"
          }
        }
      },
      {
        Action = [
          "kms:Encrypt"
        ]
        Effect   = "Allow"
        Resource = [aws_kms_key.origin_replica.arn]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.us-west-2.amazonaws.com"
          }
        }
      }
    ]
  })
}


/*
Copyright 2022 The Kubernetes Authors.

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

/*
This file defines:
- Required provider versions
- Storage backend details
- alias for the provider per region
*/

terraform {
  backend "gcs" {
    bucket = "k8s-infra-tf-aws"
    prefix = "oci-proxy"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.12.0"
    }
  }
}


/*
Copyright 2022 The Kubernetes Authors.

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

/*
This file defines:
- Required Terraform version
*/

terraform {
  required_version = "~> 1.1.2"
}