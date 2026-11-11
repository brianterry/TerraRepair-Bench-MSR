module "ebs_csi_driver_irsa" {
  source                = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-role-for-service-accounts-eks?ref=5cf2a61"
  role_name_prefix      = format("%s-%s", local.name, "ebs-csi-driver")
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
  source  = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=cc9c0c7"
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
    eks-pod-identity-agent = {}
  }

  enable_cert_manager = true
  cert_manager = {
    set_values = [
      {
        name  = "extraArgs[0]"
        value = "--enable-certificate-owner-ref=false"
      },
    ]
  }

  enable_metrics_server = true
  metrics_server = {
    values = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {})]
  }

  enable_cluster_autoscaler = true
  cluster_autoscaler = {
    create_role = true
    values = [templatefile("${path.module}/helm-values/cluster-autoscaler-values.yaml", {
      aws_region     = var.region,
      eks_cluster_id = module.eks.cluster_name
    })]
  }

  enable_aws_cloudwatch_metrics = true
  aws_cloudwatch_metrics = {
    values = [templatefile("${path.module}/helm-values/aws-cloudwatch-metrics-values.yaml", {})]
  }
}

module "karpenter" {
  source  = "github.com/terraform-aws-modules/terraform-aws-eks//modules/karpenter?ref=3a0e0c1"
  cluster_name          = module.eks.cluster_name
  enable_v1_permissions = false

  enable_pod_identity             = true
  create_pod_identity_association = true

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags

  depends_on = [
    module.eks
  ]
}

resource "helm_release" "karpenter" {
  namespace  = "kube-system"
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.6.1"
  wait       = false

  values = [
    <<-EOT
    nodeSelector:
      NodeGroupType: core
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    webhook:
      enabled: false
    EOT
  ]

  lifecycle {
    ignore_changes = [
      repository_password
    ]
  }

  depends_on = [
    module.karpenter
  ]
}

module "eks_data_addons" {
  depends_on = [module.flink_irsa_jobs, module.flink_irsa_operator, module.eks_blueprints_addons, helm_release.karpenter]

  source            = "github.com/aws-ia/terraform-aws-eks-data-addons?ref=1a2b3c4"
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_emr_flink_operator = true
  emr_flink_operator_helm_config = {
    repository               = "oci://public.ecr.aws/emr-on-eks"
    operatorExecutionRoleArn = module.flink_irsa_operator.iam_role_arn
    version                  = "7.9.0"
  }

  enable_karpenter_resources = true
  karpenter_resources_helm_config = {
    flink-compute-optimized = {
      values = [
        <<-EOT
      name: flink-compute-optimized

      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:

        karpenterRole: ${split("/", module.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            Name: "${module.eks.cluster_name}-private*"
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0

      nodePool:

        labels:
          - type: karpenter
          - NodeGroupType: FlinkComputeOptimized
          - multiArch: Flink
        nodeClassRef:
          name: flink-compute-optimized
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot","on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["c"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["c5d"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: ["4", "8", "16", "36"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["2"]

        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmpty
          consolidateAfter: 30s
          expireAfter: 720h
        weight: 100
      EOT
      ]
    }
    flink-graviton-memory-optimized = {
      values = [
        <<-EOT
      name: flink-graviton-memory-optimized
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        karpenterRole: ${split("/", module.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            Name: "${module.eks.cluster_name}-private*"
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0
      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: FlinkGravitonMemoryOptimized
          - multiArch: Flink
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["arm64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["r"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["r6gd"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: ["4", "8", "16", "32"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["2"]
        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmpty
          consolidateAfter: 30s
          expireAfter: 720h
        weight: 50
      EOT
      ]
    }
  }
}

resource "kubernetes_namespace_v1" "flink_team_a" {
  metadata {
    name = "${local.flink_team}-ns"
  }
  timeouts {
    delete = "15m"
  }
}

resource "aws_iam_policy" "flink" {
  description = "IAM role policy for flink Job execution"
  name        = "${local.name}-flink-irsa"
  policy      = data.aws_iam_policy_document.flink_sample_job.json
}

module "flink_irsa_jobs" {
  source  = "github.com/aws-ia/terraform-aws-eks-blueprints-addon?ref=d4e5f6b"
  create_release = false
  create_role   = true
  role_name     = "${local.name}-${local.flink_team}"
  create_policy = false
  role_policies = {
    flink_team_a_policy = aws_iam_policy.flink.arn
  }
  assume_role_condition_test = "StringLike"
  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = "${local.flink_team}-ns"
      service_account = "emr-containers-sa-*-*-${data.aws_caller_identity.current.account_id}-*"
    }
  }
}

module "flink_irsa_operator" {
  source  = "github.com/aws-ia/terraform-aws-eks-blueprints-addon?ref=d4e5f6b"
  create_release = false
  create_role   = true
  role_name     = "${local.name}-operator"
  create_policy = false
  role_policies = {
    flink_team_a_policy = aws_iam_policy.flink.arn
  }
  assume_role_condition_test = "StringLike"
  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = "${local.flink_operator}-ns"
      service_account = "emr-containers-sa-flink-operator"
    }
  }
}

resource "aws_cloudwatch_log_group" "flink_team_a" {
  name              = "/aws/emr-flink/flink-team-a"
  retention_in_days = 365
  kms_key_id        = "alias/aws/cloudwatch"
}

data "aws_iam_policy_document" "flink_sample_job" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = [
      module.s3_bucket.s3_bucket_arn,
      "${module.s3_bucket.s3_bucket_arn}/*"
    ]
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetBucketLocation",
      "s3:GetObjectVersion"
    ]
  }
  statement {
    sid       = ""
    effect    = "Allow"
    resources = [
      aws_cloudwatch_log_group.flink_team_a.arn,
      "${aws_cloudwatch_log_group.flink_team_a.arn}:*"
    ]
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
  }
}

module "s3_bucket" {
  source                           = "github.com/terraform-aws-modules/terraform-aws-s3-bucket?ref=345a1e2"
  bucket_prefix                    = "${local.name}-"
  attach_require_latest_tls_policy = true
  block_public_acls                = true
  block_public_policy              = true
  ignore_public_acls               = true
  restrict_public_buckets          = true
  versioning = {
    enabled = true
  }
  logging = {
    target_bucket = module.s3_bucket.s3_bucket_id
    target_prefix = "logs/"
  }
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
  tags = local.tags
}

resource "aws_s3_object" "checkpoints" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "checkpoints/"
  content_type = "application/x-directory"
}

resource "aws_s3_object" "savepoints" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "savepoints/"
  content_type = "application/x-directory"
}

resource "aws_s3_object" "jobmanager" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "jobmanager/"
  content_type = "application/x-directory"
}

resource "aws_s3_object" "logs" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "logs/"
  content_type = "application/x-directory"
}

locals {
  name   = var.name
  region = var.region
  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
  flink_team     = "flink-team-a"
  flink_operator = "flink-kubernetes-operator"
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

data "aws_caller_identity" "current" {}

module "eks" {
  source  = "github.com/terraform-aws-modules/terraform-aws-eks?ref=3a0e0c1"
  cluster_name                    = local.name
  cluster_version                 = var.eks_cluster_version
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = false
  cluster_enabled_log_types       = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  vpc_id                          = module.vpc.vpc_id
  subnet_ids                      = module.vpc.private_subnets
  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }

  eks_managed_node_groups = {
    core_node_group = {
      name        = "core-node-group"
      description = "EKS managed node group example launch template"
      subnet_ids  = module.vpc.private_subnets

      min_size     = 1
      max_size     = 9
      desired_size = 3

      force_update_version = true
      instance_types       = ["m5.xlarge"]

      ebs_optimized = true
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 100
            volume_type = "gp3"
          }
        }
      }

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
      }

      tags = {
        Name = "core-node-grp"
      }
    }
  }
}

output "flink_job_execution_role_arn" {
  value       = module.flink_irsa_jobs.iam_role_arn
}

output "flink_operator_role_arn" {
  value       = module.flink_irsa_operator.iam_role_arn
}

output "flink_operator_bucket" {
  value       = module.s3_bucket.s3_bucket_id
}

output "configure_kubectl" {
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

provider "aws" {
  region = local.region
}

provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
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

provider "kubectl" {
  apply_retry_count      = 30
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.this.token
}

variable "region" {
  type        = string
  default     = "us-west-2"
}

variable "name" {
  default     = "emr-eks-flink"
  type        = string
}

variable "eks_cluster_version" {
  type        = string
  default     = "1.33"
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
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
  }
}

module "vpc" {
  source  = "github.com/terraform-aws-modules/terraform-aws-vpc?ref=345a1e2"
  name                 = local.name
  cidr                 = "10.0.0.0/16"
  azs                  = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_flow_log                      = true
  flow_log_destination_type            = "cloud-watch-logs"
  flow_log_traffic_type                = "REJECT"
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = 1
  }
  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = 1
  }
}