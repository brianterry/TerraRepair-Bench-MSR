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

resource "aws_iam_role" "example" {
  count = length(var.user_names)
  name  = var.user_names[count.index]

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "cloudwatch_read_only" {

  name   = "${var.policy_name_prefix}cloudwatch-read-only"

  policy = data.aws_iam_policy_document.cloudwatch_read_only.json
}

data "aws_iam_policy_document" "cloudwatch_read_only" {
  statement {
    effect    = "Allow"
    actions   = [
      "cloudwatch:Describe*",
      "cloudwatch:Get*",
      "cloudwatch:List*"
    ]
    resources = ["arn:aws:cloudwatch:us-east-2:*:*"]
  }
}

resource "aws_iam_policy" "cloudwatch_full_access" {

  name   = "${var.policy_name_prefix}cloudwatch-full-access"

  policy = data.aws_iam_policy_document.cloudwatch_full_access.json
}

data "aws_iam_policy_document" "cloudwatch_full_access" {
  statement {
    effect    = "Allow"
    actions   = ["cloudwatch:*"]
    resources = ["arn:aws:cloudwatch:us-east-2:*:*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "neo_cloudwatch_full_access" {
  count = var.give_neo_cloudwatch_full_access ? 1 : 0

  role       = aws_iam_role.example[0].name
  policy_arn = aws_iam_policy.cloudwatch_full_access.arn
}

resource "aws_iam_role_policy_attachment" "neo_cloudwatch_read_only" {
  count = var.give_neo_cloudwatch_full_access ? 0 : 1

  role       = aws_iam_role.example[0].name
  policy_arn = aws_iam_policy.cloudwatch_read_only.arn
}



output "first_arn" {
  value       = aws_iam_role.example[0].arn
  description = "The ARN for the first user"
}

output "all_arns" {
  value       = aws_iam_role.example[*].arn
  description = "The ARNs for all users"
}

output "neo_cloudwatch_policy_arn_ternary" {
  value = (
    var.give_neo_cloudwatch_full_access
    ? aws_iam_role_policy_attachment.neo_cloudwatch_full_access[0].policy_arn
    : aws_iam_role_policy_attachment.neo_cloudwatch_read_only[0].policy_arn
  )
}

output "neo_cloudwatch_policy_arn" {
  value = one(concat(
    aws_iam_role_policy_attachment.neo_cloudwatch_full_access[*].policy_arn,
    aws_iam_role_policy_attachment.neo_cloudwatch_read_only[*].policy_arn
  ))
}



variable "user_names" {
  description = "Create IAM users with these names"
  type        = list(string)
  default     = ["neo", "trinity", "morpheus"]
}

variable "give_neo_cloudwatch_full_access" {
  description = "If true, neo gets full access to CloudWatch"
  type        = bool
}

variable "policy_name_prefix" {
  description = "The prefix to use for the IAM policy names"
  type        = string
  default     = ""
}