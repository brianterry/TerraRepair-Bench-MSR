provider "aws" {
  region = local.region
}

provider "aws" {
  alias  = "replica"
  region = "us-east-1"
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

  exclude_zone_ids = ["usw2-az4"]
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
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=37b334ea9b0c317a5fdb6a897425f2a365a9a9c3"

  cluster_name                         = local.name
  cluster_version                      = "1.30"
  cluster_endpoint_public_access       = false
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = [local.vpc_cidr]

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

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

  node_security_group_enable_recommended_rules = false

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    ingress_cluster_443 = {
      description                   = "Cluster API to node groups"
      protocol                      = "tcp"
      from_port                     = 443
      to_port                       = 443
      type                          = "ingress"
      source_cluster_security_group = true
    }
    ingress_cluster_kubelet = {
      description                   = "Cluster API to node kubelets"
      protocol                      = "tcp"
      from_port                     = 10250
      to_port                       = 10250
      type                          = "ingress"
      source_cluster_security_group = true
    }
    ingress_cluster_coredns_tcp = {
      description                   = "Cluster to node CoreDNS TCP"
      protocol                      = "tcp"
      from_port                     = 53
      to_port                       = 53
      type                          = "ingress"
      source_cluster_security_group = true
    }
    ingress_cluster_coredns_udp = {
      description                   = "Cluster to node CoreDNS UDP"
      protocol                      = "udp"
      from_port                     = 53
      to_port                       = 53
      type                          = "ingress"
      source_cluster_security_group = true
    }
    egress_vpc = {
      description = "Egress to VPC"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = [local.vpc_cidr]
    }
  }

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
  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addons.git?ref=a996914f9f24ed73a31477db42b1f9c0ea9a3a24"

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
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-role-for-service-accounts-eks?ref=de95e21a3c52cd384036dbd0978008baa233cfe4"

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
# KMS
################################################################################

data "aws_iam_policy_document" "s3_kms" {
  statement {
    sid    = "EnableRootAccount"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCURService"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowS3"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.s3_kms.json

  tags = local.tags
}

resource "aws_kms_key" "s3_replica" {
  provider                = aws.replica
  description             = "KMS key for S3 replica bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = local.tags
}

################################################################################
# S3 Access Logs
################################################################################

resource "aws_s3_bucket" "logs" {
  bucket_prefix = "s3-access-logs-"
  force_destroy = true

  tags = local.tags
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "logs" {
  statement {
    sid    = "S3ServerAccessLogsPolicy"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/*"]
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        aws_s3_bucket.cur.arn,
        aws_s3_bucket.athena_results.arn
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs.json
}

################################################################################
# S3 Replica
################################################################################

resource "aws_s3_bucket" "replica" {
  provider      = aws.replica
  bucket_prefix = "kubecost-replica-"
  force_destroy = true

  tags = local.tags
}

resource "aws_s3_bucket_versioning" "replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_replica.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "replication" {
  name = "${local.name}-s3-replication"

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

  tags = local.tags
}

data "aws_iam_policy_document" "replication" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.cur.arn,
      aws_s3_bucket.athena_results.arn
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
      "${aws_s3_bucket.cur.arn}/*",
      "${aws_s3_bucket.athena_results.arn}/*"
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
      "${aws_s3_bucket.replica.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
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
      aws_kms_key.s3_replica.arn
    ]
  }
}

resource "aws_iam_role_policy" "replication" {
  name   = "${local.name}-s3-replication"
  role   = aws_iam_role.replication.id
  policy = data.aws_iam_policy_document.replication.json
}

################################################################################
# S3 Notifications
################################################################################

resource "aws_sns_topic" "s3_notifications" {
  name = "${local.name}-s3-notifications"

  tags = local.tags
}

data "aws_iam_policy_document" "s3_notifications" {
  statement {
    sid    = "AllowS3Publish"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.s3_notifications.arn]
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        aws_s3_bucket.cur.arn,
        aws_s3_bucket.athena_results.arn
      ]
    }
  }
}

resource "aws_sns_topic_policy" "s3_notifications" {
  arn    = aws_sns_topic.s3_notifications.arn
  policy = data.aws_iam_policy_document.s3_notifications.json
}

################################################################################
# CUR
################################################################################

resource "aws_s3_bucket" "cur" {
  bucket_prefix = "kubecost-"
  force_destroy = true

  tags = local.tags
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.cur.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cur" {
  bucket = aws_s3_bucket.cur.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cur" {
  bucket = aws_s3_bucket.cur.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "cur" {
  bucket = aws_s3_bucket.cur.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "cur/"
}

resource "aws_s3_bucket_lifecycle_configuration" "cur" {
  bucket = aws_s3_bucket.cur.id
  rule {
    id = "cost"
    expiration {
      days = 7
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
    status = "Enabled"
  }
}

resource "aws_s3_bucket_notification" "cur" {
  bucket = aws_s3_bucket.cur.id

  topic {
    topic_arn = aws_sns_topic.s3_notifications.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.s3_notifications]
}

resource "aws_s3_bucket_replication_configuration" "cur" {
  depends_on = [
    aws_s3_bucket_versioning.cur,
    aws_s3_bucket_versioning.replica
  ]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.cur.id

  rule {
    id       = "replicate"
    status   = "Enabled"
    priority = 0

    filter {}

    delete_marker_replication {
      status = "Disabled"
    }

    destination {
      bucket        = aws_s3_bucket.replica.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.s3_replica.arn
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
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
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "athena-results/"
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  rule {
    id = "cost"
    expiration {
      days = 1
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_notification" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  topic {
    topic_arn = aws_sns_topic.s3_notifications.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.s3_notifications]
}

resource "aws_s3_bucket_replication_configuration" "athena_results" {
  depends_on = [
    aws_s3_bucket_versioning.athena_results,
    aws_s3_bucket_versioning.replica
  ]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.athena_results.id

  rule {
    id       = "replicate"
    status   = "Enabled"
    priority = 0

    filter {}

    delete_marker_replication {
      status = "Disabled"
    }

    destination {
      bucket        = aws_s3_bucket.replica.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.s3_replica.arn
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }
}

################################################################################
# Kubecost
################################################################################

module "kubecost_irsa" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-role-for-service-accounts-eks?ref=88ac73d1b381672e92d7f0c545680145c24e6d1b"

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
    sid    = "athenaaccess"
    effect = "Allow"
    actions = [
      "athena:BatchGetNamedQuery",
      "athena:BatchGetQueryExecution",
      "athena:GetNamedQuery",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:GetQueryResultsStream",
      "athena:GetWorkGroup",
      "athena:ListNamedQueries",
      "athena:ListQueryExecutions",
      "athena:ListWorkGroups",
      "athena:StartQueryExecution",
      "athena:StopQueryExecution",
      "athena:GetDataCatalog",
      "athena:GetDatabase",
      "athena:GetTableMetadata",
      "athena:ListDataCatalogs",
      "athena:ListDatabases",
      "athena:ListTableMetadata"
    ]
    resources = [
      "arn:aws:athena:${local.region}:${data.aws_caller_identity.current.account_id}:workgroup/*",
      "arn:aws:athena:${local.region}:${data.aws_caller_identity.current.account_id}:datacatalog/*"
    ]
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
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["true"]
    }
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
  statement {
    sid    = "KMSAccess"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = [
      aws_kms_key.s3.arn
    ]
  }
}

module "eks_blueprints_addon" {
  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addon.git?ref=9252743b4e00e5d6e3e5961e1b9d386e7b3b2383"

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
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=e226cc7153f1ec7e65d2d51d1417bf44e10e8d4d"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_traffic_type                = "REJECT"

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