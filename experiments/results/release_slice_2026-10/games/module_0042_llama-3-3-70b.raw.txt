locals {
  client_name = "${local.name}-client"
}

################################################################################
# VPC
################################################################################

module "client_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.client_name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k + 10)]

  enable_nat_gateway = true
  single_nat_gateway = true

  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.client_name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.client_name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.client_name}-default" }
  enable_flow_log               = true
  flow_log_destination_type     = "cloud-watch-logs"
  flow_log_traffic_type         = "REJECT"

  tags = merge(local.tags, {
    Name = local.client_name
  })
}

################################################################################
# EC2 Instance
################################################################################

module "client_ec2_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name = local.client_name

  create_iam_instance_profile = true
  iam_role_policies = {
    EKSFullAccess                = aws_iam_policy.eks_full_access_policy.arn
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  vpc_security_group_ids = [module.client_security_group.security_group_id]
  subnet_id              = element(module.client_vpc.private_subnets, 0)

  user_data = <<-EOT
    #!/bin/bash

    # Install kubectl
    curl -LO https://dl.k8s.io/release/v${module.eks.cluster_version}.0/bin/linux/amd64/kubectl
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

    # Remove default awscli which is v1 - we want latest v2
    yum remove awscli -y
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -qq awscliv2.zip
    ./aws/install
  EOT

  root_block_device {
    volume_size = 30
    encrypted   = true
  }

  tags = merge(local.tags, {
    Name = local.client_name
  })
}

resource "aws_iam_policy" "eks_full_access_policy" {
  name        = "EKSFullAccess"
  path        = "/"
  description = "EKS full-access policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Effect   = "Allow"
        Resource = module.eks.cluster_arn
      },
    ]
  })
}

module "client_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = local.client_name
  description = "Security group for SSM access to private cluster"
  vpc_id      = module.client_vpc.vpc_id

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = module.client_vpc.vpc_cidr_block
    },
  ]

  tags = merge(local.tags, {
    Name = local.client_name
  })
}


################################################################################
# EKS Cluster
################################################################################

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.11"

  cluster_name    = local.name
  cluster_version = "1.30"

  cluster_endpoint_public_access           = false
  enable_cluster_creator_admin_permissions = true

  access_entries = {
    ec2-access-entry = {
      principal_arn = module.client_ec2_instance.iam_role_arn
      policy_associations = {
        cluster-admin-policy = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            namespaces = []
            type       = "cluster"
          }
        }
      }
    }
  }

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  cluster_security_group_additional_rules = {
    # Allow tcp/443 from the NLB IP addresses
    for ip_addr in data.dns_a_record_set.nlb.addrs : "nlb_ingress_${replace(ip_addr, ".", "")}" => {
      description = "Allow ingress from NLB"
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["${ip_addr}/32"]
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      instance_types = ["c5.large"]

      min_size     = 1
      max_size     = 3
      desired_size = 1
    }
  }

  enable_control_plane_logging = true
  control_plane_logging_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = local.tags
}

################################################################################
# VPC
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]

  # Disable NAT gateway for fully private networking
  enable_nat_gateway = false

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  enable_flow_log               = true
  flow_log_destination_type     = "cloud-watch-logs"
  flow_log_traffic_type         = "REJECT"

  tags = local.tags
}

# Explicitly create a Internet Gateway here in the Private EKS VPC as without an
# internet gateway, a NLB cannot be created. Config option of create_igw = true
# (default) did not work during the VPC creation as it requires public subnets
# and the related routes that connect them to IGW
resource "aws_internet_gateway" "igw" {
  vpc_id = module.vpc.vpc_id
  tags   = local.tags
}

################################################################################
# VPC Endpoints
################################################################################

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.1"

  vpc_id = module.vpc.vpc_id

  # Security group
  create_security_group      = true
  security_group_name_prefix = "${local.name}-vpc-endpoints-"
  security_group_description = "VPC endpoint security group"
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from VPC"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

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
    { for service in toset(["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "elasticloadbalancing", "sts", "kms", "logs", "ssm", "ssmmessages"]) :
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


provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {
  # Do not include local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
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
    Name       = local.name
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}


output "ssm_start_session" {
  description = "SSM start session command to connect to remote host created"
  value       = "aws ssm start-session --region ${local.region} --target ${module.client_ec2_instance.id}"
}

output "ssm_test" {
  description = "SSM commands to test connectivity from client EC2 instance to the private EKS cluster"
  value       = <<-EOT

    COMMAND="curl -ks ${module.eks.cluster_endpoint}/readyz"

    COMMAND_ID=$(aws ssm send-command --region ${local.region} \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[$COMMAND]" \
    --targets "Key=instanceids,Values=${module.client_ec2_instance.id}" \
    --query 'Command.CommandId' \
    --output text)

    aws ssm get-command-invocation --region ${local.region} \
    --command-id $COMMAND_ID \
    --instance-id ${module.client_ec2_instance.id} \
    --query 'StandardOutputContent' \
    --output text
  EOT
}


################################################################################
# Internal NLB
################################################################################

module "nlb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.6"

  name               = local.name
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.private_subnets
  internal           = true
  load_balancer_type = "network"

  target_groups = [{
    name             = local.name
    backend_protocol = "TCP"
    backend_port     = 443
    target_type      = "ip"
    health_check = {
      enabled  = true
      path     = "/readyz"
      protocol = "HTTPS"
      matcher  = "200"
    }
  }]

  http_tcp_listeners = [{
    port               = 443
    protocol           = "TCP"
    target_group_index = 0
  }]

  tags = local.tags
}

data "dns_a_record_set" "nlb" {
  host = module.nlb.lb_dns_name
}

# VPC Endpoint Service that can be shared with other services in other VPCs.
# This Service Endpoint is created in the VPC where the LB exists; the client
# VPC Endpoint will connect to this service to reach the cluster via AWS PrivateLink
resource "aws_vpc_endpoint_service" "this" {
  acceptance_required        = true
  network_load_balancer_arns = [module.nlb.lb_arn]

  tags = merge(local.tags,
    { Name = local.name },
  )
}

resource "aws_vpc_endpoint_connection_accepter" "this" {
  vpc_endpoint_service_id = aws_vpc_endpoint_service.this.id
  vpc_endpoint_id         = aws_vpc_endpoint.client.id
}

################################################################################
# VPC Endpoint
# This allows resources in the client VPC to connect to the EKS cluster API
# endpoint in the EKS VPC without going over the internet, using a VPC peering
# connection, or a transit gateway attachment between VPCs
################################################################################

locals {
  # Get patterns for subdomain name (index 1) and domain name (index 2)
  api_server_url_pattern = regex("(https://)([[:alnum:]]+\\.)(.*)", module.eks.cluster_endpoint)

  # Retrieve the subdomain and domain name of the API server endpoint URL
  cluster_endpoint_subdomain = local.api_server_url_pattern[1]
  cluster_endpoint_domain    = local.api_server_url_pattern[2]
}

resource "aws_vpc_endpoint" "client" {
  vpc_id             = module.client_vpc.vpc_id
  service_name       = resource.aws_vpc_endpoint_service.this.service_name
  vpc_endpoint_type  = "Interface"
  subnet_ids         = module.client_vpc.private_subnets
  security_group_ids = [resource.aws_security_group.client_vpc_endpoint.id]

  tags = merge(local.tags,
    { Name = local.name },
  )
}

# Create a new security group that allows TLS traffic on port 443 and let the
# client applications in Client VPC connect to the VPC Endpoint on port 443
resource "aws_security_group" "client_vpc_endpoint" {
  name_prefix = "${local.name}-"
  description = "Allow TLS inbound traffic"
  vpc_id      = module.client_vpc.vpc_id

  ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.client_vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [module.client_vpc.vpc_cidr_block]
  }

  tags = local.tags
}

resource "aws_route53_zone" "client" {
  name    = local.cluster_endpoint_domain
  comment = "Private hosted zone for EKS API server endpoint"

  vpc {
    vpc_id = module.client_vpc.vpc_id
  }

  tags = local.tags
}

resource "aws_route53_record" "client" {
  zone_id = resource.aws_route53_zone.client.zone_id
  name    = "${local.cluster_endpoint_subdomain}${local.cluster_endpoint_domain}"
  type    = "A"

  alias {
    name                   = resource.aws_vpc_endpoint.client.dns_entry[0].dns_name
    zone_id                = resource.aws_vpc_endpoint.client.dns_entry[0].hosted_zone_id
    evaluate_target_health = true
  }
}

################################################################################
# Lambda - Create ENI IPs to NLB Target Group
################################################################################

module "create_eni_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 5.0"

  function_name = "${local.name}-add-eni-ips"
  description   = "Add ENI IPs to NLB target group when EKS API endpoint is created"
  handler       = "create_eni.handler"
  runtime       = "python3.10"
  publish       = true
  source_path   = "lambdas"

  attach_policy_json = true
  policy_json        = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "elasticloadbalancing:RegisterTargets"
          ],
          "Resource": ["${module.nlb.target_group_arns[0]}"]
        }
      ]
    }
  EOT

  environment_variables = {
    TARGET_GROUP_ARN = module.nlb.target_group_arns[0]
  }

  tracing_mode = "Active"

  allowed_triggers = {
    eventbridge = {
      principal  = "events.amazonaws.com"
      source_arn = module.eventbridge.eventbridge_rule_arns["eks-api-endpoint-create"]
    }
  }

  tags = local.tags
}

################################################################################
# Lambda - Delete ENI IPs from NLB Target Group
################################################################################

module "delete_eni_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 5.0"

  function_name = "${local.name}-delete-eni-ips"
  description   = "Deletes ENI IPs from NLB target group when EKS API endpoint is deleted"
  handler       = "delete_eni.handler"
  runtime       = "python3.10"
  publish       = true
  source_path   = "lambdas"

  attach_policy_json = true
  policy_json        = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "ec2:DescribeNetworkInterfaces",
            "elasticloadbalancing:Describe*"
          ],
          "Resource": ["*"]
        },
        {
          "Effect": "Allow",
          "Action": [
            "elasticloadbalancing:DeregisterTargets"
          ],
          "Resource": ["${module.nlb.target_group_arns[0]}"]
        }
      ]
    }
  EOT

  environment_variables = {
    TARGET_GROUP_ARN = module.nlb.target_group_arns[0]

    # Passing local.name in lieu of module.eks.cluster_name to avoid dependency
    EKS_CLUSTER_NAME = local.name
  }

  tracing_mode = "Active"

  allowed_triggers = {
    eventbridge = {
      principal  = "events.amazonaws.com"
      source_arn = module.eventbridge.eventbridge_rule_arns["eks-api-endpoint-delete"]
    }
  }

  tags = local.tags
}

################################################################################
# EventBridge Rules
################################################################################

module "eventbridge" {
  source  = "terraform-aws-modules/eventbridge/aws"
  version = "~> 2.0"

  # Use the existing default event bus
  create_bus = false

  rules = {
    eks-api-endpoint-create = {
      event_pattern = jsonencode({
        "source" : ["aws.ec2"],
        "detail-type" : ["AWS API Call via CloudTrail"],
        "detail" : {
          "eventSource" : ["ec2.amazonaws.com"],
          "eventName" : ["CreateNetworkInterface"],
          "sourceIPAddress" : ["eks.amazonaws.com"],
          "responseElements" : {
            "networkInterface" : {
              "description" : ["Amazon EKS ${local.name}"]
            }
          }
        }
      })
      enabled = true
    }

    eks-api-endpoint-delete = {
      description         = "Trigger for a Lambda"
      schedule_expression = "rate(15 minutes)"
    }
  }

  targets = {
    eks-api-endpoint-create = [
      {
        name = module.create_eni_lambda.lambda_function_name
        arn  = module.create_eni_lambda.lambda_function_arn
      }
    ]
    eks-api-endpoint-delete = [
      {
        name = module.delete_eni_lambda.lambda_function_name
        arn  = module.delete_eni_lambda.lambda_function_arn
      }
    ]
  }

  tags = local.tags
}

terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34, < 6.0"
    }
    dns = {
      source  = "hashicorp/dns"
      version = ">= 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20"
    }
  }

  # ##  Used for end-to-end testing on project; update to suit your needs
  # backend "s3" {
  #   bucket = "terraform-ssp-github-actions-state"
  #   region = "us-west-2"
  #   key    = "e2e/privatelink-access/terraform.tfstate"
  # }
}