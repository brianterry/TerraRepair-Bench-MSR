provider "aws" {
  region = local.region
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  # Exclude local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
  state = "available"
}

locals {
  name               = "ex-${replace(basename(path.cwd), "_", "-")}"
  kubernetes_version = "1.33"
  region             = "eu-west-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Test       = local.name
    GithubRepo = "terraform-aws-eks"
    GithubOrg  = "terraform-aws-modules"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc"
  version = "6.0.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags

  flow_logs_iam_role_arn = aws_iam_role.vpc_flow_logs.arn
  flow_logs_enabled      = true
  flow_logs_traffic_type = "REJECT"
}

module "aws_vpc_cni_ipv4_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws//modules/iam"
  version = "1.6.0"

  name = "aws-vpc-cni-ipv4"

  attach_aws_vpc_cni_policy = true
  aws_vpc_cni_enable_ipv4   = true

  tags = local.tags
}

module "key_pair" {
  source  = "terraform-aws-modules/key-pair/aws//modules/key-pair"
  version = "2.0.0"

  key_name_prefix    = local.name
  create_private_key = true

  tags = local.tags
}

module "ebs_kms_key" {
  source  = "terraform-aws-modules/kms/aws//modules/key"
  version = "4.0.0"

  description = "Customer managed key to encrypt EKS managed node group volumes"

  # Policy
  key_administrators = [
    data.aws_caller_identity.current.arn
  ]

  key_service_roles_for_autoscaling = [
    # required for the ASG to manage encrypted volumes for nodes
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling",
    # required for the cluster / persistentvolume-controller to create encrypted PVCs
    module.eks.cluster_iam_role_arn,
  ]

  # Aliases
  aliases = ["eks/${local.name}/ebs"]

  tags = local.tags
}

module "kms" {
  source  = "terraform-aws-modules/kms/aws//modules/key"
  version = "4.0.0"

  aliases               = ["eks/${local.name}"]
  description           = "${local.name} cluster encryption key"
  enable_default_policy = true
  key_owners            = [data.aws_caller_identity.current.arn]

  tags = local.tags
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${local.name}-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "additional" {
  name        = "${local.name}-additional"
  description = "Example usage of node additional policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:Describe*",
        ]
        Effect   = "Allow"
        Resource = [
          "arn:aws:ec2:*:*:instance/*",
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*",
          "arn:aws:ec2:*:*:image/*",
          "arn:aws:ec2:*:*:security-group/*",
          "arn:aws:ec2:*:*:network-interface/*",
          "arn:aws:ec2:*:*:key-pair/*",
          "arn:aws:ec2:*:*:launch-template/*",
          "arn:aws:ec2:*:*:subnet/*",
          "arn:aws:ec2:*:*:vpc/*",
          "arn:aws:ec2:*:*:route-table/*",
          "arn:aws:ec2:*:*:route/*",
          "arn:aws:ec2:*:*:internet-gateway/*",
          "arn:aws:ec2:*:*:natgateway/*",
          "arn:aws:ec2:*:*:network-acl/*",
          "arn:aws:ec2:*:*:network-acl-entry/*",
          "arn:aws:ec2:*:*:dhcp-options/*",
          "arn:aws:ec2:*:*:customer-gateway/*",
          "arn:aws:ec2:*:*:vpn-gateway/*",
          "arn:aws:ec2:*:*:vpn-connection/*",
          "arn:aws:ec2:*:*:transit-gateway/*",
          "arn:aws:ec2:*:*:transit-gateway-attachment/*",
          "arn:aws:ec2:*:*:transit-gateway-route-table/*",
          "arn:aws:ec2:*:*:transit-gateway-route/*",
          "arn:aws:ec2:*:*:transit-gateway-vpc-attachment/*",
          "arn:aws:ec2:*:*:transit-gateway-peering-attachment/*",
          "arn:aws:ec2:*:*:transit-gateway-multicast-domain/*",
          "arn:aws:ec2:*:*:transit-gateway-multicast-domain-association/*",
          "arn:aws:ec2:*:*:transit-gateway-route-table-association/*",
          "arn:aws:ec2:*:*:transit-gateway-route-table-propagation/*",
          "arn:aws:ec2:*:*:local-gateway/*",
          "arn:aws:ec2:*:*:local-gateway-route-table/*",
          "arn:aws:ec2:*:*:local-gateway-route-table-vpc-association/*",
          "arn:aws:ec2:*:*:local-gateway-route-table-virtual-interface-group-association/*",
          "arn:aws:ec2:*:*:local-gateway-virtual-interface/*",
          "arn:aws:ec2:*:*:local-gateway-virtual-interface-group/*",
          "arn:aws:ec2:*:*:capacity-reservation/*",
          "arn:aws:ec2:*:*:capacity-reservation-fleet/*",
          "arn:aws:ec2:*:*:client-vpn-endpoint/*",
          "arn:aws:ec2:*:*:client-vpn-network-association/*",
          "arn:aws:ec2:*:*:client-vpn-authorization-rule/*",
          "arn:aws:ec2:*:*:client-vpn-route/*",
          "arn:aws:ec2:*:*:traffic-mirror-filter/*",
          "arn:aws:ec2:*:*:traffic-mirror-session/*",
          "arn:aws:ec2:*:*:traffic-mirror-target/*",
          "arn:aws:ec2:*:*:verified-access-instance/*",
          "arn:aws:ec2:*:*:verified-access-group/*",
          "arn:aws:ec2:*:*:verified-access-endpoint/*",
          "arn:aws:ec2:*:*:verified-access-policy/*",
          "arn:aws:ec2:*:*:verified-access-trust-provider/*",
          "arn:aws:ec2:*:*:ipam/*",
          "arn:aws:ec2:*:*:ipam-pool/*",
          "arn:aws:ec2:*:*:ipam-scope/*",
          "arn:aws:ec2:*:*:launch-template/*",
          "arn:aws:ec2:*:*:launch-template-version/*",
          "arn:aws:ec2:*:*:network-insights-access-scope/*",
          "arn:aws:ec2:*:*:network-insights-access-scope-analysis/*",
          "arn:aws:ec2:*:*:network-insights-path/*",
          "arn:aws:ec2:*:*:network-insights-analysis/*",
          "arn:aws:ec2:*:*:network-performance-profile/*",
          "arn:aws:ec2:*:*:outpost/*",
          "arn:aws:ec2:*:*:outpost-instance-type/*",
          "arn:aws:ec2:*:*:placement-group/*",
          "arn:aws:ec2:*:*:prefix-list/*",
          "arn:aws:ec2:*:*:route-table/*",
          "arn:aws:ec2:*:*:route/*",
          "arn:aws:ec2:*:*:security-group/*",
          "arn:aws:ec2:*:*:security-group-rule/*",
          "arn:aws:ec2:*:*:snapshot/*",
          "arn:aws:ec2:*:*:spot-fleet-request/*",
          "arn:aws:ec2:*:*:spot-instances-request/*",
          "arn:aws:ec2:*:*:subnet/*",
          "arn:aws:ec2:*:*:subnet-cidr-reservation/*",
          "arn:aws:ec2:*:*:traffic-mirror-filter/*",
          "arn:aws:ec2:*:*:traffic-mirror-session/*",
          "arn:aws:ec2:*:*:traffic-mirror-target/*",
          "arn:aws:ec2:*:*:transit-gateway/*",
          "arn:aws:ec2:*:*:transit-gateway-attachment/*",
          "arn:aws:ec2:*:*:transit-gateway-connect-peer/*",
          "arn:aws:ec2:*:*:transit-gateway-multicast-domain/*",
          "arn:aws:ec2:*:*:transit-gateway-multicast-domain-association/*",
          "arn:aws:ec2:*:*:transit-gateway-route-table/*",
          "arn:aws:ec2:*:*:transit-gateway-route/*",
          "arn:aws:ec2:*:*:transit-gateway-vpc-attachment/*",
          "arn:aws:ec2:*:*:verified-access-endpoint/*",
          "arn:aws:ec2:*:*:verified-access-group/*",
          "arn:aws:ec2:*:*:verified-access-instance/*",
          "arn:aws:ec2:*:*:verified-access-policy/*",
          "arn:aws:ec2:*:*:verified-access-trust-provider/*",
          "arn:aws:ec2:*:*:vpc/*",
          "arn:aws:ec2:*:*:vpc-cidr-block-association/*",
          "arn:aws:ec2:*:*:vpc-endpoint/*",
          "arn:aws:ec2:*:*:vpc-endpoint-connection/*",
          "arn:aws:ec2:*:*:vpc-endpoint-service/*",
          "arn:aws:ec2:*:*:vpc-flow-log/*",
          "arn:aws:ec2:*:*:vpc-peering-connection/*",
          "arn:aws:ec2:*:*:vpc-security-group/*",
          "arn:aws:ec2:*:*:vpc-security-group-rule/*",
          "arn:aws:ec2:*:*:vpc-subnet/*",
          "arn:aws:ec2:*:*:vpc-subnet-cidr-block-association/*",
          "arn:aws:ec2:*:*:vpc-traffic-mirror-filter/*",
          "arn:aws:ec2:*:*:vpc-traffic-mirror-session/*",
          "arn:aws:ec2:*:*:vpc-traffic-mirror-target/*",
          "arn:aws:ec2:*:*:vpn-connection/*",
          "arn:aws:ec2:*:*:vpn-gateway/*",
          "arn:aws:ec2:*:*:vpn-gateway-route-propagation/*",
        ]
      },
    ]
  })

  tags = local.tags
}

module "eks" {
  source = "../../.."

  name                   = local.name
  kubernetes_version     = local.kubernetes_version
  endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      before_compute = true
      most_recent    = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      before_compute = true
      most_recent    = true
      pod_identity_association = [{
        role_arn        = module.aws_vpc_cni_ipv4_pod_identity.iam_role_arn
        service_account = "aws-node"
      }]
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  # External encryption key
  create_kms_key = false
  encryption_config = {
    resources        = ["secrets"]
    provider_key_arn = module.kms.key_arn
  }

  self_managed_node_groups = {
    # Default node group - as provisioned by the module defaults
    default_node_group = {
      ami_type = "AL2023_x86_64_STANDARD"
      ami_id   = data.aws_ami.eks_default.image_id

      # enable discovery of autoscaling groups by cluster-autoscaler
      autoscaling_group_tags = {
        "k8s.io/cluster-autoscaler/enabled" : true,
        "k8s.io/cluster-autoscaler/${local.name}" : "owned",
      }
    }

    # Bottlerocket node group
    bottlerocket = {
      name = "bottlerocket-self-mng"

      ami_type      = "BOTTLEROCKET_x86_64"
      ami_id        = data.aws_ami.eks_default_bottlerocket.id
      instance_type = "m5.large"
      desired_size  = 2
      key_name      = module.key_pair.key_pair_name

      bootstrap_extra_args = <<-EOT
        # The admin host container provides SSH access and runs with "superpowers".
        # It is disabled by default, but can be disabled explicitly.
        [settings.host-containers.admin]
        enabled = false

        # The control host container provides out-of-band access via SSM.
        # It is enabled by default, and can be disabled if you do not expect to use SSM.
        # This could leave you with no way to access the API and change settings on an existing node!
        [settings.host-containers.control]
        enabled = true

        # extra args added
        [settings.kernel]
        lockdown = "integrity"

        [settings.kubernetes.node-labels]
        label1 = "foo"
        label2 = "bar"

        [settings.kubernetes.node-taints]
        dedicated = "experimental:PreferNoSchedule"
        special = "true:NoSchedule"
      EOT
    }

    mixed = {
      name = "mixed"

      min_size     = 1
      max_size     = 5
      desired_size = 2

      cloudinit_pre_nodeadm = [{
        content      = <<-EOT
          ---
          apiVersion: node.eks.aws/v1alpha1
          kind: NodeConfig
          spec:
            kubelet:
              flags:
                - --node-labels=node.kubernetes.io/lifecycle=spot
        EOT
        content_type = "application/node.eks.aws"
      }]

      use_mixed_instances_policy = true
      mixed_instances_policy = {
        instances_distribution = {
          on_demand_base_capacity                  = 0
          on_demand_percentage_above_base_capacity = 20
          spot_allocation_strategy                 = "capacity-optimized"
        }

        launch_template = {
          override = [
            {
              instance_type     = "m5.large"
              weighted_capacity = "1"
            },
            {
              instance_type     = "m6i.large"
              weighted_capacity = "2"
            },
          ]
        }
      }
    }

    instance_attributes = {
      name = "instance-attributes"

      min_size     = 1
      max_size     = 2
      desired_size = 1

      cloudinit_pre_nodeadm = [{
        content      = <<-EOT
          ---
          apiVersion: node.eks.aws/v1alpha1
          kind: NodeConfig
          spec:
            kubelet:
              config:
                shutdownGracePeriod: 30s
        EOT
        content_type = "application/node.eks.aws"
      }]

      instance_type = null

      # launch template configuration
      instance_requirements = {
        cpu_manufacturers                           = ["intel"]
        instance_generations                        = ["current", "previous"]
        spot_max_price_percentage_over_lowest_price = 100

        memory_mib = {
          min = 8192
        }

        vcpu_count = {
          min = 1
        }

        allowed_instance_types = ["t*", "m*"]
      }

      use_mixed_instances_policy = true
      mixed_instances_policy = {
        instances_distribution = {
          on_demand_base_capacity                  = 0
          on_demand_percentage_above_base_capacity = 0
          on_demand_allocation_strategy            = "lowest-price"
          spot_allocation_strategy                 = "price-capacity-optimized"
        }

        # ASG configuration
        launch_template = {
          override = [
            {
              instance_requirements = {
                cpu_manufacturers                           = ["intel"]
                instance_generations                        = ["current", "previous"]
                spot_max_price_percentage_over_lowest_price = 100

                memory_mib = {
                  min = 8192
                }

                vcpu_count = {
                  min = 1
                }

                allowed_instance_types = ["t*", "m*"]
              }
            }
          ]
        }
      }
    }

    complete = {
      name            = "complete-self-mng"
      use_name_prefix = false

      subnet_ids = module.vpc.public_subnets

      min_size     = 1
      max_size     = 7
      desired_size = 1

      cloudinit_pre_nodeadm = [{
        content      = <<-EOT
          ---
          apiVersion: node.eks.aws/v1alpha1
          kind: NodeConfig
          spec:
            kubelet:
              flags:
                - --node-labels=node.kubernetes.io/lifecycle=spot
        EOT
        content_type = "application/node.eks.aws"
      }]

      instance_type = "m6i.large"

      launch_template_name            = "self-managed-ex"
      launch_template_use_name_prefix = true
      launch_template_description     = "Self managed node group example launch template"

      ebs_optimized     = true
      enable_monitoring = true

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 75
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 150
            encrypted             = true
            kms_key_id            = module.ebs_kms_key.key_arn
            delete_on_termination = true
          }
        }
      }

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
        instance_metadata_tags      = "disabled"
      }

      create_iam_role          = true
      iam_role_name            = "self-managed-node-group-complete-example"
      iam_role_use_name_prefix = false
      iam_role_description     = "Self managed node group complete example role"
      iam_role_tags = {
        Purpose = "Protector of the kubelet"
      }
      iam_role_additional_policies = {
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        additional                         = aws_iam_policy.additional.arn
      }

      tags = {
        ExtraTag = "Self managed node group complete example"
      }
    }

    efa = {
      # The EKS AL2023 NVIDIA AMI provides all of the necessary components
      # for accelerated workloads w/ EFA
      ami_type       = "AL2023_x86_64_NVIDIA"
      instance_types = ["p4d.24xlarge"]

      # Setting to zero so all resources are created *EXCEPT the EC2 instances
      min_size     = 0
      max_size     = 1
      desired_size = 0

      # Mount instance store volumes in RAID-0 for kubelet and containerd
      # https://github.com/awslabs/amazon-eks-ami/blob/master/doc/USER_GUIDE.md#raid-0-for-kubelet-and-containerd-raid0
      cloudinit_pre_nodeadm = [
        {
          content_type = "application/node.eks.aws"
          content      = <<-EOT
            ---
            apiVersion: node.eks.aws/v1alpha1
            kind: NodeConfig
            spec:
              instance:
                localStorage:
                  strategy: RAID0
          EOT
        }
      ]

      # This will:
      # 1. Create a placement group to place the instances close to one another
      # 2. Create and attach the necessary security group rules (and security group)
      # 3. Expose all of the available EFA interfaces on the launch template
      enable_efa_support = true
      enable_efa_only    = true
      efa_indices        = [0]

      labels = {
        "vpc.amazonaws.com/efa.present" = "true"
        "nvidia.com/gpu.present"        = "true"
      }

      taints = {
        # Ensure only GPU workloads are scheduled on this node group
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  tags = local.tags
}

module "disabled_self_managed_node_group" {
  source = "../../modules/self-managed-node-group"

  create = false

  # Hard requirement
  cluster_service_cidr = ""
}

data "aws_ami" "eks_default" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-al2023-x86_64-standard-${local.kubernetes_version}-v*"]
  }
}

data "aws_ami" "eks_default_bottlerocket" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["bottlerocket-aws-k8s-${local.kubernetes_version}-x86_64-*"]
  }
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_id" {
  description = "The ID of the EKS cluster. Note: currently a value is returned only for local EKS clusters created on Outposts"
  value       = module.eks.cluster_id
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = module.eks.cluster_oidc_issuer_url
}

output "cluster_dualstack_oidc_issuer_url" {
  description = "Dual-stack compatible URL on the EKS cluster for the OpenID Connect identity provider"
  value       = module.eks.cluster_dualstack_oidc_issuer_url
}

output "cluster_platform_version" {
  description = "Platform version for the cluster"
  value       = module.eks.cluster_platform_version
}

output "cluster_status" {
  description = "Status of the EKS cluster. One of `CREATING`, `ACTIVE`, `DELETING`, `FAILED`"
  value       = module.eks.cluster_status
}

output "cluster_primary_security_group_id" {
  description = "Cluster security group that was created by Amazon EKS for the cluster. Managed node groups use this security group for control-plane-to-data-plane communication. Referred to as 'Cluster security group' in the EKS console"
  value       = module.eks.cluster_primary_security_group_id
}

output "cluster_service_cidr" {
  description = "The CIDR block where Kubernetes pod and service IP addresses are assigned from"
  value       = module.eks.cluster_service_cidr
}

output "cluster_ip_family" {
  description = "The IP family used by the cluster (e.g. `ipv4` or `ipv6`)"
  value       = module.eks.cluster_ip_family
}

output "access_entries" {
  description = "Map of access entries created and their attributes"
  value       = module.eks.access_entries
}

output "kms_key_arn" {
  description = "The Amazon Resource Name (ARN) of the key"
  value       = module.eks.kms_key_arn
}

output "kms_key_id" {
  description = "The globally unique identifier for the key"
  value       = module.eks.kms_key_id
}

output "kms_key_policy" {
  description = "The IAM resource policy set on the key"
  value       = module.eks.kms_key_policy
}

output "cluster_security_group_arn" {
  description = "Amazon Resource Name (ARN) of the cluster security group"
  value       = module.eks.cluster_security_group_arn
}

output "cluster_security_group_id" {
  description = "ID of the cluster security group"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_arn" {
  description = "Amazon Resource Name (ARN) of the node shared security group"
  value       = module.eks.node_security_group_arn
}

output "node_security_group_id" {
  description = "ID of the node shared security group"
  value       = module.eks.node_security_group_id
}

output "oidc_provider" {
  description = "The OpenID Connect identity provider (issuer URL without leading `https://`)"
  value       = module.eks.oidc_provider
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider if `enable_irsa = true`"
  value       = module.eks.oidc_provider_arn
}

output "cluster_tls_certificate_sha1_fingerprint" {
  description = "The SHA1 fingerprint of the public key of the cluster's certificate"
  value       = module.eks.cluster_tls_certificate_sha1_fingerprint
}

output "cluster_iam_role_name" {
  description = "Cluster IAM role name"
  value       = module.eks.cluster_iam_role_name
}

output "cluster_iam_role_arn" {
  description = "Cluster IAM role ARN"
  value       = module.eks.cluster_iam_role_arn
}

output "cluster_iam_role_unique_id" {
  description = "Stable and unique string identifying the IAM role"
  value       = module.eks.cluster_iam_role_unique_id
}

output "node_iam_role_name" {
  description = "EKS Auto node IAM role name"
  value       = module.eks.node_iam_role_name
}

output "node_iam_role_arn" {
  description = "EKS Auto node IAM role ARN"
  value       = module.eks.node_iam_role_arn
}

output "node_iam_role_unique_id" {
  description = "Stable and unique string identifying the IAM role"
  value       = module.eks.node_iam_role_unique_id
}

output "cluster_addons" {
  description = "Map of attribute maps for all EKS cluster addons enabled"
  value       = module.eks.cluster_addons
}

output "cluster_identity_providers" {
  description = "Map of attribute maps for all EKS identity providers enabled"
  value       = module.eks.cluster_identity_providers
}

output "cloudwatch_log_group_name" {
  description = "Name of cloudwatch log group created"
  value       = module.eks.cloudwatch_log_group_name
}

output "cloudwatch_log_group_arn" {
  description = "Arn of cloudwatch log group created"
  value       = module.eks.cloudwatch_log_group_arn
}

output "fargate_profiles" {
  description = "Map of attribute maps for all EKS Fargate Profiles created"
  value       = module.eks.fargate_profiles
}

output "eks_managed_node_groups" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value       = module.eks.eks_managed_node_groups
}

output "eks_managed_node_groups_autoscaling_group_names" {
  description = "List of the autoscaling group names created by EKS managed node groups"
  value       = module.eks.eks_managed_node_groups_autoscaling_group_names
}

output "self_managed_node_groups" {
  description = "Map of attribute maps for all self managed node groups created"
  value       = module.eks.self_managed_node_groups
}

output "self_managed_node_groups_autoscaling_group_names" {
  description = "List of the autoscaling group names created by self-managed node groups"
  value       = module.eks.self_managed_node_groups_autoscaling_group_names
}

terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28"
    }
  }
}