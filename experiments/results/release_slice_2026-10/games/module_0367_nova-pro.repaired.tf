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

module "eks_blueprints_addons" {
  source  = "github.com/aws-ia/eks-blueprints-addons/aws?ref=v1.0.0"
  version = "~> 1.0"

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

  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    namespace     = "monitoring"
    name          = "prometheus"
    chart_version = "48.1.1"
    set_sensitive = [
      {
        name  = "grafana.adminPassword"
        value = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
      }
    ]

    values = [
      templatefile("${path.module}/monitoring/kube-stack-config.yaml", {
        storage_class_type = kubernetes_storage_class.ebs_csi_encrypted_gp3_storage_class.id,
      })
    ]
  }
  tags = local.tags
}

module "eks_data_addons" {
  source  = "github.com/aws-ia/eks-data-addons/aws?ref=v1.2.0"
  version = "~> 1.2.0"

  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_cnpg_operator = true
  cnpg_operator_helm_config = {
    namespace   = "cnpg-system"
    description = "CloudNativePG Operator Helm chart deployment configuration"
    set = [
      {
        name  = "resources.limits.memory"
        value = "200Mi"
      },
      {
        name  = "resources.limits.cpu"
        value = "100m"
      },
      {
        name  = "resources.requests.cpu"
        value = "100m"
      },
      {
        name  = "resources.memory.memory"
        value = "100Mi"
      }
    ]
  }
}

resource "kubectl_manifest" "cnpg_prometheus_rule" {
  yaml_body = file("${path.module}/monitoring/cnpg-prometheusrule.yaml")

  depends_on = [
    module.eks_blueprints_addons.kube_prometheus_stack
  ]
}

resource "kubectl_manifest" "cnpg_grafana_cm" {
  yaml_body = file("${path.module}/monitoring/grafana-configmap.yaml")

  depends_on = [
    module.eks_blueprints_addons.kube_prometheus_stack
  ]
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }

  names = [
    "us-west-2a",
    "us-west-2b",
    "us-west-2c"
  ]
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "irsa_backup_policy" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = [
      "arn:aws:ec2:*:*:volume/*",
      "arn:aws:ec2:*:*:snapshot/*"
    ]

    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
    ]
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = [
      "arn:aws:s3:::${module.barman_s3_bucket.s3_bucket_id}/*",
      "arn:aws:s3:::${module.barman_s3_bucket.s3_bucket_id}"
    ]

    actions = [
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
      "s3:ListBucket"
    ]
  }
}

locals {
  name   = var.name
  region = var.region

  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}

module "eks" {
  source  = "github.com/terraform-aws-modules/terraform-aws-eks/aws?ref=v19.15.0"
  version = "~> 19.15"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  manage_aws_auth_configmap = true

  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
    ingress_nodes_postgresql = {
      description                = "Cluster to nodes PostgreSQL"
      protocol                   = "tcp"
      from_port                  = 5432
      to_port                    = 5432
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
    ingress_postgresql = {
      description = "PostgreSQL port for CNPG cluster communication"
      protocol    = "tcp"
      from_port   = 5432
      to_port     = 5432
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }
  eks_managed_node_groups = {
    doeks_node_group = {
      name        = "doeks-node-group"
      description = "EKS managed node group example launch template"

      ami_type = "AL2023_ARM_64_STANDARD"

      subnet_ids = module.vpc.private_subnets

      min_size     = 1
      max_size     = 9
      desired_size = 4

      force_update_version = true
      instance_types       = ["m8g.xlarge"]

      vpc_security_group_ids = [module.eks.cluster_primary_security_group_id]

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
        NodeGroupType = "doeks"
      }

      tags = {
        Name = "doeks-node-grp"
      }
    }
  }
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "barman_backup_irsa" {
  description = "ARN for Backup IAM ROLE"
  value       = module.barman_backup_irsa.irsa_iam_role_arn
}

output "barman_s3_bucket" {
  description = "Backup bucket"
  value       = module.barman_s3_bucket.s3_bucket_id
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

provider "kubectl" {
  apply_retry_count      = 30
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.this.token
}

resource "random_string" "random" {
  length  = 4
  special = false
  upper   = false
}

module "ebs_csi_driver_irsa" {
  source                = "github.com/terraform-aws-modules/terraform-aws-iam/aws//modules/iam-role-for-service-accounts-eks?ref=v5.14.0"
  version               = "~> 5.14"
  role_name             = format("%s-%s", local.name, "ebs-csi-driver")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}

module "barman_s3_bucket" {
  source  = "github.com/terraform-aws-modules/terraform-aws-s3-bucket/aws?ref=v3.8.0"
  version = "~> 3.8"

  bucket = "${random_string.random.result}-cnpg-barman-bucket"
  acl    = "private"

  force_destroy = true

  attach_policy                         = true
  attach_deny_insecure_transport_policy = true

  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"
  expected_bucket_owner    = data.aws_caller_identity.current.account_id

  versioning = {
    status     = true
    mfa_delete = false
  }
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  logging = {
    target_bucket = module.barman_s3_bucket.s3_bucket_id
    target_prefix = "logs/"
  }

  tags = local.tags
}

module "barman_backup_irsa" {
  source                            = "github.com/aws-ia/terraform-aws-eks-blueprints-addons//modules/irsa?ref=ed27abc"
  eks_cluster_id                    = module.eks.cluster_name
  eks_oidc_provider_arn             = module.eks.oidc_provider_arn
  irsa_iam_policies                 = [aws_iam_policy.irsa_policy.arn]
  kubernetes_namespace              = "demo"
  kubernetes_service_account        = "prod"
  create_kubernetes_service_account = false
  create_kubernetes_namespace       = false
}

resource "aws_iam_policy" "irsa_policy" {
  description = "IAM role policy for CloudNativePG Barman Tool"
  name        = "${local.name}-barman-irsa"
  policy      = data.aws_iam_policy_document.irsa_backup_policy.json
}

data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id  = aws_secretsmanager_secret.grafana.id
  depends_on = [aws_secretsmanager_secret_version.grafana]
}

resource "random_password" "grafana" {
  length           = 16
  special          = true
  override_special = "@_"
}

resource "aws_secretsmanager_secret" "grafana" {
  name                    = "${local.name}-grafana"
  recovery_window_in_days = 0
  kms_key_id              = "alias/aws/secretsmanager"

  rotation_configuration {
    automatically_after_days = 90
  }
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}

variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "cnpg"
  type        = string
}

variable "region" {
  description = "Region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.32"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  default     = "10.1.0.0/16"
  type        = string
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
      version = ">> 2.17"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.4.3"
    }
  }
}

module "vpc" {
  source  = "github.com/terraform-aws-modules/terraform-aws-vpc/aws?ref=v5.0.0"
  version = "~> 5.0"

  name = local.name
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 10)]

  enable_nat_gateway = true
  single_nat_gateway = true

  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = 1
  }

  tags = local.tags
}