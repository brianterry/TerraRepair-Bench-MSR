terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

# Create a KMS Customer Managed Key (CMK)
resource "aws_kms_key" "cmk" {
  policy = data.aws_iam_policy_document.cmk_admin_policy.json

  # We set a short deletion window, as these keys are only used
  # for testing/learning, and we want to minimize the AWS charges
  deletion_window_in_days = 7

  rotation_enabled = true
}

# A simple policy that makes the current IAM user the admin
# of the CMK
data "aws_iam_policy_document" "cmk_admin_policy" {
  statement {
    effect    = "Allow"
    resources = [aws_kms_key.cmk.arn]
    actions   = [
      "kms:CreateAlias",
      "kms:CreateGrant",
      "kms:DescribeKey",
      "kms:DisableKey",
      "kms:EnableKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyPair",
      "kms:GenerateDataKeyPairWithoutPlaintext",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListAliases",
      "kms:ListGrants",
      "kms:ListKeyPolicies",
      "kms:ListKeys",
      "kms:ListResourceTags",
      "kms:ReEncrypt",
      "kms:ReEncryptTo",
      "kms:ReplicateKey",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateAlias",
      "kms:UpdateKeyDescription",
      "kms:UpdatePrimaryRegion"
    ]
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.self.arn]
    }
  }
  statement {
    effect    = "Allow"
    resources = [aws_kms_key.cmk.arn]
    actions   = [
      "kms:PutKeyPolicy",
      "kms:DeleteAlias",
      "kms:CancelKeyDeletion"
    ]
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.self.arn]
    }
    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values   = [data.aws_caller_identity.self.arn]
    }
  }
}

# Look up the details of the current user
data "aws_caller_identity" "self" {}

# Create an alias for the CMK
resource "aws_kms_alias" "cmk" {
  name          = "alias/${var.alias}"
  target_key_id = aws_kms_key.cmk.id
}

output "cmk_arn" {
  value       = aws_kms_key.cmk.arn
  description = "The ARN of the CMK"
}

output "cmk_alias" {
  value       = aws_kms_alias.cmk.name
  description = "The alias of the CMK"
}

variable "alias" {
  description = "The alias to use for the CMK"
  type        = string
  default     = "kms-cmk-example"
}