provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true
  enable_classiclink   = false
  enable_classiclink_dns_support = false

  tags = {
    Name = "main"
  }
}

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.main.id
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name = "vpc-flow-log"

  retention_in_days = 30
}

resource "aws_iam_role" "vpc_flow_log" {
  name        = "vpc-flow-log"
  description = "VPC Flow Log IAM Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "vpc-flow-log.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_policy" "vpc_flow_log" {
  name        = "vpc-flow-log"
  description = "VPC Flow Log IAM Policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = aws_cloudwatch_log_group.vpc_flow_log.arn
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "vpc_flow_log" {
  role       = aws_iam_role.vpc_flow_log.name
  policy_arn = aws_iam_policy.vpc_flow_log.arn
}

terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

provider "kubectl" {
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_blueprints.eks_cluster_id]
  }
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "19.10.0"

  cluster_name           = module.eks_blueprints.eks_cluster_id
  irsa_oidc_provider_arn = module.eks_blueprints.eks_oidc_provider_arn
  create_irsa            = false 
}

resource "kubectl_manifest" "karpenter_provisioner" {
  yaml_body = <<-YAML
---
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
spec:
  ttlSecondsAfterEmpty: 60 
  ttlSecondsUntilExpired: 604800 
  limits:
    resources:
      cpu: 100 
  requirements:
    - key: karpenter.k8s.aws/instance-family
      operator: In
      values: [c5, m5, r5]
    - key: karpenter.k8s.aws/instance-size
      operator: NotIn
      values: [nano, micro, small, large]
  providerRef:
    name: default
YAML

  depends_on = [module.kubernetes_addons]
}

resource "kubectl_manifest" "karpenter_template" {
  yaml_body = <<-YAML
---
apiVersion: karpenter.k8s.aws/v1alpha1
kind: AWSNodeTemplate
metadata:
    name: default
spec:
  subnetSelector:
    "kubernetes.io/cluster/${module.eks_blueprints.eks_cluster_id}": "owned"
  securityGroupSelector:
    "kubernetes.io/cluster/${module.eks_blueprints.eks_cluster_id}": "owned"
  instanceProfile: ${module.karpenter.instance_profile_name}
  tags:
    "kubernetes.io/cluster/${module.eks_blueprints.eks_cluster_id}": "owned"
YAML

  depends_on = [module.kubernetes_addons]
}

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "allow_assume_developer_role" {
  name = "AllowAssumeDeveloperRole"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = aws_iam_role.developer.arn
      }
    ]
  })
}

resource "aws_iam_role" "developer" {
  name = "developer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          AWS = data.aws_caller_identity.current.account_id
        }
        Condition = {
          StringLike = {
            "aws:sourceArn" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "eks_console_access" {
  name = "EKSConsoleAccess"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:*"
        ]
        Resource = "arn:aws:eks:${aws_region.name}:${data.aws_caller_identity.current.account_id}:cluster/*"
      },
      {
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "eks.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "developer_eks_console_access" {
  role       = aws_iam_role.developer.name
  policy_arn = aws_iam_policy.eks_console_access.arn
}

resource "kubectl_manifest" "cluster_role_reader" {
  yaml_body = <<-YAML
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: reader
rules:
- apiGroups: ["*"]
  resources: ["deployments", "configmaps", "pods", "secrets", "services"]
  verbs: ["get", "list", "watch"]
YAML

  depends_on = [aws_iam_role_policy_attachment.developer_eks_console_access]
}

resource "kubectl_manifest" "cluster_role_binding_reader" {
  yaml_body = <<-YAML
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: reader
subjects:
- kind: Group
  name: reader
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: reader
  apiGroup: rbac.authorization.k8s.io
YAML

  depends_on = [aws_iam_role_policy_attachment.developer_eks_console_access]
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "igw"
  }
}

resource "aws_subnet" "private_us_east_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/19"
  availability_zone = "us-east-1a"

  tags = {
    "Name"                            = "private-us-east-1a"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/demo-2"    = "owned"
  }
}

resource "aws_subnet" "private_us_east_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.32.0/19"
  availability_zone = "us-east-1b"

  tags = {
    "Name"                            = "private-us-east-1b"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/demo-2"    = "owned"
  }
}

resource "aws_subnet" "public_us_east_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.64.0/19"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    "Name"                         = "public-us-east-1a"
    "kubernetes.io/role/elb"       = "1"
    "kubernetes.io/cluster/demo-2" = "owned"
  }
}

resource "aws_subnet" "public_us_east_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.96.0/19"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    "Name"                         = "public-us-east-1b"
    "kubernetes.io/role/elb"       = "1"
    "kubernetes.io/cluster/demo-2" = "owned"
  }
}

resource "aws_eip" "nat" {
  vpc = true

  tags = {
    Name = "nat"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_us_east_1a.id

  tags = {
    Name = "nat"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public"
  }
}

resource "aws_route_table_association" "private_us_east_1a" {
  subnet_id      = aws_subnet.private_us_east_1a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_us_east_1b" {
  subnet_id      = aws_subnet.private_us_east_1b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "public_us_east_1a" {
  subnet_id      = aws_subnet.public_us_east_1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_us_east_1b" {
  subnet_id      = aws_subnet.public_us_east_1b.id
  route_table_id = aws_route_table.public.id
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.19.0"

  name = "main-module"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.0.0/19", "10.0.32.0/19"]
  public_subnets  = ["10.0.64.0/19", "10.0.96.0/19"]

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  public_subnet_tags = {
    "kubernetes.io/role/elb"     = 1
    "kubernetes.io/cluster/demo" = "owned"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "kubernetes.io/cluster/demo"      = "owned"
  }

  map_public_ip_on_launch = false
}

module "eks_blueprints" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=5a2ba6e5f4e5c2c2c2c2c2c2c2c2c2c2"

  cluster_name    = "demo"
  cluster_version = "1.25"
  enable_irsa     = true

  map_roles = [
    {
      rolearn  = module.karpenter.role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    },
    {
      rolearn  = aws_iam_role.developer.arn
      username = "developer"
      groups   = ["reader"]
    },
  ]

  fargate_profiles = {
    staging = {
      fargate_profile_name = "staging"
      subnet_ids = module.vpc.private_subnets
      fargate_profile_namespaces = [
        { namespace = "staging" }
      ]
    }
  }

  vpc_id = module.vpc.vpc_id

  private_subnet_ids = module.vpc.private_subnets

  managed_node_groups = {
    role = {
      capacity_type   = "ON_DEMAND"
      node_group_name = "general"
      instance_types  = ["t3a.xlarge"]
      desired_size    = "1"
      max_size        = "5"
      min_size        = "1"
    }
  }

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = false
}

provider "kubernetes" {
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_blueprints.eks_cluster_id]
  }
}

module "kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=5a2ba6e5f4e5c2c2c2c2c2c2c2c2c2c2"

  eks_cluster_id = module.eks_blueprints.eks_cluster_id

  enable_amazon_eks_aws_ebs_csi_driver = true

  enable_aws_efs_csi_driver = true

  enable_aws_load_balancer_controller = true

  enable_metrics_server = true
  enable_cert_manager   = true

  enable_karpenter = true
  karpenter_helm_config = {
    name       = "karpenter"
    chart      = "karpenter"
    repository = "oci://public.ecr.aws/karpenter"
    version    = "v0.27.0"
    namespace  = "karpenter"
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks_blueprints.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_blueprints.eks_cluster_id]
    }
  }
}

resource "aws_efs_file_system" "eks" {
  creation_token = "eks"

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true
  kms_key_id        = aws_kms_key.eks.arn

  tags = {
    Name = "eks"
  }
}

resource "aws_kms_key" "eks" {
  description             = "EKS KMS Key"
  deletion_window_in_days = 10
}

resource "aws_efs_mount_target" "zone" {
  for_each = toset(module.vpc.private_subnets)

  file_system_id  = aws_efs_file_system.eks.id
  subnet_id       = each.key
  security_groups = [module.eks_blueprints.cluster_primary_security_group_id]
}

resource "kubernetes_storage_class_v1" "efs" {
  metadata {
    name = "efs"
  }

  storage_provisioner = "efs.csi.aws.com"

  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = aws_efs_file_system.eks.id
    directoryPerms   = "700"
  }

  mount_options = ["iam"]

  depends_on = [module.kubernetes_addons]
}

resource "aws_security_group_rule" "egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.eks_blueprints.cluster_primary_security_group_id
  description       = "Allow all egress traffic"
}