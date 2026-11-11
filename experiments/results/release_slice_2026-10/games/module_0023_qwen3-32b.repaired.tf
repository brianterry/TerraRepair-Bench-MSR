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
  deletion_window_in_days = 7
  enable_key_rotation = true
}

# A simple policy that makes the current IAM user the admin
# of the CMK
data "aws_iam_policy_document" "cmk_admin_policy" {
  statement {
    effect    = "Allow"
    resources = ["*"]
    actions   = ["kms:DescribeKey", "kms:GetKeyPolicy", "kms:GetPublicKey", "kms:ListGrants", "kms:ListKeyPolicies", "kms:ListAliases"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.self.arn]
    }
  }

  statement {
    effect    = "Allow"
    resources = ["*"]
    actions   = ["kms:CreateGrant", "kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext", "kms:ReEncrypt*", "kms:Sign", "kms:Verify*", "kms:PutKeyPolicy"]
    condition {
      test     = "ArnLike"
      variable = "kms:Resource"
      values   = ["${aws_kms_key.cmk.arn}"]
    }
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.self.arn]
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

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These parameters have reasonable defaults.
# ---------------------------------------------------------------------------------------------------------------------

variable "alias" {
  description = "The alias to use for the CMK"
  type        = string
  default     = "kms-cmk-example"
}