provider "aws" {
  region = local.region
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

locals {
  name   = var.environment_name
  region = var.aws_region

  vpc_cidr       = var.vpc_cidr
  num_of_subnets = min(length(data.aws_availability_zones.available.names), 3)
  azs            = slice(data.aws_availability_zones.available.names, 0, local.num_of_subnets)

  argocd_secret_manager_name = var.argocd_secret_manager_name_suffix

  hosted_zone_name = var.hosted_zone_name

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  # Do not include local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }

  exclude_zone_ids = ["usw2-az4"]
}

module "vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=473c826ea329a3d72c1e672c7d361e4341d8682f"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 6, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 6, k + 10)]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_traffic_type                = "REJECT"
  flow_log_max_aggregation_interval    = 60

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

# Retrieve existing root hosted zone
data "aws_route53_zone" "root" {
  name = local.hosted_zone_name
}

# Create Sub HostedZone four our deployment
resource "aws_route53_zone" "sub" {
  name = "${local.name}.${local.hosted_zone_name}"
}

resource "aws_kms_key" "dnssec" {
  provider                 = aws.us-east-1
  customer_master_key_spec = "ECC_NIST_P256"
  deletion_window_in_days  = 7
  key_usage                = "SIGN_VERIFY"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRoute53DNSSECService"
        Effect = "Allow"
        Principal = {
          Service = "dnssec-route53.amazonaws.com"
        }
        Action = [
          "kms:DescribeKey",
          "kms:GetPublicKey",
          "kms:Sign",
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowRoute53DNSSECToCreateGrant"
        Effect = "Allow"
        Principal = {
          Service = "dnssec-route53.amazonaws.com"
        }
        Action   = "kms:CreateGrant"
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      },
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
    ]
  })
}

resource "aws_route53_key_signing_key" "sub" {
  hosted_zone_id             = aws_route53_zone.sub.id
  key_management_service_arn = aws_kms_key.dnssec.arn
  name                       = "${local.name}-ksk"
}

resource "aws_route53_hosted_zone_dnssec" "sub" {
  hosted_zone_id = aws_route53_key_signing_key.sub.hosted_zone_id
}

resource "aws_cloudwatch_log_group" "route53_sub" {
  provider          = aws.us-east-1
  name              = "/aws/route53/${local.name}.${local.hosted_zone_name}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_resource_policy" "route53_query_logging" {
  provider    = aws.us-east-1
  policy_name = "${local.name}-route53-query-logging"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "route53.amazonaws.com"
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.route53_sub.arn}:*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_route53_zone.sub.arn
          }
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
    ]
  })
}

resource "aws_route53_query_log" "sub" {
  depends_on               = [aws_cloudwatch_log_resource_policy.route53_query_logging]
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.route53_sub.arn
  zone_id                  = aws_route53_zone.sub.zone_id
}

# Validate records for the new HostedZone
resource "aws_route53_record" "ns" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = "${local.name}.${local.hosted_zone_name}"
  type    = "NS"
  ttl     = "30"
  records = aws_route53_zone.sub.name_servers
}

module "acm" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-acm.git?ref=d5d7ed0e9ad64c92b88a00a03e08f9faba1c4bd7"

  domain_name = "${local.name}.${local.hosted_zone_name}"
  zone_id     = aws_route53_zone.sub.zone_id

  subject_alternative_names = [
    "*.${local.name}.${local.hosted_zone_name}"
  ]

  wait_for_validation = true

  tags = {
    Name = "${local.name}.${local.hosted_zone_name}"
  }
}

#---------------------------------------------------------------
# ArgoCD Admin Password credentials with Secrets Manager
# Login to AWS Secrets manager with the same role as Terraform to extract the ArgoCD admin password with the secret name as "argocd"
#---------------------------------------------------------------
resource "random_password" "argocd" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_kms_key" "argocd" {
  description             = "CMK for ArgoCD Secrets Manager secret"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = local.tags
}

resource "aws_secretsmanager_secret" "argocd" {
  name                    = "${local.argocd_secret_manager_name}.${local.name}"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
  kms_key_id              = aws_kms_key.argocd.arn
}

resource "aws_secretsmanager_secret_version" "argocd" {
  secret_id     = aws_secretsmanager_secret.argocd.id
  secret_string = random_password.argocd.result
}

data "archive_file" "argocd_rotation" {
  type        = "zip"
  output_path = "${path.module}/argocd_rotation.zip"

  source {
    content  = <<-PY
import boto3

def handler(event, context):
    client = boto3.client("secretsmanager")
    arn = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]
    if step == "createSecret":
        import secrets
        import string
        alphabet = string.ascii_letters + string.digits + "!#$%&*()-_=+[]{}<>:?"
        password = "".join(secrets.choice(alphabet) for _ in range(16))
        try:
            client.put_secret_value(
                SecretId=arn,
                ClientRequestToken=token,
                SecretString=password,
                VersionStages=["AWSPENDING"],
            )
        except client.exceptions.ResourceExistsException:
            pass
    elif step == "setSecret":
        pass
    elif step == "testSecret":
        pass
    elif step == "finishSecret":
        metadata = client.describe_secret(SecretId=arn)
        current = None
        for version, stages in metadata["VersionIdsToStages"].items():
            if "AWSCURRENT" in stages:
                current = version
        if current != token:
            client.update_secret_version_stage(
                SecretId=arn,
                VersionStage="AWSCURRENT",
                MoveToVersionId=token,
                RemoveFromVersionId=current,
            )
    return event
PY
    filename = "index.py"
  }
}

resource "aws_iam_role" "argocd_rotation" {
  name = "${local.name}-argocd-rotation"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "argocd_rotation" {
  name = "${local.name}-argocd-rotation"
  role = aws_iam_role.argocd_rotation.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage",
        ]
        Resource = aws_secretsmanager_secret.argocd.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey",
        ]
        Resource = aws_kms_key.argocd.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "argocd_rotation_basic" {
  role       = aws_iam_role.argocd_rotation.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "argocd_rotation" {
  function_name    = "${local.name}-argocd-secret-rotation"
  filename         = data.archive_file.argocd_rotation.output_path
  source_code_hash = data.archive_file.argocd_rotation.output_base64sha256
  role             = aws_iam_role.argocd_rotation.arn
  handler          = "index.handler"
  runtime          = "python3.9"
  timeout          = 60
  tags             = local.tags

  depends_on = [
    aws_iam_role_policy.argocd_rotation,
    aws_iam_role_policy_attachment.argocd_rotation_basic,
  ]
}

resource "aws_lambda_permission" "argocd_rotation" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.argocd_rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = aws_secretsmanager_secret.argocd.arn
}

resource "aws_secretsmanager_secret_rotation" "argocd" {
  secret_id           = aws_secretsmanager_secret.argocd.id
  rotation_lambda_arn = aws_lambda_function.argocd_rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }

  depends_on = [
    aws_secretsmanager_secret_version.argocd,
    aws_lambda_permission.argocd_rotation,
  ]
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "aws_route53_zone" {
  description = "The new Route53 Zone"
  value       = aws_route53_zone.sub.name
}

output "aws_acm_certificate_status" {
  description = "Status of Certificate"
  value       = module.acm.acm_certificate_status
}


variable "environment_name" {
  description = "The name of environment Infrastructure stack, feel free to rename it. Used for cluster and VPC names."
  type        = string
  default     = "eks-blueprint"
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "argocd_secret_manager_name_suffix" {
  type        = string
  description = "Name of secret manager secret for ArgoCD Admin UI Password"
  default     = "argocd-admin-secret"
}

variable "hosted_zone_name" {
  type        = string
  description = "Route53 domain for the cluster."
  default     = "example.com"
}


terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.67"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }

  }
}