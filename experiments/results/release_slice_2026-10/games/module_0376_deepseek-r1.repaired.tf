module "ebs_csi_driver_irsa" {
  source  = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-role-for-service-accounts-eks?ref=v5.20.0"
  version = "~> 5.20"

  role_name_prefix = "${module.eks.cluster_name}-ebs-csi-driver-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

module "eks_blueprints_addons" {
  source  = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=v1.2.0"
  version = "~> 1.2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns = {
      preserve = true
    }
    vpc-cni = {
      preserve = true
    }
    kube-proxy = {
      preserve = true
    }
  }

  enable_aws_load_balancer_controller = true

  enable_external_dns = true
  external_dns = {
    values = [templatefile("${path.module}/helm-values/external-dns-values.yaml", {
      txtOwnerId   = local.name
      domainFilter = var.eks_cluster_domain
    })]
  }

  enable_cert_manager = true

  enable_metrics_server = true
  metrics_server = {
    set = [
      {
        name  = "image.repository"
        value = "registry.k8s.io/metrics-server/metrics-server"
      }
    ]
  }

  enable_cluster_autoscaler = true

  enable_aws_for_fluentbit = true
  aws_for_fluentbit_cw_log_group = {
    create            = true
    use_name_prefix   = false
    name              = "/${local.name}/aws-fluentbit-logs"
    retention_in_days = 30
  }
  aws_for_fluentbit = {
    create_namespace = true
    namespace        = "aws-for-fluentbit"
    create_role      = true
    role_policies    = { "policy1" = aws_iam_policy.fluentbit.arn }
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      region               = local.region,
      cloudwatch_log_group = "/${local.name}/aws-fluentbit-logs"
      s3_bucket_name       = module.s3_bucket.s3_bucket_id
      cluster_name         = module.eks.cluster_name
    })]
  }

  enable_aws_cloudwatch_metrics = true

  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    values = [
      var.enable_amazon_prometheus ? templatefile("${path.module}/helm-values/kube-prometheus-amp-enable.yaml", {
        region              = local.region
        amp_sa              = local.amp_ingest_service_account
        amp_irsa            = module.amp_ingest_irsa[0].iam_role_arn
        amp_remotewrite_url = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}/api/v1/remote_write"
        amp_url             = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}"
        storage_class_type  = kubernetes_storage_class.ebs_csi_encrypted_gp3_storage_class.id
      }) : templatefile("${path.module}/helm-values/kube-prometheus.yaml", {})
    ]
    chart_version = "48.1.1"
    set_sensitive = [
      {
        name  = "grafana.adminPassword"
        value = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
      }
    ],
  }

  tags = local.tags
}

resource "kubernetes_annotations" "gp2_default" {
  annotations = {
    "storageclass.kubernetes.io/is-default-class" : "false"
  }
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  force = true

  depends_on = [module.eks]
}

resource "kubernetes_storage_class" "ebs_csi_encrypted_gp3_storage_class" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    fsType    = "xfs"
    encrypted = true
    type      = "gp3"
  }

  depends_on = [kubernetes_annotations.gp2_default]
}

resource "random_password" "grafana" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "grafana" {
  name                    = "grafana-${random_string.random_suffix.result}"
  recovery_window_in_days = 0
  kms_key_id              = "alias/aws/secretsmanager"
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}

resource "random_string" "random_suffix" {
  length  = 10
  special = false
  upper   = false
}

resource "random_password" "nifi_keystore_password" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "nifi_keystore_password" {
  name                    = "nifi_keystore_password-${random_string.random_suffix.result}"
  recovery_window_in_days = 0
  kms_key_id              = "alias/aws/secretsmanager"
}

resource "aws_secretsmanager_secret_version" "nifi_keystore_password" {
  secret_id     = aws_secretsmanager_secret.nifi_keystore_password.id
  secret_string = random_password.nifi_keystore_password.result
}

resource "random_password" "nifi_truststore_password" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "nifi_truststore_password" {
  recovery_window_in_days = 0
  kms_key_id              = "alias/aws/secretsmanager"
}

resource "aws_secretsmanager_secret_version" "nifi_truststore_password" {
  secret_id     = aws_secretsmanager_secret.nifi_truststore_password.id
  secret_string = random_password.nifi_truststore_password.result
}

resource "random_password" "nifi_login_password" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "nifi_login_password" {
  name                    = "nifi_login_password-${random_string.random_suffix.result}"
  recovery_window_in_days = 0
  kms_key_id              = "alias/aws/secretsmanager"
}

resource "aws_secretsmanager_secret_version" "nifi_login_password" {
  secret_id     = aws_secretsmanager_secret.nifi_login_password.id
  secret_string = random_password.nifi_login_password.result
}

resource "random_password" "sensitive_key" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "sensitive_key" {
  name                    = "sensitive_key-${random_string.random_suffix.result}"
  recovery_window_in_days = 0
  kms_key_id              = "alias/aws/secretsmanager"
}

resource "aws_secretsmanager_secret_version" "sensitive_key" {
  secret_id     = aws_secretsmanager_secret.sensitive_key.id
  secret_string = random_password.sensitive_key.result
}

resource "helm_release" "nifi" {
  name             = "nifi"
  repository       = "https://cetic.github.io/helm-charts"
  chart            = "nifi"
  version          = "1.1.3"
  namespace        = "nifi"
  create_namespace = true

  values = [templatefile("${path.module}/helm-values/nifi-values.yaml", {
    hostname            = join(".", [var.nifi_sub_domain, var.eks_cluster_domain])
    ssl_cert_arn        = data.aws_acm_certificate.issued.arn
    nifi_username       = var.nifi_username
    nifi_password       = data.aws_secretsmanager_secret_version.nifi_login_password_version.secret_string
    keystore_password   = data.aws_secretsmanager_secret_version.nifi_keystore_password_version.secret_string
    truststore_password = data.aws_secretsmanager_secret_version.nifi_truststore_password_version.secret_string
    sensitive_key       = data.aws_secretsmanager_secret_version.sensitive_key_version.secret_string
  })]

  depends_on = [kubernetes_storage_class.ebs_csi_encrypted_gp3_storage_class]
}

resource "aws_iam_policy" "fluentbit" {
  description = "IAM policy policy for FluentBit"
  name        = "${local.name}-fluentbit-additional"
  policy      = data.aws_iam_policy_document.fluent_bit.json
}

module "s3_bucket" {
  source  = "github.com/terraform-aws-modules/terraform-aws-s3-bucket?ref=v3.0.0"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-nifi-logs-"

  force_destroy = true

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  logging = {
    target_bucket = module.s3_bucket.s3_bucket_id
    target_prefix = "logs/"
  }

  tags = local.tags
}

resource "aws_iam_policy" "grafana" {
  count = var.enable_amazon_prometheus ? 1 : 0

  description = "IAM policy for Grafana Pod"
  name_prefix = format("%s-%s-", local.name, "grafana")
  path        = "/"
  policy      = data.aws_iam_policy_document.grafana[0].json
}

data "aws_iam_policy_document" "grafana" {
  count = var.enable_amazon_prometheus ? 1 : 0

  statement {
    sid       = "AllowReadingMetricsFromCloudWatch"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics"
    ]
  }

  statement {
    sid       = "AllowGetInsightsCloudWatch"
    effect    = "Allow"
    resources = ["arn:${local.partition}:cloudwatch:${local.region}:${local.account_id}:insight-rule/*"]

    actions = [
      "cloudwatch:GetInsightRuleReport",
    ]
  }

  statement {
    sid       = "AllowReadingAlarmHistoryFromCloudWatch"
    effect    = "Allow"
    resources = ["arn:${local.partition}:cloudwatch:${local.region}:${local.account_id}:alarm:*"]

    actions = [
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:DescribeAlarms",
    ]
  }

  statement {
    sid       = "AllowReadingLogsFromCloudWatch"
    effect    = "Allow"
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:*:log-stream:*"]

    actions = [
      "logs:DescribeLogGroups",
      "logs:GetLogGroupFields",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "logs:GetLogEvents",
    ]
  }

  statement {
    sid       = "AllowReadingTagsInstancesRegionsFromEC2"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
    ]
  }

  statement {
    sid       = "AllowReadingResourcesForTags"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["tag:GetResources"]
  }

  statement {
    sid    = "AllowListApsWorkspaces"
    effect = "Allow"
    resources = [
      "arn:${local.partition}:aps:${local.region}:${local.account_id}:/*",
      "arn:${local.partition}:aps:${local.region}:${local.account_id}:workspace/*",
      "arn:${local.partition}:aps:${local.region}:${local.account_id}:workspace/*/*",
    ]
    actions = [
      "aps:ListWorkspaces",
      "aps:DescribeWorkspace",
      "aps:GetMetricMetadata",
      "aps:GetSeries",
      "aps:QueryMetrics",
      "aps:RemoteWrite",
      "aps:GetLabels"
    ]
  }
}

resource "aws_prometheus_workspace" "amp" {
  count = var.enable_amazon_prometheus ? 1 : 0

  alias = format("%s-%s", "amp-ws", local.name)
  tags  = local.tags
}

module "amp_ingest_irsa" {
  count = var.enable_amazon_prometheus ? 1 : 0

  source         = "github.com/aws-ia/terraform-aws-eks-blueprints-addon?ref=v1.0.0"
  version        = "~> 1.0"
  create_release = false
  create_role    = true
  create_policy  = false
  role_name      = format("%s-%s", local.name, "amp-ingest")
  role_policies  = { amp_policy = aws_iam_policy.grafana[0].arn }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = local.amp_namespace
      service_account = local.amp_ingest_service_account
    }
  }

  tags = local.tags
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id = aws_secretsmanager_secret.grafana.id

  depends_on = [aws_secretsmanager_secret_version.grafana]
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_acm_certificate" "issued" {
  domain   = var.acm_certificate_domain
  statuses = ["ISSUED"]
}

data "aws_secretsmanager_secret_version" "nifi_login_password_version" {
  secret_id = aws_secretsmanager_secret.nifi_login_password.id

  depends_on = [aws_secretsmanager_secret_version.nifi_login_password]
}

data "aws_secretsmanager_secret_version" "nifi_truststore_password_version" {
  secret_id = aws_secretsmanager_secret.nifi_truststore_password.id

  depends_on = [aws_secretsmanager_secret_version.nifi_truststore_password]
}

data "aws_secretsmanager_secret_version" "nifi_keystore_password_version" {
  secret_id = aws_secretsmanager_secret.nifi_keystore_password.id

  depends_on = [aws_secretsmanager_secret_version.nifi_keystore_password]
}

data "aws_secretsmanager_secret_version" "sensitive_key_version" {
  secret_id = aws_secretsmanager_secret.sensitive_key.id

  depends_on = [aws_secretsmanager_secret_version.sensitive_key]
}

data "aws_iam_policy_document" "fluent_bit" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${module.s3_bucket.s3_bucket_id}/*"]

    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObject",
      "s3:GetObjectAcl",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion"
    ]
  }
}

locals {
  name   = var.name
  region = var.region
  azs    = slice(data.aws_availability_zones.available.names, 0, 3)

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}

module "eks" {
  source  = "github.com/terraform-aws-modules/terraform-aws-eks?ref=v19.15.0"
  version = "~> 19.15"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = false
  cluster_endpoint_public_access_cidrs = ["10.1.0.0/16"]

  eks_managed_node_groups = {
    nifi_node_group = {
      instance_types = ["m5.xlarge"]
      capacity_type  = "ON_DEMAND"
      max_size       = 5
      min_size       = 3
      desired_size   = 3
      security_group_rules = {
        egress_restricted = {
          description = "Restrict egress"
          protocol    = "-1"
          from_port   = 0
          to_port     = 0
          type        = "egress"
          cidr_blocks = [var.vpc_cidr]
        }
      }
    }
  }

  tags = local.tags
}

output "configure_kubectl" {
  value = "aws eks --region ${var.region} update-kubeconfig --name ${var.name}"
}

output "nifi_login_password_secret_name" {
  value = aws_secretsmanager_secret.nifi_login_password.name
}

output "grafana_secret_name" {
  value = aws_secretsmanager_secret.grafana.name
}

provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

variable "name" {
  default = "nifi-on-eks"
}

variable "region" {
  default = "us-west-2"
}

variable "eks_cluster_version" {
  default = "1.27"
}

variable "vpc_cidr" {
  default = "10.1.0.0/16"
}

variable "public_subnets" {
  default = ["10.1.192.0/20", "10.1.208.0/20", "10.1.224.0/20"]
}

variable "private_subnets" {
  default = ["10.1.0.0/18", "10.1.64.0/18", "10.1.128.0/18"]
}

variable "eks_cluster_domain" {}

variable "nifi_sub_domain" {
  default = "mynifi"
}

variable "acm_certificate_domain" {}

variable "nifi_username" {
  default = "admin"
}

variable "enable_amazon_prometheus" {
  default = true
}

terraform {
  required_version = ">= 1.3.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.95"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.3.2"
    }
  }
}

module "vpc" {
  source  = "github.com/terraform-aws-modules/terraform-aws-vpc?ref=v5.0.0"
  version = "~> 5.0"

  name = local.name
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60
  flow_log_traffic_type                = "REJECT"

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}