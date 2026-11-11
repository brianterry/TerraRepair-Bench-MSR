provider "aws" {
  region = local.region
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  # Do not include local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name   = basename(path.cwd)
  region = "us-west-2"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

################################################################################
# Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.11"

  cluster_name                   = local.name
  cluster_version               = "1.30"
  cluster_endpoint_public_access = false

  # Give the Terraform identity admin access to the cluster
  # which will allow resources to be deployed into the cluster
  enable_cluster_creator_admin_permissions = true

  # EKS Addons
  cluster_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    initial = {
      instance_types = ["m6i.large", "m5.large", "m5n.large", "m5zn.large"]
      capacity_type  = "SPOT"
      min_size       = 3
      max_size       = 10
      desired_size   = 5
    }
  }

  tags = local.tags
}

################################################################################
# Addons
################################################################################

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_metrics_server = true

  depends_on = [module.eks.eks_managed_node_groups]
}

################################################################################
# EBS CSI Driver Role
################################################################################

module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name = "${local.name}-ebs-csi-driver"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

################################################################################
# CUR
################################################################################

resource "aws_s3_bucket" "cur" {
  bucket_prefix = "kubecost-"
  force_destroy = true

  tags = local.tags

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
        kms_master_key_id = "alias/aws/s3"
      }
    }
  }

  public_access_block_configuration {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }

  lifecycle_rule {
    id      = "cost"
    enabled = true

    expiration {
      days = 7
    }
  }

  logging {
    target_bucket = aws_s3_bucket.cur_logs.id
    target_prefix = "logs/"
  }

  event_notification_configuration {
    destination = "sns"
    event_types = ["s3:ObjectCreated:*"]
    topic_arn   = aws_sns_topic.cur_events.arn
  }

  tags = local.tags
}

resource "aws_s3_bucket" "cur_logs" {
  bucket_prefix = "kubecost-logs-"
  force_destroy = true

  tags = local.tags
}

resource "aws_sns_topic" "cur_events" {
  name = "cur-events"
}

resource "aws_s3_bucket_public_access_block" "cur" {
  bucket = aws_s3_bucket.cur.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cur" {
  bucket = aws_s3_bucket.cur.id
  rule {
    id = "cost"
    expiration {
      days = 7
    }
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "allow_access" {
  bucket = aws_s3_bucket.cur.id
  policy = data.aws_iam_policy_document.cur_bucket_policy.json
}

data "aws_iam_policy_document" "cur_bucket_policy" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }

    actions = [
      "s3:GetBucketAcl",
      "s3:GetBucketPolicy"
    ]

    resources = [
      aws_s3_bucket.cur.arn,
    ]
  }

  statement {
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.cur.arn}/*",
    ]
  }
}

resource "aws_cur_report_definition" "cur" {
  report_name                = "kubecost"
  time_unit                  = "DAILY"
  format                     = "Parquet"
  compression                = "Parquet"
  additional_schema_elements = ["RESOURCES"]
  s3_bucket                  = aws_s3_bucket.cur.id
  s3_prefix                  = "reports"
  s3_region                  = local.region
  additional_artifacts       = ["ATHENA"]
  report_versioning          = "OVERWRITE_REPORT"
}

################################################################################
# Athena
################################################################################

resource "aws_s3_bucket" "athena_results" {
  bucket_prefix = "aws-athena-query-results-"
  force_destroy = true

  tags = local.tags

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
        kms_master_key_id = "alias/aws/s3"
      }
    }
  }

  public_access_block_configuration {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }

  lifecycle_rule {
    id      = "cost"
    enabled = true

    expiration {
      days = 1
    }
  }

  logging {
    target_bucket = aws_s3_bucket.athena_results_logs.id
    target_prefix = "logs/"
  }

  event_notification_configuration {
    destination = "sns"
    event_types = ["s3:ObjectCreated:*"]
    topic_arn   = aws_sns_topic.athena_results_events.arn
  }

  tags = local.tags
}

resource "aws_s3_bucket" "athena_results_logs" {
  bucket_prefix = "aws-athena-query-results-logs-"
  force_destroy = true

  tags = local.tags
}

resource "aws_sns_topic" "athena_results_events" {
  name = "athena-results-events"
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  rule {
    id = "cost"
    expiration {
      days = 1
    }
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "athena_results" {
  depends_on = [aws_s3_bucket_ownership_controls.athena_results]

  bucket = aws_s3_bucket.athena_results.id
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  policy = data.aws_iam_policy_document.athena_results_bucket_policy.json
}

data "aws_iam_policy_document" "athena_results_bucket_policy" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["athena.amazonaws.com"]
    }

    actions = [
      "s3:GetBucketAcl",
      "s3:GetBucketPolicy"
    ]

    resources = [
      aws_s3_bucket.athena_results.arn,
    ]
  }

  statement {
    principals {
      type        = "Service"
      identifiers = ["athena.amazonaws.com"]
    }

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.athena_results.arn}/*",
    ]
  }
}

################################################################################
# Kubecost
################################################################################

module "kubecost_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name_prefix           = "${local.name}-"
  assume_role_condition_test = "StringLike"

  role_policy_arns = {
    policy = aws_iam_policy.kubecost.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kubecost:*"]
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "kubecost" {
  name   = local.name
  policy = data.aws_iam_policy_document.combined.json
}

data "aws_iam_policy_document" "combined" {
  source_policy_documents = [
    data.aws_iam_policy_document.kubecost.json,
    data.aws_iam_policy_document.athena.json
  ]
}

data "aws_iam_policy_document" "kubecost" {
  statement {
    sid    = "KubecostSavingsAccess"
    effect = "Allow"
    actions = [
      "ec2:DescribeAddresses",
      "ec2:DescribeVolumes"
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "s3:ListAllMyBuckets",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "athena" {
  statement {
    sid       = "athenaaccess"
    effect    = "Allow"
    actions   = ["athena:*"]
    resources = ["*"]
  }
  statement {
    sid    = "ReadAccessToAthenaCurDataViaGlue"
    effect = "Allow"
    actions = [
      "glue:GetDatabase*",
      "glue:GetTable*",
      "glue:GetPartition*",
      "glue:GetUserDefinedFunction",
      "glue:BatchGetPartition"
    ]
    resources = [
      "arn:aws:glue:*:*:catalog",
      "arn:aws:glue:*:*:database/athenacurcfn*",
      "arn:aws:glue:*:*:table/athenacurcfn*/*"
    ]
  }
  statement {
    sid    = "AthenaQueryResultsOutput"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload",
      "s3:CreateBucket",
      "s3:PutObject"
    ]
    resources = [
      aws_s3_bucket.athena_results.arn,
      "${aws_s3_bucket.athena_results.arn}/*"
    ]
  }
  statement {
    sid    = "S3ReadAccessToAwsBillingData"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:List*",
      "s3:Get*"
    ]
    resources = [
      aws_s3_bucket.cur.arn,
      "${aws_s3_bucket.cur.arn}/*"
    ]
  }
}

module "eks_blueprints_addon" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.1.1" #ensure to update this to the latest/desired version

  chart            = "cost-analyzer"
  chart_version    = "1.108.1"
  repository       = "https://kubecost.github.io/cost-analyzer/"
  description      = "Kubecost helm Chart deployment configuration"
  namespace        = "kubecost"
  create_namespace = true

  values = [templatefile("kubecost-values.yaml", {
    kubecostToken    = var.kubecost_token
    service-account  = "kubecost-cost-analyzer"
    iam-role-arn     = module.kubecost_irsa.iam_role_arn
    projectID        = data.aws_caller_identity.current.account_id
    athenaProjectID  = data.aws_caller_identity.current.account_id
    athenaBucketName = "s3://${aws_s3_bucket.athena_results.id}"
    athenaRegion     = local.region
    athenaDatabase   = "athenacurcfn_kubecost"
    athenaTable      = "kubecost"
    })
  ]

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --alias ${module.eks.cluster_name}"
}

output "cur_bucket_id" {
  description = "Kubecost CUR bucket id"
  value       = aws_s3_bucket.cur.id
}

output "s3_cur_report_prefix" {
  description = "Kubecost CUR bucket prefix"
  value       = aws_cur_report_definition.cur.s3_prefix
}

output "region" {
  description = "region"
  value       = local.region
}

variable "kubecost_token" {
  type        = string
  description = "To find or obtain Kubecost token, go to https://www.kubecost.com/install#show-instructions"
}

terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34, < 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.9, < 3.0"
    }
  }

  # ##  Used for end-to-end testing on project; update to suit your needs
  # backend "s3" {
  #   bucket = "terraform-ssp-github-actions-state"
  #   region = "us-west-2"
  #   key    = "e2e/kubecost/terraform.tfstate"
  # }
}