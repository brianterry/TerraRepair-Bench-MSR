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
    name   = "state"
    values = ["available"]
  }
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

locals {
  name   = basename(path.cwd)
  region = "us-west-2"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)


  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

module "eks" {
  source  = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=v20.11.1"

  cluster_name                   = local.name
  cluster_version                = "1.30"
  cluster_endpoint_public_access = false
  cluster_endpoint_private_access = true
  enable_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    initial = {
      instance_types = ["m5.large"]

      min_size     = 1
      max_size     = 5
      desired_size = 2

      security_group_egress_rules = {
        https = {
          description = "HTTPS egress"
          protocol    = "tcp"
          from_port   = 443
          to_port     = 443
          cidr_blocks = ["0.0.0.0/0"]
        }
        http = {
          description = "HTTP egress"
          protocol    = "tcp"
          from_port   = 80
          to_port     = 80
          cidr_blocks = ["0.0.0.0/0"]
        }
        dns = {
          description = "DNS egress"
          protocol    = "udp"
          from_port   = 53
          to_port     = 53
          cidr_blocks = ["0.0.0.0/0"]
        }
      }
    }
  }

  tags = local.tags
}

module "eks_blueprints_addons" {
  source  = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addons.git?ref=v1.16.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  eks_addons = {
    coredns    = {}
    vpc-cni    = {}
    kube-proxy = {}
  }

  enable_cert_manager         = true
  enable_aws_privateca_issuer = true
  aws_privateca_issuer = {
    acmca_arn        = aws_acmpca_certificate_authority.this.arn
    namespace        = "aws-privateca-issuer"
    create_namespace = true
  }

  helm_releases = {
    cert-manager-csi-driver = {
      description   = "Cert Manager CSI Driver Add-on"
      chart         = "cert-manager-csi-driver"
      namespace     = "cert-manager"
      chart_version = "v0.5.0"
      repository    = "https://charts.jetstack.io"
    }
  }

  tags = local.tags
}

resource "aws_acmpca_certificate_authority" "this" {
  type = "ROOT"

  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name = var.certificate_dns
    }
  }

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

resource "kubectl_manifest" "cluster_pca_issuer" {
  yaml_body = yamlencode({
    apiVersion = "awspca.cert-manager.io/v1beta1"
    kind       = "AWSPCAClusterIssuer"

    metadata = {
      name = module.eks.cluster_name
    }

    spec = {
      arn = aws_acmpca_certificate_authority.this.arn
      region : local.region
    }
  })

  depends_on = [
    module.eks_blueprints_addons
  ]
}

resource "kubectl_manifest" "pca_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"

    metadata = {
      name      = var.certificate_name
      namespace = "default"
    }

    spec = {
      commonName = var.certificate_dns
      duration   = "2160h0m0s"
      issuerRef = {
        group = "awspca.cert-manager.io"
        kind  = "AWSPCAClusterIssuer"
        name : module.eks.cluster_name
      }
      renewBefore = "360h0m0s"
      secretName  = join("-", [var.certificate_name, "clusterissuer"])
      usages = [
        "server auth",
        "client auth"
      ]
      privateKey = {
        algorithm : "RSA"
        size : 2048
      }
    }
  })

  depends_on = [
    kubectl_manifest.cluster_pca_issuer,
  ]
}

module "vpc" {
  source  = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=v5.0.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_flow_log = true
  flow_log_traffic_type = "REJECT"
  create_flow_log_cloudwatch_log_group = true
  flow_log_destination_type = "cloud-watch-logs"

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

output "configure_kubectl" {
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

variable "certificate_name" {
  type        = string
  default     = "example"
}

variable "certificate_dns" {
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