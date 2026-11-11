provider "aws" {
  region = local.region
}

locals {
  name   = "vpc-lattice"
  region = "us-west-2"

  domain = var.custom_domain_name

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

#-------------------------------
# Create Private Hosted Zone
#-------------------------------

resource "aws_route53_zone" "private_zone" {
  name = local.domain

  vpc {
    vpc_id = aws_vpc.example.id
  }

  #we will add vpc association in other terraform stack, prevent this one to revert this
  lifecycle {
    ignore_changes = [
      vpc,
    ]
  }

  force_destroy = true
  tags          = local.tags
}

#dummy VPC that will not be used, but needed to create private hosted zone
resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "Example VPC"
  }
}

resource "aws_flow_log" "example" {
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.example.id
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name = "vpc-flow-log"

  retention_in_days = 30
}

resource "aws_iam_role" "vpc_flow_log" {
  name        = "vpc-flow-log"
  description = "IAM role for VPC flow log"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "vpc_flow_log" {
  role       = aws_iam_role.vpc_flow_log.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsReadOnlyAccess"
}

resource "aws_security_group" "default" {
  name        = "default-sg"
  description = "Default security group"
  vpc_id      = aws_vpc.example.id

  ingress {
    from_port = -1
    to_port   = -1
    protocol  = -1
    self      = true
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags = {
    Name = "Default Security Group"
  }
}

resource "aws_default_security_group" "example" {
  vpc_id = aws_vpc.example.id

  ingress {
    from_port = -1
    to_port   = -1
    protocol  = -1
    self      = false
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags = {
    Name = "Default Security Group"
  }
}

################################################################################
# Create IAM role to talk to VPC Lattice services and get Certificate from Manager
################################################################################
data "aws_iam_policy_document" "eks_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}
resource "aws_iam_role" "vpc_lattice_role" {
  name               = "${local.name}-sigv4-client"
  description        = "IAM role for aws-sigv4-client VPC Lattice access"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
}

resource "aws_iam_role_policy_attachment" "vpc_lattice_invoke_access" {
  role       = aws_iam_role.vpc_lattice_role.name
  policy_arn = "arn:aws:iam::aws:policy/VPCLatticeServicesInvokeAccess"
}

resource "aws_iam_role_policy_attachment" "private_ca_read_only" {
  role       = aws_iam_role.vpc_lattice_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCertificateManagerPrivateCAReadOnly"
}



output "region" {
  description = "The AWS Region"
  value       = local.region
}

output "private_zone_id" {
  description = "The ID of the private hosted zone"
  value       = aws_route53_zone.private_zone.id
}

output "custom_domain_name" {
  description = "Custom domain name for the private hosted zone"
  value       = var.custom_domain_name
}

output "aws_acm_cert_arn" {
  description = "Arn of private Certificate"
  value       = aws_acm_certificate.private_domain_cert.arn
}

output "aws_acmpca_cert_authority_arn" {
  description = "Arn of ACM Private CA"
  value       = aws_acmpca_certificate_authority.this.arn
}

output "route53_private_zone_arn" {
  description = "Arn of Amazon Route53 Private Zone"
  value       = aws_route53_zone.private_zone.arn
}

output "vpc_lattice_client_role_arn" {
  value       = aws_iam_role.vpc_lattice_role.arn
  description = "ARN of the IAM role for VPC Lattice access"
}


#-------------------------------
# Associates a certificate with an AWS Certificate Manager Private Certificate Authority (ACM PCA Certificate Authority).
# An ACM PCA Certificate Authority is unable to issue certificates until it has a certificate associated with it.
# A root level ACM PCA Certificate Authority is able to self-sign its own root certificate.
#-------------------------------

# # https://docs.aws.amazon.com/acm-pca/latest/userguide/pca-rbp.html

resource "aws_acmpca_certificate_authority" "this" {
  enabled = true
  type    = "ROOT"

  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name  = var.custom_domain_name
      organization = var.organization
    }
  }

  permanent_deletion_time_in_days = 7

  tags = local.tags
}

resource "aws_acmpca_certificate" "this" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.this.arn
  certificate_signing_request = aws_acmpca_certificate_authority.this.certificate_signing_request
  signing_algorithm           = "SHA512WITHRSA"

  template_arn = "arn:aws:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = 10
  }
}

resource "aws_acmpca_certificate_authority_certificate" "this" {
  certificate_authority_arn = aws_acmpca_certificate_authority.this.arn

  certificate       = aws_acmpca_certificate.this.certificate
  certificate_chain = aws_acmpca_certificate.this.certificate_chain
}

#-------------------------------
# Create certificate in AWS Certificate Manager
#-------------------------------

resource "aws_acm_certificate" "private_domain_cert" {
  domain_name = var.custom_domain_name
  #validation_method = "DNS"

  subject_alternative_names = [
    "*.${var.custom_domain_name}"
  ]

  options {
    certificate_transparency_logging_preference = "ENABLED"
  }

  lifecycle {
    create_before_destroy = true
  }

  certificate_authority_arn = aws_acmpca_certificate_authority.this.arn

  tags = local.tags
}


variable "organization" {
  type        = string
  description = "organization for the certificate"
  default     = "example"
}

variable "custom_domain_name" {
  description = "Custom domain name for the private hosted zone"
  type        = string
  default     = "example.com"
}


terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34, < 6.0"
    }
  }
}