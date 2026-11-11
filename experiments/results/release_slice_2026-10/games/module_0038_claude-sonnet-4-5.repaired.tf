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
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
  
  filter {
    name   = "zone-id"
    values = ["usw2-az1", "usw2-az2", "usw2-az3"]
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
  source  = "terraform-aws-modules/eks/aws"
  version = "20.11.0"

  cluster_name                   = local.name
  cluster_version                = "1.30"
  cluster_endpoint_public_access = false
  cluster_endpoint_public_access_cidrs = ["10.0.0.0/8"]

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    initial = {
      instance_types = ["m5.large"]

      min_size     = 1
      max_size     = 5
      desired_size = 2
    }
  }

  node_security_group_additional_rules = {
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["10.0.0.0/8"]
    }
  }

  tags = local.tags
}

################################################################################
# EKS Blueprints Addons
################################################################################

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "1.16.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns    = {}
    vpc-cni    = {}
    kube-proxy = {}
  }

  enable_external_secrets = true

  tags = local.tags
}

#---------------------------------------------------------------
# Supporting Resources
#---------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true
  flow_log_traffic_type                = "REJECT"

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
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
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
  rotation_lambda_arn = aws_lambda_function.rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }
}

resource "aws_lambda_function" "rotation" {
  function_name = "${local.name}-secret-rotation"
  role          = aws_iam_role.rotation.arn
  handler       = "index.handler"
  runtime       = "python3.9"
  filename      = "${path.module}/rotation.zip"

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${local.region}.amazonaws.com"
    }
  }
}

resource "aws_iam_role" "rotation" {
  name = "${local.name}-secret-rotation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rotation" {
  role       = aws_iam_role.rotation.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
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
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.20.0"

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
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.20.0"

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
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.20.0"

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
}