locals {
  env         = "dev"
  region      = "us-east-2"
  zone1       = "us-east-2a"
  zone2       = "us-east-2b"
  eks_name    = "demo"
  eks_version = "1.31"
}


provider "aws" {
  region = local.region
}

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.16"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
  }
}


data "aws_iam_policy_document" "appmesh_controller" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:appmesh-system:appmesh-controller"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "appmesh_controller" {
  assume_role_policy = data.aws_iam_policy_document.appmesh_controller.json
  name               = "${local.env}-${local.eks_name}-eks-appmesh-controller"
}

resource "aws_iam_role_policy_attachment" "aws_cloud_map_full_access_controller" {
  role       = aws_iam_role.appmesh_controller.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCloudMapFullAccess"
}

resource "aws_iam_role_policy_attachment" "aws_appmesh_full_access_controller" {
  role       = aws_iam_role.appmesh_controller.name
  policy_arn = "arn:aws:iam::aws:policy/AWSAppMeshFullAccess"
}


# Deploy to existing EKS cluster
# provider "helm" {
#   kubernetes {
#     config_path = "~/.kube/config"
#   }
# }

data "aws_eks_cluster" "eks" {
  name = "${local.env}-${local.eks_name}"

  depends_on = [aws_eks_cluster.eks]
}

data "aws_eks_cluster_auth" "eks" {
  name = "${local.env}-${local.eks_name}"

  depends_on = [aws_eks_cluster.eks]
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.eks.token
  }
}

resource "helm_release" "appmesh_controller" {
  name = "appmesh-controller"

  repository       = "https://aws.github.io/eks-charts"
  chart            = "appmesh-controller"
  namespace        = "appmesh-system"
  create_namespace = true
  version          = "1.12.3"

  set {
    name  = "serviceAccount.name"
    value = "appmesh-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.appmesh_controller.arn
  }

  depends_on = [
    aws_eks_node_group.general,
    aws_iam_role_policy_attachment.aws_cloud_map_full_access_controller,
    aws_iam_role_policy_attachment.aws_appmesh_full_access_controller
  ]
}


provider "kubectl" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
  load_config_file       = false
}

resource "kubectl_manifest" "mesh" {
  yaml_body = file("../k8s/mesh.yaml")

  depends_on = [helm_release.appmesh_controller]
}


data "aws_iam_policy_document" "service_a" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:service-a:service-a"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "service_a" {
  assume_role_policy = data.aws_iam_policy_document.service_a.json
  name               = "${local.env}-${local.eks_name}-eks-service-a"
}

resource "aws_iam_policy" "service_a" {
  policy = file("./proxy-auth.json")
  name   = "AppMeshServiceAAccess"
}

resource "aws_iam_role_policy_attachment" "service_a" {
  role       = aws_iam_role.service_a.name
  policy_arn = aws_iam_policy.service_a.arn
}

output "iam_service_a_arn" {
  value = aws_iam_role.service_a.arn
}


data "aws_iam_policy_document" "service_b" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:service-b:service-b"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "service_b" {
  assume_role_policy = data.aws_iam_policy_document.service_b.json
  name               = "${local.env}-${local.eks_name}-eks-service-b"
}

resource "aws_iam_policy" "service_b" {
  policy = file("./proxy-auth.json")
  name   = "AppMeshServiceBAccess"
}

resource "aws_iam_role_policy_attachment" "service_b" {
  role       = aws_iam_role.service_b.name
  policy_arn = aws_iam_policy.service_b.arn
}

output "iam_service_b_arn" {
  value = aws_iam_role.service_b.arn
}


data "aws_iam_policy_document" "appmesh_gateway" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:gateway:appmesh-gateway"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "appmesh_gateway" {
  assume_role_policy = data.aws_iam_policy_document.appmesh_gateway.json
  name               = "${local.env}-${local.eks_name}-eks-appmesh-gateway"
}

resource "aws_iam_role_policy_attachment" "aws_cloud_map_full_access_gateway" {
  role       = aws_iam_role.appmesh_gateway.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCloudMapFullAccess"
}

resource "aws_iam_role_policy_attachment" "aws_appmesh_full_access_gateway" {
  role       = aws_iam_role.appmesh_gateway.name
  policy_arn = "arn:aws:iam::aws:policy/AWSAppMeshFullAccess"
}


resource "kubectl_manifest" "gateway_ns" {
  yaml_body = file("../k8s/gateway-ns.yaml")

  depends_on = [kubectl_manifest.mesh]
}


resource "helm_release" "appmesh_gateway" {
  name = "appmesh-gateway"

  repository       = "https://aws.github.io/eks-charts"
  chart            = "appmesh-gateway"
  namespace        = "gateway"
  create_namespace = false
  version          = "0.1.5"

  set {
    name  = "serviceAccount.name"
    value = "appmesh-gateway"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.appmesh_gateway.arn
  }

  set {
    name  = "service.port"
    value = 80
  }

  depends_on = [
    kubectl_manifest.mesh,
    kubectl_manifest.gateway_ns,
    helm_release.appmesh_controller,
    aws_iam_role_policy_attachment.aws_cloud_map_full_access_gateway,
    aws_iam_role_policy_attachment.aws_appmesh_full_access_gateway
  ]
}


resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.env}-main"
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name              = "/aws/vpc/${local.env}-main"
  retention_in_days = 365
}

resource "aws_iam_role" "vpc_flow_log" {
  name = "${local.env}-vpc-flow-log"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy" "vpc_flow_log" {
  name = "${local.env}-vpc-flow-log"
  role = aws_iam_role.vpc_flow_log.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.main.id
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.env}-igw"
  }
}


resource "aws_subnet" "private_zone1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/19"
  availability_zone = local.zone1

  tags = {
    "Name"                                                 = "${local.env}-private-${local.zone1}"
    "kubernetes.io/role/internal-elb"                      = "1"
    "kubernetes.io/cluster/${local.env}-${local.eks_name}" = "owned"
  }
}

resource "aws_subnet" "private_zone2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.32.0/19"
  availability_zone = local.zone2

  tags = {
    "Name"                                                 = "${local.env}-private-${local.zone2}"
    "kubernetes.io/role/internal-elb"                      = "1"
    "kubernetes.io/cluster/${local.env}-${local.eks_name}" = "owned"
  }
}

resource "aws_subnet" "public_zone1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.64.0/19"
  availability_zone       = local.zone1
  map_public_ip_on_launch = false

  tags = {
    "Name"                                                 = "${local.env}-public-${local.zone1}"
    "kubernetes.io/role/elb"                               = "1"
    "kubernetes.io/cluster/${local.env}-${local.eks_name}" = "owned"
  }
}

resource "aws_subnet" "public_zone2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.96.0/19"
  availability_zone       = local.zone2
  map_public_ip_on_launch = false

  tags = {
    "Name"                                                 = "${local.env}-public-${local.zone2}"
    "kubernetes.io/role/elb"                               = "1"
    "kubernetes.io/cluster/${local.env}-${local.eks_name}" = "owned"
  }
}


resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.env}-nat"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_zone1.id

  tags = {
    Name = "${local.env}-nat"
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
    Name = "${local.env}-private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${local.env}-public"
  }
}

resource "aws_route_table_association" "private_zone1" {
  subnet_id      = aws_subnet.private_zone1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_zone2" {
  subnet_id      = aws_subnet.private_zone2.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "public_zone1" {
  subnet_id      = aws_subnet.public_zone1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_zone2" {
  subnet_id      = aws_subnet.public_zone2.id
  route_table_id = aws_route_table.public.id
}


resource "aws_iam_role" "eks" {
  name = "${local.env}-${local.eks_name}-eks-cluster"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "eks" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks.name
}

resource "aws_kms_key" "eks" {
  description             = "EKS cluster secrets encryption key"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_iam_role_policy" "eks_kms" {
  name = "${local.env}-${local.eks_name}-eks-kms"
  role = aws_iam_role.eks.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ListGrants",
        "kms:DescribeKey",
        "kms:CreateGrant"
      ],
      "Resource": "${aws_kms_key.eks.arn}"
    }
  ]
}
POLICY
}

resource "aws_eks_cluster" "eks" {
  name     = "${local.env}-${local.eks_name}"
  version  = local.eks_version
  role_arn = aws_iam_role.eks.arn

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = false

    subnet_ids = [
      aws_subnet.private_zone1.id,
      aws_subnet.private_zone2.id
    ]
  }

  encryption_config {
    resources = ["secrets"]

    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks,
    aws_iam_role_policy.eks_kms
  ]
}


resource "aws_iam_role" "nodes" {
  name = "${local.env}-${local.eks_name}-eks-nodes"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      }
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "amazon_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.nodes.name
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.nodes.name
}

resource "aws_iam_role_policy_attachment" "amazon_ec2_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.nodes.name
}

resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.eks.name
  version         = local.eks_version
  node_group_name = "general"
  node_role_arn   = aws_iam_role.nodes.arn

  subnet_ids = [
    aws_subnet.private_zone1.id,
    aws_subnet.private_zone2.id
  ]

  # You probably want ON_DEMAND
  capacity_type  = "SPOT"
  instance_types = ["t3.small"]

  scaling_config {
    desired_size = 1
    max_size     = 5
    min_size     = 0
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "general"
  }

  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.amazon_eks_cni_policy,
    aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only,
  ]

  # Allow external changes without Terraform plan difference
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}


data "tls_certificate" "eks" {
  url = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}