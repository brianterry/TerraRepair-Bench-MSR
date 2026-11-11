module "label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=0.14.1"
  namespace  = var.namespace
  stage      = var.stage
  name       = var.name
  attributes = ["role"]
}

module "kops_metadata" {
  source       = "git::https://github.com/cloudposse/terraform-aws-kops-data-iam.git?ref=0.2.0"
  cluster_name = var.kops_cluster_name
}

locals {
  # TODO search for kiam-specific role
  kiam_role = module.kops_metadata.masters_role_arn
  role_arns = {
    kiam    = [local.kiam_role]
    masters = [module.kops_metadata.masters_role_arn]
    nodes   = [module.kops_metadata.nodes_role_arn]
    both    = [module.kops_metadata.masters_role_arn, module.kops_metadata.nodes_role_arn]
  }
}

resource "aws_iam_role" "default" {
  name        = module.label.id
  description = "Role that has access to AWS metrics"

  lifecycle {
    create_before_destroy = true
  }

  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  max_session_duration = var.max_session_duration
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    principals {
      type = "AWS"

      identifiers = [module.kops_metadata.masters_role_arn]
    }

    effect = "Allow"
  }
}

resource "aws_iam_role_policy_attachment" "default" {
  role       = aws_iam_role.default.name
  policy_arn = aws_iam_policy.default.arn

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_policy" "default" {
  name        = module.label.id
  description = "Grant permissions for external-dns"
  policy      = data.aws_iam_policy_document.default.json
}

data "aws_iam_policy_document" "default" {
  statement {
    sid = "ReadMetricsAndTags"

    actions = [
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:GetMetricData",
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "tag:GetResources",
    ]

    effect = "Allow"

    resources = ["*"]
  }
}


locals {
  chamber_service = coalesce(var.chamber_service, basename(pathexpand(path.module)))
}


resource "kubernetes_namespace" "default" {
  count = length(var.cloudwatch_namespace) > 0 ? 1 : 0

  metadata {
    annotations = {
      "iam.amazonaws.com/permitted" = aws_iam_role.default.name
    }

    labels = {
      name = var.cloudwatch_namespace
    }

    name = var.cloudwatch_namespace
  }
}

resource "aws_ssm_parameter" "aws_metrics_iam_role" {
  name        = format(var.chamber_parameter_name_pattern, local.chamber_service, "aws_metrics_iam_role")
  value       = aws_iam_role.default.name
  description = "IAM role name for AWS metrics access"
  type        = "SecureString"
  key_id      = var.chamber_kms_key_id
  overwrite   = "true"
}

resource "aws_ssm_parameter" "aws_metrics_iam_namespace" {
  count       = length(var.cloudwatch_namespace) > 0 ? 1 : 0
  name        = format(var.chamber_parameter_name_pattern, local.chamber_service, "aws_metrics_iam_namespace")
  value       = var.cloudwatch_namespace
  description = "Kubernetes namespace for AWS metrics accessors"
  type        = "SecureString"
  key_id      = var.chamber_kms_key_id
  overwrite   = "true"
}

output "aws_metrics_namespace" {
  value = length(var.cloudwatch_namespace) > 0 ? var.cloudwatch_namespace : "<not managed>"
}

output "aws_metrics_iam_role_name" {
  value = aws_iam_role.default.name
}

output "aws_metrics_iam_role_unique_id" {
  value = aws_iam_role.default.unique_id
}

output "aws_metrics_iam_role_arn" {
  value = aws_iam_role.default.arn
}


terraform {
  backend "s3" {}
}

provider "aws" {
  assume_role { role_arn = var.aws_assume_role_arn }
}

variable "aws_assume_role_arn" {
  type = string
}

variable "namespace" {
  type        = string
  description = "Namespace (e.g. `eg` or `cp`)"
}

variable "cloudwatch_namespace" {
  type        = string
  default     = ""
  description = "Kubernetes namespace in which to deploy prometheus-cloudwatch-exporter. Default is no namespacer created."
}

variable "stage" {
  type        = string
  description = "Stage (e.g. `prod`, `dev`, `staging`)"
}

variable "region" {
  type        = string
  description = "AWS region"
}

variable "name" {
  type        = string
  default     = "prometheus-cloudwatch-exporter"
  description = "The base name of the role"
}

variable "kops_cluster_name" {
  type        = string
  description = "The name of the kops cluster (used for finding kops IAM roles)"
}

variable "assume_role_permitted_roles" {
  type        = string
  description = "Roles that are permitted to assume thie role. One of 'kiam', 'nodes', 'masters', or 'both' (nodes + masters)."
  default     = "kiam"
}

variable "chamber_service" {
  type        = string
  default     = "grafana"
  description = "`chamber` service name. See [chamber usage](https://github.com/segmentio/chamber#usage) for more details"
}

variable "chamber_parameter_name_pattern" {
  type        = string
  default     = "/%s/%s"
  description = "Format string for creating SSM parameter name used to store chamber parameters. The default is usually best."
}

variable "chamber_kms_key_id" {
  type        = string
  default     = "alias/aws/ssm"
  description = "KMS key ID, ARN, or alias to use for encrypting SSM secrets"
}

variable "max_session_duration" {
  default     = 3600
  description = "The maximum session duration (in seconds) for the role. Can have a value from 1 hour to 12 hours"
}


terraform {
  required_version = "~> 0.12.0"

  required_providers {
    aws        = "~> 2.0"
    kubernetes = "~> 1.8"
  }
}