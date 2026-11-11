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

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

data "aws_availability_zones" "available" {
  all_availability_zones = false

  # Do not include local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

locals {
  name   = basename(path.cwd)
  region = "us-west-2"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  namespace                = "external-secrets"
  cluster_secretstore_name = "cluster-secretstore-sm"
  cluster_secretstore_sa   = "cluster-secretstore-sa"
  secretstore_name         = "secretstore-ps"
  secretstore_sa           = "secretstore-sa"

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

################################################################################
# Cluster
################################################################################

module "eks" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=4660a0e2d02ff6a19b3cfb2b20cf9d6f7c0b3a5a"

  cluster_name                   = local.name
  cluster_version                = "1.30"
  cluster_endpoint_public_access = false

  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # Give the Terraform identity admin access to the cluster
  # which will allow resources to be deployed into the cluster
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  node_security_group_additional_rules = {
    egress_all = {
      description = "Node all egress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = [local.vpc_cidr]
    }
  }

  eks_managed_node_groups = {
    initial = {
      instance_types = ["m5.large"]

      min_size     = 1
      max_size     = 5
      desired_size = 2
    }
  }

  tags = local.tags
}

################################################################################
# EKS Blueprints Addons
################################################################################

module "eks_blueprints_addons" {
  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addons.git?ref=a1b2c3d4e5f60718293a4b5c6d7e8f9012a3b4c"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # EKS Add-ons
  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns    = {}
    vpc-cni    = {}
    kube-proxy = {}
  }

  # Add-ons
  enable_external_secrets = true

  tags = local.tags
}

#---------------------------------------------------------------
# Supporting Resources
#---------------------------------------------------------------

module "vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=9f8e7d6c5b4a392817263544536271809f8e7d6"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group             = true
  create_flow_log_cloudwatch_iam_role              = true
  flow_log_traffic_type                            = "REJECT"
  flow_log_destination_type                        = "cloud-watch-logs"
  flow_log_cloudwatch_log_group_retention_in_days   = 30

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

resource "aws_kms_key" "secrets" {
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountAccess"
        Effect    = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "kubectl_manifest" "cluster_secretstore" {
  yaml_body = <<YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ClusterSecretStore
    metadata:
      name: ${local.cluster_secretstore_name}
    spec:
      provider:
        aws:
          service: SecretsManager
          region: ${local.region}
          auth:
            jwt:
              serviceAccountRef:
                name: ${local.cluster_secretstore_sa}
                namespace: ${local.namespace}
  YAML

  depends_on = [module.eks_blueprints_addons]
}

resource "aws_secretsmanager_secret" "secret" {
  recovery_window_in_days = 0
  kms_key_id              = aws_kms_key.secrets.arn
}

resource "aws_secretsmanager_secret_rotation" "secret" {
  secret_id           = aws_secretsmanager_secret.secret.id
  rotation_lambda_arn = aws_kms_key.secrets.arn

  rotation_rules {
    automatically_after_days = 30
  }
}

resource "aws_secretsmanager_secret_version" "secret" {
  secret_id = aws_secretsmanager_secret.secret.id
  secret_string = jsonencode({
    username = "secretuser",
    password = "secretpassword"
  })
}

resource "kubectl_manifest" "secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: ${local.name}-sm
      namespace: ${local.namespace}
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: ${local.cluster_secretstore_name}
        kind: ClusterSecretStore
      dataFrom:
      - extract:
          key: ${aws_secretsmanager_secret.secret.name}
  YAML

  depends_on = [kubectl_manifest.cluster_secretstore]
}

#---------------------------------------------------------------
# External Secrets Operator - Parameter Store
#---------------------------------------------------------------

resource "kubectl_manifest" "secretstore" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: SecretStore
    metadata:
      name: ${local.secretstore_name}
      namespace: ${local.namespace}
    spec:
      provider:
        aws:
          service: ParameterStore
          region: ${local.region}
          auth:
            jwt:
              serviceAccountRef:
                name: ${local.secretstore_sa}
  YAML

  depends_on = [module.eks_blueprints_addons]
}

resource "aws_ssm_parameter" "secret_parameter" {
  name = "/${local.name}/secret"
  type = "SecureString"
  value = jsonencode({
    username = "secretuser",
    password = "secretpassword"
  })
  key_id = aws_kms_key.secrets.arn
}


resource "kubectl_manifest" "secret_parameter" {
  yaml_body  = <<YAML
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ${local.name}-ps
  namespace: ${local.namespace}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: ${local.secretstore_name}
    kind: SecretStore
  dataFrom:
  - extract:
      key: ${aws_ssm_parameter.secret_parameter.name}
YAML
  depends_on = [kubectl_manifest.secretstore]
}

#---------------------------------------------------------------
# IRSA
#---------------------------------------------------------------

module "cluster_secretstore_role" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-role-for-service-accounts-eks?ref=c3d4e5f60718293a4b5c6d7e8f9012a3b4c5d6e"

  role_name_prefix = "${module.eks.cluster_name}-secrets-manager-"

  role_policy_arns = {
    policy = aws_iam_policy.cluster_secretstore.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${local.namespace}:${local.cluster_secretstore_sa}"]
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "cluster_secretstore" {
  name_prefix = local.cluster_secretstore_sa
  policy      = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetResourcePolicy",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecretVersionIds"
      ],
      "Resource": "${aws_secretsmanager_secret.secret.arn}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt"
      ],
      "Resource": "${aws_kms_key.secrets.arn}"
    }
  ]
}
POLICY
}

module "secretstore_role" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-role-for-service-accounts-eks?ref=c3d4e5f60718293a4b5c6d7e8f9012a3b4c5d6e"

  role_name_prefix = "${module.eks.cluster_name}-parameter-store"

  role_policy_arns = {
    policy = aws_iam_policy.secretstore.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${local.namespace}:${local.cluster_secretstore_sa}"]
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "secretstore" {
  name_prefix = local.secretstore_sa
  policy      = <<-POLICY
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "ssm:GetParameter*"
          ],
          "Resource": "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/${local.name}/*"
        },
        {
          "Effect": "Allow",
          "Action": [
            "kms:Decrypt"
          ],
          "Resource": "${aws_kms_key.secrets.arn}"
        }
      ]
    }
  POLICY
}

module "ebs_csi_driver_irsa" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-role-for-service-accounts-eks?ref=c3d4e5f60718293a4b5c6d7e8f9012a3b4c5d6e"

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


output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
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
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
  }

  # ##  Used for end-to-end testing on project; update to suit your needs
  # backend "s3" {
  #   bucket = "terraform-ssp-github-actions-state"
  #   region = "us-west-2"
  #   key    = "e2e/complete-kubernetes-addons/terraform.tfstate"
  # }
}