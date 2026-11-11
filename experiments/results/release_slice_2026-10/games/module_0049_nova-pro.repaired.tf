resource "aws_eip" "nat1" {
  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip" "nat2" {
  depends_on = [aws_internet_gateway.main]
}

resource "aws_iam_role" "nodes_general" {
  name = "eks-node-group-general"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "amazon_eks_worker_node_policy_general" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role = aws_iam_role.nodes_general.name
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cni_policy_general" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role = aws_iam_role.nodes_general.name
}

resource "aws_iam_role_policy_attachment" "amazon_ec2_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role = aws_iam_role.nodes_general.name
}

resource "aws_eks_node_group" "nodes_general" {
  cluster_name = aws_eks_cluster.eks.name
  node_group_name = "nodes-general"
  node_role_arn = aws_iam_role.nodes_general.arn
  subnet_ids = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id
  ]
  scaling_config {
    desired_size = 1
    max_size = 1
    min_size = 1
  }
  ami_type = "AL2_x86_64"
  capacity_type = "ON_DEMAND"
  disk_size = 20
  force_update_version = false
  instance_types = ["t3.small"]
  labels = {
    role = "nodes-general"
  }
  version = "1.18"
  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_worker_node_policy_general,
    aws_iam_role_policy_attachment.amazon_eks_cni_policy_general,
    aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only,
  ]
}

resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster"
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

resource "aws_iam_role_policy_attachment" "amazon_eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role = aws_iam_role.eks_cluster.name
}

resource "aws_eks_cluster" "eks" {
  name = "eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version = "1.18"
  encryption_config {
    resources = ["secrets"]
  }
  logging {
    cluster_logging {
      enabled_types = [
        {
          type = "api"
        },
        {
          type = "audit"
        },
        {
          type = "authenticator"
        },
        {
          type = "controllerManager"
        },
        {
          type = "scheduler"
        }
      ]
    }
  }
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access = false
    subnet_ids = [
      aws_subnet.public_1.id,
      aws_subnet.public_2.id,
      aws_subnet.private_1.id,
      aws_subnet.private_2.id
    ]
  }
  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_cluster_policy
  ]
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main"
  }
}

resource "aws_nat_gateway" "gw1" {
  allocation_id = aws_eip.nat1.id
  subnet_id = aws_subnet.public_1.id
  tags = {
    Name = "NAT 1"
  }
}

resource "aws_nat_gateway" "gw2" {
  allocation_id = aws_eip.nat2.id
  subnet_id = aws_subnet.public_2.id
  tags = {
    Name = "NAT 2"
  }
}

provider "aws" {
  profile = "terraform"
  region  = "us-east-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.21"
    }
  }
}

resource "aws_route_table_association" "public1" {
  subnet_id = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public2" {
  subnet_id = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private1" {
  subnet_id = aws_subnet.private_1.id
  route_table_id = aws_route_table.private1.id
}

resource "aws_route_table_association" "private2" {
  subnet_id = aws_subnet.private_2.id
  route_table_id = aws_route_table.private2.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "public"
  }
}

resource "aws_route_table" "private1" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.gw1.id
  }
  tags = {
    Name = "private1"
  }
}

resource "aws_route_table" "private2" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.gw2.id
  }
  tags = {
    Name = "private2"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id = aws_vpc.main.id
  cidr_block = "192.168.0.0/18"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = false
  tags = {
    Name                        = "public-us-east-1a"
    "kubernetes.io/cluster/eks" = "shared"
    "kubernetes.io/role/elb"    = 1
  }
}

resource "aws_subnet" "public_2" {
  vpc_id = aws_vpc.main.id
  cidr_block = "192.168.64.0/18"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = false
  tags = {
    Name                        = "public-us-east-1b"
    "kubernetes.io/cluster/eks" = "shared"
    "kubernetes.io/role/elb"    = 1
  }
}

resource "aws_subnet" "private_1" {
  vpc_id = aws_vpc.main.id
  cidr_block = "192.168.128.0/18"
  availability_zone = "us-east-1a"
  tags = {
    Name                              = "private-us-east-1a"
    "kubernetes.io/cluster/eks"       = "shared"
    "kubernetes.io/role/internal-elb" = 1
  }
}

resource "aws_subnet" "private_2" {
  vpc_id = aws_vpc.main.id
  cidr_block = "192.168.192.0/18"
  availability_zone = "us-east-1b"
  tags = {
    Name                              = "private-us-east-1b"
    "kubernetes.io/cluster/eks"       = "shared"
    "kubernetes.io/role/internal-elb" = 1
  }
}

resource "aws_vpc" "main" {
  cidr_block = "192.168.0.0/16"
  instance_tenancy = "default"
  enable_dns_support = true
  enable_dns_hostnames = true
  enable_classiclink = false
  enable_classiclink_dns_support = false
  assign_generated_ipv6_cidr_block = false
  tags = {
    Name = "main"
  }
  enable_flow_logs = true
}

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "VPC id."
  sensitive = false
}