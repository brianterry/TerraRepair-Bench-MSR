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

provider "aws" {
  profile = "default"
  region  = "us-east-1"
  alias   = "replica"
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
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_log" {
  provider = aws.origin

  bucket = aws_s3_bucket.access_log.id

  rule {
    id     = "auto-delete"
    status = "Enabled"

    filter {}

    # Objects are deleted after 90 days
    expiration {
      days = local.expiration_period
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}


# Prevent public access
resource "aws_s3_bucket_public_access_block" "access_log" {
  provider = aws.origin

  bucket                  = aws_s3_bucket.access_log.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "access_log" {
  provider = aws.origin

  bucket = aws_s3_bucket.access_log.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_notification" "access_log" {
  provider = aws.origin

  bucket      = aws_s3_bucket.access_log.id
  eventbridge = true
}

resource "aws_s3_bucket_replication_configuration" "access_log" {
  provider = aws.origin

  depends_on = [
    aws_s3_bucket_versioning.access_log,
    aws_s3_bucket_versioning.access_log_replica
  ]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.access_log.id

  rule {
    id     = "replicate-access-log"
    status = "Enabled"

    destination {
      bucket = aws_s3_bucket.access_log_replica.arn

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.replica.arn
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

data "aws_iam_policy_document" "s3_kms" {
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowS3"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com", "logging.s3.amazonaws.com"]
    }
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "s3" {
  provider            = aws.origin
  description         = "CMK for S3 bucket encryption"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.s3_kms.json
}

resource "aws_kms_key" "replica" {
  provider            = aws.replica
  description         = "CMK for S3 replica bucket encryption"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.s3_kms.json
}

data "aws_iam_policy_document" "replication_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "replication" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.origin.arn,
      aws_s3_bucket.access_log.arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging"
    ]
    resources = [
      "${aws_s3_bucket.origin.arn}/*",
      "${aws_s3_bucket.access_log.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags"
    ]
    resources = [
      "${aws_s3_bucket.origin_replica.arn}/*",
      "${aws_s3_bucket.access_log_replica.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt"
    ]
    resources = [
      aws_kms_key.s3.arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:GenerateDataKey"
    ]
    resources = [
      aws_kms_key.replica.arn
    ]
  }
}

resource "aws_iam_role" "replication" {
  provider           = aws.origin
  name               = "${random_pet.bucket.id}-s3-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_assume.json
}

resource "aws_iam_role_policy" "replication" {
  provider = aws.origin
  name     = "${random_pet.bucket.id}-s3-replication"
  role     = aws_iam_role.replication.id
  policy   = data.aws_iam_policy_document.replication.json
}

resource "aws_s3_bucket" "origin_replica" {
  provider = aws.replica

  bucket = "${aws_s3_bucket.origin.bucket}-replica"
}

resource "aws_s3_bucket_versioning" "origin_replica" {
  provider = aws.replica

  bucket = aws_s3_bucket.origin_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "origin_replica" {
  provider = aws.replica

  bucket                  = aws_s3_bucket.origin_replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "origin_replica" {
  provider = aws.replica

  bucket = aws_s3_bucket.origin_replica.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.replica.arn
    }
  }
}

resource "aws_s3_bucket" "access_log_replica" {
  provider = aws.replica

  bucket = "${aws_s3_bucket.access_log.bucket}-replica"
}

resource "aws_s3_bucket_versioning" "access_log_replica" {
  provider = aws.replica

  bucket = aws_s3_bucket.access_log_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "access_log_replica" {
  provider = aws.replica

  bucket                  = aws_s3_bucket.access_log_replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_log_replica" {
  provider = aws.replica

  bucket = aws_s3_bucket.access_log_replica.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.replica.arn
    }
  }
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

resource "aws_s3_bucket_public_access_block" "origin" {
  provider = aws.origin

  bucket                  = aws_s3_bucket.origin.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [aws_s3_bucket_policy.allow_public_access]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "origin" {
  provider = aws.origin

  bucket = aws_s3_bucket.origin.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "origin" {
  provider = aws.origin

  bucket = aws_s3_bucket.origin.id

  rule {
    id     = "abort-incomplete"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_notification" "origin" {
  provider = aws.origin

  bucket      = aws_s3_bucket.origin.id
  eventbridge = true
}

resource "aws_s3_bucket_replication_configuration" "origin" {
  provider = aws.origin

  depends_on = [
    aws_s3_bucket_versioning.origin,
    aws_s3_bucket_versioning.origin_replica
  ]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.origin.id

  rule {
    id     = "replicate-origin"
    status = "Enabled"

    destination {
      bucket = aws_s3_bucket.origin_replica.arn

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.replica.arn
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }
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