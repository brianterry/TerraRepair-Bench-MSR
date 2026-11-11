#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-role-for-service-accounts-eks?ref=de95e21a3c52cd153a4bae6adf355df074471a40"
  role_name_prefix      = format("%s-%s", local.name, "ebs-csi-driver")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}
#---------------------------------------------------------------
# EKS Blueprints Kubernetes Addons
#---------------------------------------------------------------
module "eks_blueprints_addons" {
  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addons.git?ref=a9963f4a0e168f73adb033be594ac35868696a91"

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
    eks-pod-identity-agent = {}
  }

  #---------------------------------------
  # Install cert-manager
  #---------------------------------------
  enable_cert_manager = true
  cert_manager = {
    set_values = [
      {
        name  = "extraArgs[0]"
        value = "--enable-certificate-owner-ref=false"
      },
    ]
  }

  #---------------------------------------
  # Metrics Server
  #---------------------------------------
  enable_metrics_server = true
  metrics_server = {
    values = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {})]
  }

  #---------------------------------------
  # Cluster Autoscaler
  #---------------------------------------
  enable_cluster_autoscaler = true
  cluster_autoscaler = {
    create_role = true
    values = [templatefile("${path.module}/helm-values/cluster-autoscaler-values.yaml", {
      aws_region     = var.region,
      eks_cluster_id = module.eks.cluster_name
    })]
  }

  #---------------------------------------
  # CloudWatch metrics for EKS
  #---------------------------------------
  enable_aws_cloudwatch_metrics = true
  aws_cloudwatch_metrics = {
    values = [templatefile("${path.module}/helm-values/aws-cloudwatch-metrics-values.yaml", {})]
  }

}

#------------------------------
# Karpenter
#------------------------------
module "karpenter" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git//modules/karpenter?ref=0debf57cbd72e0c5ac397f45a292d9d1c9f81a4c"

  cluster_name          = module.eks.cluster_name
  enable_v1_permissions = true

  enable_pod_identity             = true
  create_pod_identity_association = true

  # Used to attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags

  depends_on = [
    module.eks
  ]
}

# Deploy Karpenter using Helm
resource "helm_release" "karpenter" {
  namespace  = "kube-system"
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.6.1"
  wait       = false

  values = [
    <<-EOT
    nodeSelector:
      NodeGroupType: core
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    webhook:
      enabled: false
    EOT
  ]

  lifecycle {
    ignore_changes = [
      repository_password
    ]
  }

  depends_on = [
    module.karpenter
  ]
}


#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  depends_on = [module.flink_irsa_jobs, module.flink_irsa_operator, module.eks_blueprints_addons, helm_release.karpenter]

  source            = "git::https://github.com/aws-ia/terraform-aws-eks-data-addons.git?ref=a5d00f64756d5ec6a5291dc1d02605ab0d4dff00"
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------------------------------
  # EMR Flink operator
  #---------------------------------------------------------------
  enable_emr_flink_operator = true
  emr_flink_operator_helm_config = {
    repository               = "oci://public.ecr.aws/emr-on-eks"
    operatorExecutionRoleArn = module.flink_irsa_operator.iam_role_arn
    version                  = "7.9.0"
  }

  #---------------------------------------------------------------
  # Karpenter nodepools
  #---------------------------------------------------------------
  enable_karpenter_resources = true
  karpenter_resources_helm_config = {
    flink-compute-optimized = {
      values = [
        <<-EOT
      name: flink-compute-optimized

      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:

        karpenterRole: ${split("/", module.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            Name: "${module.eks.cluster_name}-private*"
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0

      nodePool:

        labels:
          - type: karpenter
          - NodeGroupType: FlinkComputeOptimized
          - multiArch: Flink
        nodeClassRef:
          name: flink-compute-optimized
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot","on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["c"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["c5d"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: ["4", "8", "16", "36"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["2"]

        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmpty
          consolidateAfter: 30s
          expireAfter: 720h
        weight: 100
      EOT
      ]
    }
    flink-graviton-memory-optimized = {
      values = [
        <<-EOT
      name: flink-graviton-memory-optimized
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        karpenterRole: ${split("/", module.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            Name: "${module.eks.cluster_name}-private*"
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0
      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: FlinkGravitonMemoryOptimized
          - multiArch: Flink
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["arm64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["r"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["r6gd"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: ["4", "8", "16", "32"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["2"]
        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmpty
          consolidateAfter: 30s
          expireAfter: 720h
        weight: 50
      EOT
      ]
    }
  }
}


resource "kubernetes_namespace_v1" "flink_team_a" {
  metadata {
    name = "${local.flink_team}-ns"
  }
  timeouts {
    delete = "15m"
  }
}

#---------------------------------------------------------------
# Creates IAM policy for IRSA. Provides IAM permissions for flink pods
#---------------------------------------------------------------
resource "aws_iam_policy" "flink" {
  description = "IAM role policy for flink Job execution"
  name        = "${local.name}-flink-irsa"
  policy      = data.aws_iam_policy_document.flink_sample_job.json
}

#---------------------------------------------------------------
# IRSA for flink pods for "flink-team-a"
#---------------------------------------------------------------
module "flink_irsa_jobs" {
  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addon.git?ref=a34c5fadcd379e8f1d3763d492f3519a63c329eb"

  # Disable helm release
  create_release = false
  # IAM role for service account (IRSA)
  create_role   = true
  role_name     = "${local.name}-${local.flink_team}"
  create_policy = false
  role_policies = {
    flink_team_a_policy = aws_iam_policy.flink.arn
  }
  assume_role_condition_test = "StringLike"
  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = "${local.flink_team}-ns"
      service_account = "emr-containers-sa-*-*-${data.aws_caller_identity.current.account_id}-*"
    }
  }
}

#---------------------------------------------------------------
# IRSA for flink pods for "flink-operator"
#---------------------------------------------------------------
module "flink_irsa_operator" {
  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addon.git?ref=a34c5fadcd379e8f1d3763d492f3519a63c329eb"

  # Disable helm release
  create_release = false
  # IAM role for service account (IRSA)
  create_role   = true
  role_name     = "${local.name}-operator"
  create_policy = false
  role_policies = {
    flink_team_a_policy = aws_iam_policy.flink.arn
  }
  assume_role_condition_test = "StringLike"
  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = "${local.flink_operator}-ns"
      service_account = "emr-containers-sa-flink-operator"
    }
  }
}

#---------------------------------------------------------------
# Creates a log group
#---------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flink_team_a" {
  name              = "/aws/emr-flink/flink-team-a"
  retention_in_days = 365
  kms_key_id        = module.eks.kms_key_arn
}

#---------------------------------------------------------------
# Example IAM policy for Flink job execution
#---------------------------------------------------------------
data "aws_iam_policy_document" "flink_sample_job" {
  statement {
    sid    = "S3BucketLevel"
    effect = "Allow"
    resources = [
      module.s3_bucket.s3_bucket_arn
    ]
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
  }
  statement {
    sid    = "S3ObjectLevel"
    effect = "Allow"
    resources = [
      "${module.s3_bucket.s3_bucket_arn}/*"
    ]
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObjectVersion"
    ]
  }
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    resources = [
      aws_cloudwatch_log_group.flink_team_a.arn,
      "${aws_cloudwatch_log_group.flink_team_a.arn}:*"
    ]
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]
  }
}

#---------------------------------------------------------------
# S3 bucket for Flink related data,logs and checkpoint
#---------------------------------------------------------------
module "s3_bucket" {
  source                           = "git::https://github.com/terraform-aws-modules/terraform-aws-s3-bucket.git?ref=8a0b697adfbc673e6135c70246cff7f8052ad95a"
  bucket                           = "${local.name}-${data.aws_caller_identity.current.account_id}"
  attach_require_latest_tls_policy = true
  attach_access_log_delivery_policy = true
  block_public_acls                = true
  block_public_policy              = true
  ignore_public_acls               = true
  restrict_public_buckets          = true

  versioning = {
    enabled = true
  }

  logging = {
    target_bucket = "${local.name}-${data.aws_caller_identity.current.account_id}"
    target_prefix = "access-logs/"
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
  tags = local.tags
}

resource "aws_s3_object" "checkpoints" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "checkpoints/"
  content_type = "application/x-directory"
}

resource "aws_s3_object" "savepoints" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "savepoints/"
  content_type = "application/x-directory"
}

resource "aws_s3_object" "jobmanager" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "jobmanager/"
  content_type = "application/x-directory"
}

resource "aws_s3_object" "logs" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "logs/"
  content_type = "application/x-directory"
}


#create local
locals {
  name   = var.name
  region = var.region
  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
  flink_team     = "flink-team-a"
  flink_operator = "flink-kubernetes-operator"
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_availability_zones" "available" {
  state            = "available"
  exclude_zone_ids = ["usw2-az4"]
}

data "aws_caller_identity" "current" {}


#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------
module "eks" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=0debf57cbd72e0c5ac397f45a292d9d1c9f81a4c"

  cluster_name                    = local.name
  cluster_version                 = var.eks_cluster_version
  cluster_endpoint_private_access = true # if true, Kubernetes API requests within your cluster's VPC (such as node to control plane communication) use the private VPC endpoint
  cluster_endpoint_public_access  = false # if true, Your cluster API server is accessible from the internet. You can, optionally, limit the CIDR blocks that can access the public endpoint.
  cluster_endpoint_public_access_cidrs = ["10.0.0.0/16"]
  cluster_enabled_log_types       = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  vpc_id                          = module.vpc.vpc_id
  subnet_ids                      = module.vpc.private_subnets

  # Add the IAM identity that terraform is using as a cluster admin
  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  kms_key_statements = {
    cloudwatch_logs = {
      sid    = "CloudWatchLogs"
      effect = "Allow"
      principals = [
        {
          type        = "Service"
          identifiers = ["logs.${local.region}.amazonaws.com"]
        }
      ]
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ]
      resources = ["*"]
    }
    cloudwatch_logs_grant = {
      sid    = "CloudWatchLogsCreateGrant"
      effect = "Allow"
      principals = [
        {
          type        = "Service"
          identifiers = ["logs.${local.region}.amazonaws.com"]
        }
      ]
      actions   = ["kms:CreateGrant"]
      resources = ["*"]
      conditions = [
        {
          test     = "Bool"
          variable = "kms:GrantIsForAWSResource"
          values   = ["true"]
        }
      ]
    }
  }

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
  }

  node_security_group_enable_recommended_rules = false

  # Extend node-to-node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_vpc = {
      description = "Node egress to VPC"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["10.0.0.0/16"]
    }
    # Allows Control Plane Nodes to talk to Worker nodes on all ports. Added this to simplify the example and further avoid issues with Add-ons communication with Control plane.
    # This can be restricted further to specific port based on the requirement for each Add-on e.g., metrics-server 4443, spark-operator 8080, karpenter 8443 etc.
    # Change this according to your security requirements if needed
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # Not required, but used in the example to access the nodes to inspect mounted volumes
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }

  eks_managed_node_groups = {
    #  We recommend to have a MNG to place your critical workloads and add-ons
    #  Then rely on Karpenter to scale your workloads
    #  You can also make uses on nodeSelector and Taints/tolerations to spread workloads on MNG or Karpenter provisioners

    core_node_group = {
      name        = "core-node-group"
      description = "EKS managed node group example launch template"
      subnet_ids  = module.vpc.private_subnets

      min_size     = 1
      max_size     = 9
      desired_size = 3

      force_update_version = true
      instance_types       = ["m5.xlarge"]

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
      }

      tags = {
        Name = "core-node-grp"
      }
    }


  }
}


################################################################################
# EMR Flink operator
################################################################################
output "flink_job_execution_role_arn" {
  value       = module.flink_irsa_jobs.iam_role_arn
  description = "IAM linked role for the flink job"
}

output "flink_operator_role_arn" {
  value       = module.flink_irsa_operator.iam_role_arn
  description = "IAM linked role for the flink operator"
}

output "flink_operator_bucket" {
  value       = module.s3_bucket.s3_bucket_id
  description = "S3 bucket name for Flink operator data,logs,checkpoint and savepoint"
}

################################################################################
# EKS Managed Node Group
################################################################################
output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}



provider "aws