#------------------------------------------------------------------------
# EKS Addons
#------------------------------------------------------------------------
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws?ref=v1.2.0"
  version = "1.2.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
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

  enable_metrics_server     = true
  enable_cluster_autoscaler = true

  tags = local.tags
}

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks?ref=v5.20.0"
  version               = "5.20.0"
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

module "eks" {
  source  = "terraform-aws-modules/eks/aws?ref=v19.15.0"
  version = "19.15.0"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  cluster_endpoint_public_access = false

  cluster_logging_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  manage_aws_auth_configmap = true
  aws_auth_roles = [
    {
      rolearn  = module.mwaa.mwaa_role_arn
      username = "mwaa-service"
      groups   = ["system:masters"]
    },
    {
      # Required for EMR on EKS virtual cluster
      rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AWSServiceRoleForAmazonEMRContainers"
      username = "emr-containers"
      groups   = []
    }
  ]

  #---------------------------------------
  # Note: This can further restricted to specific required for each Add-on and your application
  #---------------------------------------
  # Extend cluster security group rules
  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }

    # MWAA needs access to the EKS control plane in order to submit a job
    allow_access_from_mwaa = {
      description              = "Access from MWAA"
      protocol                 = "tcp"
      from_port                = 443
      to_port                  = 443
      type                     = "ingress"
      source_security_group_id = module.mwaa.mwaa_security_group_id
    }
  }

  # Extend node-to-node security group rules
  node_security_group_additional_rules = {
    # Extend node-to-node security group rules. Recommended and required for the Add-ons
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }

  }

  eks_managed_node_groups = {
    #  We recommend to have a MNG to place your critical workloads and add-ons
    #  Then rely on Karpenter to scale your workloads
    #  You can also make uses on nodeSelector and Taints/tolerations to spread workloads on MNG or Karpenter provisioners
    core_node_group = {
      name       = "core-node-group"
      subnet_ids = module.vpc.private_subnets

      max_size     = 9
      min_size     = 3
      desired_size = 3

      force_update_version = true
      instance_types       = ["m5.xlarge"]
      ami_type             = "AL2_x86_64"
      capacity_type        = "ON_DEMAND"

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
        Environment   = "preprod"
        Zone          = "test"
      }

      tags = {
        Name                                                             = "core-node-grp"
        subnet_type                                                      = "private"
        "k8s.io/cluster-autoscaler/node-template/label/arch"             = "x86"
        "k8s.io/cluster-autoscaler/node-template/label/kubernetes.io/os" = "linux"
        "k8s.io/cluster-autoscaler/node-template/label/noderole"         = "core"
        "k8s.io/cluster-autoscaler/node-template/label/node-lifecycle"   = "on-demand"
        "k8s.io/cluster-autoscaler/experiments"                          = "owned"
        "k8s.io/cluster-autoscaler/enabled"                              = "true"
      }
    }
  }

  tags = local.tags
}

#----------------------------------------------------------------------------
# EMR on EKS
#----------------------------------------------------------------------------
module "emr_containers" {
  source  = "terraform-aws-modules/emr/aws//modules/virtual-cluster?ref=v1.0.0"
  version = "1.0.0"

  eks_cluster_id    = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn

  name                         = format("%s-%s", module.eks.cluster_name, "emr-mwaa-team")
  namespace                    = "emr-mwaa"
  iam_role_description         = "EMR execution role emr-eks-mwaa-team"
  iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"]

  tags = merge(local.tags, { Name = "emr-mwaa" })
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

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "mwaa_emrjob" {
  statement {
    actions = [
      "emr-containers:StartJobRun",
      "emr-containers:ListJobRuns",
      "emr-containers:DescribeJobRun",
      "emr-containers:CancelJobRun"
    ]
    resources = ["*"]
    effect    = "Allow"
  }

  statement {
    actions = [
      "iam:PassRole"
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
    ]
    effect = "Allow"
  }
}

locals {
  name   = var.name
  region = var.region

  vpc_cidr      = var.vpc_cidr
  azs           = slice(data.aws_availability_zones.available.names, 0, 3)
  dag_s3_path   = "dags"
  vpc_endpoints = ["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "elasticloadbalancing", "sts", "kms", "logs", "ssm", "ssmmessages"]

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}

#------------------------------------------------------------------------
# AWS MWAA Module
#------------------------------------------------------------------------

module "mwaa" {
  source  = "aws-ia/mwaa/aws?ref=v0.0.4"
  version = "0.0.4"

  depends_on = [aws_s3_object.uploads, module.vpc_endpoints]

  name                  = local.name
  airflow_version       = "2.5.1"
  environment_class     = "mw1.medium"  # mw1.small / mw1.medium / mw1.large
  webserver_access_mode = "PRIVATE_ONLY" # Default PRIVATE_ONLY for production environments

  create_s3_bucket  = false
  source_bucket_arn = module.s3_bucket.s3_bucket_arn

  dag_s3_path          = local.dag_s3_path
  requirements_s3_path = "${local.dag_s3_path}/requirements.txt"

  min_workers = 1
  max_workers = 25

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = slice(module.vpc.private_subnets, 0, 2) # Required 2 subnets only
  source_cidr        = [module.vpc.vpc_cidr_block]             # Add your IP here to access Airflow UI

  airflow_configuration_options = {
    "core.load_default_connections" = "false"
    "core.load_examples"            = "false"
    "webserver.dag_default_view"    = "tree"
    "webserver.dag_orientation"     = "TB"
    "logging.logging_level"         = "INFO"
  }

  logging_configuration = {
    dag_processing_logs = {
      enabled   = true
      log_level = "INFO"
    }

    scheduler_logs = {
      enabled   = true
      log_level = "INFO"
    }

    task_logs = {
      enabled   = true
      log_level = "INFO"
    }

    webserver_logs = {
      enabled   = true
      log_level = "INFO"
    }

    worker_logs = {
      enabled   = true
      log_level = "INFO"
    }
  }

  tags = local.tags
}

#------------------------------------------------------------------------
# Additional IAM policies for MWAA execution role to run emr on eks job
#------------------------------------------------------------------------
resource "aws_iam_policy" "this" {
  name        = format("%s-%s", local.name, "mwaa-emr-job")
  description = "IAM policy for MWAA RUN EMR on EKS Job execution"
  path        = "/"
  policy      = data.aws_iam_policy_document.mwaa_emrjob.json
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = module.mwaa.mwaa_role_name
  policy_arn = aws_iam_policy.this.arn
}

#------------------------------------------------------------------------
# Dags and Requirements
#------------------------------------------------------------------------

#tfsec:ignore:*
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws?ref=v3.14.0"
  version = "3.14.0"

  bucket = "mwaa-${random_id.this.hex}"

  # For example only - please evaluate for your environment
  force_destroy = true

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

# Kubeconfig is required for KubernetesPodOperator
# https://airflow.apache.org/docs/apache-airflow-providers-cncf-kubernetes/stable/operators.html
locals {
  kubeconfig = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "mwaa"
    clusters = [{
      name = module.eks.cluster_arn
      cluster = {
        certificate-authority-data = module.eks.cluster_certificate_authority_data
        server                     = module.eks.cluster_endpoint
      }
    }]
    contexts = [{
      name = "mwaa" # must match KubernetesPodOperator context
      context = {
        cluster = module.eks.cluster_arn
        user    = "mwaa"
      }
    }]
    users = [{
      name = "mwaa"
      user = {
        exec = {
          apiVersion = "client.authentication.k8s.io/v1beta1"
          command    = "aws"
          args = [
            "--region",
            local.region,
            "eks",
            "get-token",
            "--cluster-name",
            local.name
          ]
        }
      }
    }]
  })
}

resource "aws_s3_object" "kube_config" {
  bucket  = module.s3_bucket.s3_bucket_id
  key     = "${local.dag_s3_path}/kube_config.yaml"
  content = local.kubeconfig
  etag    = md5(local.kubeconfig)
}

resource "aws_s3_object" "uploads" {
  for_each = fileset("${local.dag_s3_path}/", "*")

  bucket = module.s3_bucket.s3_bucket_id
  key    = "${local.dag_s3_path}/${each.value}"
  source = "${local.dag_s3_path}/${each.value}"
  etag   = filemd5("${local.dag_s3_path}/${each.value}")
}

resource "random_id" "this" {
  byte_length = "2"
}

#------------------------------------------------------------------------
# Create K8s Namespace and Role for mwaa access directly
#------------------------------------------------------------------------
resource "kubernetes_namespace_v1" "mwaa" {
  metadata {
    annotations = {
      name = "mwaa"
    }

    name = "mwaa"
  }
}

resource "kubernetes_role_v1" "mwaa" {
  metadata {
    name      = "mwaa-role"
    namespace = kubernetes_namespace_v1.mwaa.metadata[0].name
  }

  rule {
    api_groups = [
      "",
      "apps",
      "batch",
      "extensions",
    ]
    resources = [
      "jobs",
      "pods",
      "pods/attach",
      "pods/exec",
      "pods/log",
      "pods/portforward",
      "secrets",
      "services",
    ]
    verbs = [
      "create",
      "delete",
      "describe",
      "get",
      "list",
      "patch",
      "update",
    ]
  }
}

resource "kubernetes_role_binding_v1" "mwaa" {
  metadata {
    name      = "mwaa-role-binding"
    namespace = kubernetes_namespace_v1.mwaa.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_namespace_v1.mwaa.metadata[0].name
  }

  subject {
    kind      = "User"
    name      = "mwaa-service"
    api_group = "rbac.authorization.k8s.io"
  }
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "emr_on_eks" {
  description = "EMR on EKS"
  value       = module.emr_containers
}

output "mwaa_webserver_url" {
  description = "MWAA Webserver Url"
  value       = module.mwaa.mwaa_webserver_url
}

variable "name" {
  description = "Name of the VPC and EKS Cluster"
  type        = string
  default     = "managed-airflow-mwaa"
}

variable "region" {
  description = "Region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  type        = string
  default     = "1.26"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
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
      version = ">= 3.0"
    }
  }

  # ##  Used for end-to-end testing on project; update to suit your needs
  # backend "s3" {
  #   bucket = "doeks-github-actions-e2e-test-state"
  #   region = "us-west-2"
  #   key    = "e2e/managed-airflow-mwaa/terraform.tfstate"
  # }
}

#---------------------------------------------------------------
# Supporting Resources
#---------------------------------------------------------------
# WARNING: This VPC module includes the creation of an Internet Gateway and NAT Gateway, which simplifies cluster deployment and testing, primarily intended for sandbox accounts.
# IMPORTANT: For preprod and prod use cases, it is crucial to consult with your security team and AWS architects to design a private infrastructure solution that aligns with your security requirements

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws?ref=v5.0.0"
  version = "5.0.0"

  name = local.name
  cidr = local.vpc_cidr
  azs  = local.azs

  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  # Manage so we can name
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

resource "aws_security_group" "vpc_endpoints_sg" {
  name        = "${local.name}-vpc-endpoints"
  description = "Security group for VPC endpoint access"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "VPC CIDR HTTPS"
    cidr_blocks = [module.vpc.vpc_cidr_block]
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
  }

  egress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    cidr_blocks     = [module.vpc.vpc_cidr_block]
    description     = "Egress to VPC CIDR for HTTPS"
  }

  tags = merge(local.tags, {
    "Name" = "${local.name}-vpc-endpoints"
  })
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints?ref=v5.0.0"
  version = "5.0.0"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [aws_security_group.vpc_endpoints_sg.id]

  endpoints = merge({
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags = {
        Name = "${local.name}-s3"
      }
    }
    },
    { for service in toset(local.vpc_endpoints) :
      replace(service, ".", "_") =>
      {
        service             = service
        subnet_ids          = module.vpc.private_subnets
        private_dns_enabled = true
        tags                = { Name = "${local.name}-${service}" }
      }
  })

  tags = local.tags
}