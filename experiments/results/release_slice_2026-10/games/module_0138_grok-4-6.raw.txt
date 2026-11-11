terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "bucket_name" {
   description = "Name of the bucket to create"
   default = "roger-bucket-0"
}

variable "bucket_acl" {
   description = "ACL for S3 bucket: private, public-read, public-read-write, etc"
   default = "private"
}

variable "ip_addresses" {
  description = "list of prohibited IP address"
  default = ["1.1.1.1"]
}

variable "s3_vpce_id" {
  description = "S3 VPC endpoint"
  default = ""
}

variable "shared_s3_vpce_id" {
  description = "Shared S3 VPC endpoint"
  default = ""
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "my_key" {
  description             = "This key is used to encrypt bucket objects"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  policy                  = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "key-default-policy",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_iam_role" "replication" {
  name = "s3-bucket-replication"

  assume_role_policy = <<POLICY
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
POLICY
}

resource "aws_iam_role_policy" "replication" {
  name = "s3-bucket-replication"
  role = aws_iam_role.replication.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetReplicationConfiguration",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${var.bucket_name}",
        "arn:aws:s3:::roger-bucket-1",
        "arn:aws:s3:::roger-bucket-2"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObjectVersionForReplication",
        "s3:GetObjectVersionAcl",
        "s3:GetObjectVersionTagging"
      ],
      "Resource": [
        "arn:aws:s3:::${var.bucket_name}/*",
        "arn:aws:s3:::roger-bucket-1/*",
        "arn:aws:s3:::roger-bucket-2/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateDelete",
        "s3:ReplicateTags"
      ],
      "Resource": [
        "arn:aws:s3:::${var.bucket_name}/*",
        "arn:aws:s3:::roger-bucket-1/*",
        "arn:aws:s3:::roger-bucket-2/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "${aws_kms_key.my_key.arn}"
    }
  ]
}
POLICY
}

resource "aws_sns_topic" "s3_notifications" {
  name = "s3-bucket-notifications"
}

resource "aws_sns_topic_policy" "s3_notifications" {
  arn = aws_sns_topic.s3_notifications.arn

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "SNS:Publish",
      "Resource": "${aws_sns_topic.s3_notifications.arn}",
      "Condition": {
        "ArnLike": {
          "aws:SourceArn": [
            "arn:aws:s3:::${var.bucket_name}",
            "arn:aws:s3:::roger-bucket-1",
            "arn:aws:s3:::roger-bucket-2"
          ]
        }
      }
    }
  ]
}
POLICY
}

resource "aws_s3_bucket" "bucket_0" {
  bucket = var.bucket_name
  acl    = var.bucket_acl

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "roger-bucket-1"
    target_prefix = "log/bucket_0/"
  }

  lifecycle_rule {
    id                                     = "abort-incomplete"
    enabled                                = true
    prefix                                 = ""
    abort_incomplete_multipart_upload_days = 7
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.my_key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  replication_configuration {
    role = aws_iam_role.replication.arn

    rules {
      id     = "replicate"
      status = "Enabled"
      prefix = ""

      destination {
        bucket             = "arn:aws:s3:::roger-bucket-2"
        storage_class      = "STANDARD"
        replica_kms_key_id = aws_kms_key.my_key.arn
      }

      source_selection_criteria {
        sse_kms_encrypted_objects {
          enabled = true
        }
      }
    }
  }
}

resource "aws_s3_bucket" "bucket_1" {
  bucket = "roger-bucket-1"
  acl    = var.bucket_acl

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "roger-bucket-1"
    target_prefix = "log/bucket_1/"
  }

  lifecycle_rule {
    id                                     = "abort-incomplete"
    enabled                                = true
    prefix                                 = ""
    abort_incomplete_multipart_upload_days = 7
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.my_key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  replication_configuration {
    role = aws_iam_role.replication.arn

    rules {
      id     = "replicate"
      status = "Enabled"
      prefix = ""

      destination {
        bucket             = "arn:aws:s3:::roger-bucket-2"
        storage_class      = "STANDARD"
        replica_kms_key_id = aws_kms_key.my_key.arn
      }

      source_selection_criteria {
        sse_kms_encrypted_objects {
          enabled = true
        }
      }
    }
  }
}

resource "aws_s3_bucket" "bucket_2" {
  bucket = "roger-bucket-2"
  acl    = var.bucket_acl

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "roger-bucket-1"
    target_prefix = "log/bucket_2/"
  }

  lifecycle_rule {
    id                                     = "abort-incomplete"
    enabled                                = true
    prefix                                 = ""
    abort_incomplete_multipart_upload_days = 7
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.my_key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  replication_configuration {
    role = aws_iam_role.replication.arn

    rules {
      id     = "replicate"
      status = "Enabled"
      prefix = ""

      destination {
        bucket             = "arn:aws:s3:::roger-bucket-1"
        storage_class      = "STANDARD"
        replica_kms_key_id = aws_kms_key.my_key.arn
      }

      source_selection_criteria {
        sse_kms_encrypted_objects {
          enabled = true
        }
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "bucket_0" {
  bucket = aws_s3_bucket.bucket_0.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "bucket_1" {
  bucket = aws_s3_bucket.bucket_1.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "bucket_2" {
  bucket = aws_s3_bucket.bucket_2.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_notification" "bucket_0" {
  bucket = aws_s3_bucket.bucket_0.id

  topic {
    topic_arn = aws_sns_topic.s3_notifications.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.s3_notifications]
}

resource "aws_s3_bucket_notification" "bucket_1" {
  bucket = aws_s3_bucket.bucket_1.id

  topic {
    topic_arn = aws_sns_topic.s3_notifications.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.s3_notifications]
}

resource "aws_s3_bucket_notification" "bucket_2" {
  bucket = aws_s3_bucket.bucket_2.id

  topic {
    topic_arn = aws_sns_topic.s3_notifications.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.s3_notifications]
}

resource "aws_s3_bucket_policy" "bucket_policy_1" {
  bucket = aws_s3_bucket.bucket_1.id
  policy = data.aws_iam_policy_document.example.json

  depends_on = [aws_s3_bucket_public_access_block.bucket_1]
}

resource "aws_s3_bucket_policy" "bucket_policy_2" {
  bucket = aws_s3_bucket.bucket_2.id
  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"DenyHTTP",
      "Effect":"Deny",
      "Principal": "*",
      "Action":"s3:*",
      "Resource":[
        "arn:aws:s3:::roger-bucket-2",
        "arn:aws:s3:::roger-bucket-2/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
POLICY

  depends_on = [aws_s3_bucket_public_access_block.bucket_2]
}

data "aws_iam_policy_document" "example" {
  statement {
    sid = "Deny HTTP for bucket level operations"
    effect = "Deny"
    principals {
      type = "*"
      identifiers = ["*"]
    }
    actions = [
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.bucket_1.id}",
    ]
    condition {
      test = "Bool"
      variable = "aws:SecureTransport"
      values = [
        "false",
      ]
    }
  }

  statement {
    sid = "Deny HTTP for object operations"
    effect = "Deny"
    principals {
      type = "*"
      identifiers = ["*"]
    }
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.bucket_1.id}",
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values = [
        "false",
      ]
    }
  }

  statement {
    sid = "Deny bucket access not through vpce"
    effect = "Deny"
    principals {
      type = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.bucket_1.id}",
    ]
    condition {
      test     = "NotIpAddress"
      variable = "aws:SourceIp"
      values = var.ip_addresses
    }
    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values = [
        "vpce-111111",
        var.s3_vpce_id,
        var.shared_s3_vpce_id
      ]
    }
  }

  statement {
    sid = "Deny object access not through vpce"
    effect = "Deny"
    principals {
      type = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.bucket_1.id}",
    ]
    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values = [
        "vpce-111111111111111111",
        var.s3_vpce_id,
        var.shared_s3_vpce_id
      ]
    }
  }
}