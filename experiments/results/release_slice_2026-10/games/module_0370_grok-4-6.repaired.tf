#---------------------------------------------------------------
# GP3 Encrypted Storage Class
#---------------------------------------------------------------

resource "kubernetes_annotations" "gp2_default" {
  annotations = {
    "storageclass.kubernetes.io/is-default-class" : "false"
  }
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  force = true

  depends_on = [module.eks]
}

resource "kubernetes_storage_class" "ebs_csi_encrypted_gp3_storage_class" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    fsType    = "xfs"
    encrypted = true
    type      = "gp3"
  }

  depends_on = [kubernetes_annotations.gp2_default]
}

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-role-for-service-accounts-eks?ref=e2d57ce650c211a3694d4a7ca1df171d0bfe6664"
  role_name_prefix      = format("%s-%s-", local.name, "ebs-csi-driver")
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
# EKS Blueprints Addons
#---------------------------------------------------------------
module "eks_blueprints_addons" {
  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addons.git?ref=a5ae82fe6a4a98e1a6d5e3c97cc40c32f20c15be"


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

  #---------------------------------------
  # Kubernetes Add-ons
  #---------------------------------------
  #---------------------------------------------------------------
  # CoreDNS Autoscaler helps to scale for large EKS Clusters
  #   Further tuning for CoreDNS is to leverage NodeLocal DNSCache -> https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
  #---------------------------------------------------------------
  enable_cluster_proportional_autoscaler = true
  cluster_proportional_autoscaler = {
    values = [templatefile("${path.module}/helm-values/coredns-autoscaler-values.yaml", {
      target = "deployment/coredns"
    })]
    description = "Cluster Proportional Autoscaler for CoreDNS Service"
  }

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                  = true
  karpenter_enable_spot_termination = true
  karpenter_node = {
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
    iam_role_permissions_boundary = null
  }
  karpenter = {
    chart_version       = "v0.34.0"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
    set = [
      {
        name  = "controller.resources.requests.cpu"
        value = "1"
      }
    ]
    role_policies = {
      passrole_filter = aws_iam_policy.karpenter_passrole_filter.arn
    }
  }

  #---------------------------------------
  # Metrics Server
  #---------------------------------------
  enable_metrics_server = true
  metrics_server = {
    values = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {})]
  }

  #---------------------------------------
  # AWS for FluentBit - DaemonSet
  #---------------------------------------
  enable_aws_for_fluentbit = true
  aws_for_fluentbit_cw_log_group = {
    use_name_prefix   = false
    name              = "/${local.name}/aws-fluentbit-logs"
    retention_in_days = 30
  }
  aws_for_fluentbit = {
    s3_bucket_arns = [
      module.s3_bucket.s3_bucket_arn,
      "${module.s3_bucket.s3_bucket_arn}/*"
    ]
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      region               = local.region,
      cloudwatch_log_group = "/${local.name}/aws-fluentbit-logs"
      s3_bucket_name       = module.s3_bucket.s3_bucket_id
      cluster_name         = module.eks.cluster_name
    })]
  }

  enable_aws_load_balancer_controller = true

  #---------------------------------------
  # Argo Workflows & Argo Events
  #---------------------------------------
  enable_argo_workflows = true
  argo_workflows = {
    name       = "argo-workflows"
    namespace  = "argo-workflows"
    repository = "https://argoproj.github.io/argo-helm"
    values     = [templatefile("${path.module}/helm-values/argo-workflows-values.yaml", {})]
  }

  enable_argo_events = true
  argo_events = {
    name       = "argo-events"
    namespace  = "argo-events"
    repository = "https://argoproj.github.io/argo-helm"
    values     = [templatefile("${path.module}/helm-values/argo-events-values.yaml", {})]
  }

  #---------------------------------------
  # Prommetheus and Grafana stack
  #---------------------------------------
  #---------------------------------------------------------------
  # Install Prometheus and Grafana
  # 1- Grafana port-forward `kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack`
  # 2- Grafana Admin user: admin
  # 3- Get admin user password: `aws secretsmanager get-secret-value --secret-id <output.grafana_secret_name> --region $AWS_REGION --query "SecretString" --output text`
  #---------------------------------------------------------------
  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    values = [
      var.enable_amazon_prometheus ? templatefile("${path.module}/helm-values/kube-prometheus-amp-enable.yaml", {
        region              = local.region
        amp_sa              = local.amp_ingest_service_account
        amp_irsa            = module.amp_ingest_irsa[0].iam_role_arn
        amp_remotewrite_url = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}/api/v1/remote_write"
        amp_url             = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}"
        storage_class_type  = kubernetes_storage_class.ebs_csi_encrypted_gp3_storage_class.id
      }) : templatefile("${path.module}/helm-values/kube-prometheus.yaml", {})
    ]
    chart_version = "48.1.1"
    set_sensitive = [
      {
        name  = "grafana.adminPassword"
        value = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
      }
    ],
  }

  tags = local.tags
}

resource "aws_iam_policy" "karpenter_passrole_filter" {
  name_prefix = "${local.name}-karpenter-passrole-"
  description = "Restrict iam:PassRole for Karpenter to EC2 and the node role"
  policy      = data.aws_iam_policy_document.karpenter_passrole_filter.json
}

data "aws_iam_policy_document" "karpenter_passrole_filter" {
  statement {
    sid    = "IAMPassRoleFiltering"
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [
      module.eks_blueprints_addons.karpenter.node_iam_role_arn
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }
}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source = "git::https://github.com/aws-ia/terraform-aws-eks-data-addons.git?ref=4f8a2c6e0b1d9a3f7e5c8b2d0a6f4e1c9b7d3a5e"

  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------------------------------
  # Spark Operator Add-on
  #---------------------------------------------------------------
  enable_spark_operator = true
  spark_operator_helm_config = {
    values = [templatefile("${path.module}/helm-values/spark-operator-values.yaml", {})]
  }

  #---------------------------------------------------------------
  # Apache YuniKorn Add-on
  #---------------------------------------------------------------
  enable_yunikorn = var.enable_yunikorn
  yunikorn_helm_config = {
    values = [templatefile("${path.module}/helm-values/yunikorn-values.yaml", {
      image_version = "1.2.0"
    })]
  }

  #---------------------------------------------------------------
  # Spark History Server Add-on
  #---------------------------------------------------------------
  # Spark history server is required only when EMR Spark Operator is enabled
  enable_spark_history_server = true
  spark_history_server_helm_config = {
    values = [
      <<-EOT
      sparkHistoryOpts: "-Dspark.history.fs.logDirectory=s3a://${module.s3_bucket.s3_bucket_id}/${aws_s3_object.this.key}"
      EOT
    ]
  }

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter_resources = true
  karpenter_resources_helm_config = {
    spark-compute-optimized = {
      values = [
        <<-EOT
      name: spark-compute-optimized
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
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
          - NodeGroupType: SparkComputeOptimized
          - multiArch: Spark
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
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
    spark-graviton-compute-optimized = {
      values = [
        <<-EOT
      name: spark-graviton-compute-optimized
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
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
          - NodeGroupType: SparkGravitonComputeOptimized
          - multiArch: Spark
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["arm64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["c"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["c7gd"]
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

#tfsec:ignore:*
module "s3_bucket" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-s3-bucket.git?ref=8aa0b7d61878c7e1c3f16243a9a03275d3aa85bd"

  bucket_prefix = "${local.name}-spark-logs-"

  # For example only - please evaluate for your environment
  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

# Creating an s3 bucket prefix. Ensure you copy Spark History event logs under this path to visualize the dags
resource "aws_s3_object" "this" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "spark-event-logs/"
  content_type = "application/x-directory"
}

#---------------------------------------------------------------
# Grafana Admin credentials resources
#---------------------------------------------------------------
data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id  = aws_secretsmanager_secret.grafana.id
  depends_on = [aws_secretsmanager_secret_version.grafana]
}

resource "random_password" "grafana" {
  length           = 16
  special          = true
  override_special = "@_"
}

resource "aws_kms_key" "grafana" {
  description             = "${local.name}-grafana"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${local.partition}:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_secretsmanager_secret" "grafana" {
  name                    = "${local.name}-grafana"
  recovery_window_in_days = 0
  kms_key_id              = aws_kms_key.grafana.id
}

resource "aws_secretsmanager_secret_rotation" "grafana" {
  secret_id = aws_secretsmanager_secret.grafana.id

  rotation_rules {
    automatically_after_days = 30
  }
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}


#IAM Policy for Amazon Prometheus & Grafana
resource "aws_iam_policy" "grafana" {
  count = var.enable_amazon_prometheus ? 1 : 0

  description = "IAM policy for Grafana Pod"
  name_prefix = format("%s-%s-", local.name, "grafana")
  path        = "/"
  policy      = data.aws_iam_policy_document.grafana[0].json
}

data "aws_iam_policy_document" "grafana" {
  count = var.enable_amazon_prometheus ? 1 : 0

  statement {
    sid       = "AllowReadingMetricsFromCloudWatch"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics"
    ]
  }

  statement {
    sid       = "AllowGetInsightsCloudWatch"
    effect    = "Allow"
    resources = ["arn:${local.partition}:cloudwatch:${local.region}:${local.account_id}:insight-rule/*"]

    actions = [
      "cloudwatch:GetInsightRuleReport",
    ]
  }

  statement {
    sid       = "AllowReadingAlarmHistoryFromCloudWatch"
    effect    = "Allow"
    resources = ["arn:${local.partition}:cloudwatch:${local.region}:${local.account_id}:alarm:*"]

    actions = [
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:DescribeAlarms",
    ]
  }

  statement {
    sid       = "AllowReadingLogsFromCloudWatch"
    effect    = "Allow"
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:*:log-stream:*"]

    actions = [
      "logs:DescribeLogGroups",
      "logs:GetLogGroupFields",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "logs:GetLogEvents",
    ]
  }

  statement {
    sid       = "AllowReadingTagsInstancesRegionsFromEC2"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
    ]
  }

  statement {
    sid       = "AllowReadingResourcesForTags"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["tag:GetResources"]
  }

  statement {
    sid    = "AllowListApsWorkspaces"
    effect = "Allow"
    resources = [
      "arn:${local.partition}:aps:${local.region}:${local.account_id}:/*",
      "arn:${local.partition}:aps:${local.region}:${local.account_id}:workspace/*",
      "arn:${local.partition}:aps:${local.region}:${local.account_id}:workspace/*/*",
    ]
    actions = [
      "aps:ListWorkspaces",
      "aps:DescribeWorkspace",
      "aps:GetMetricMetadata",
      "aps:GetSeries",
      "aps:QueryMetrics",
      "aps:RemoteWrite",
      "aps:GetLabels"
    ]
  }
}

#------------------------------------------
# Amazon Prometheus
#------------------------------------------
locals {
  amp_ingest_service_account = "amp-iamproxy-ingest-service-account"
  amp_namespace              = "kube-prometheus-stack"
}

resource "aws_prometheus_workspace" "amp" {
  count = var.enable_amazon_prometheus ? 1 : 0

  alias = format("%s-%s", "amp-ws", local.name)
  tags  = local.tags
}

module "amp_ingest_irsa" {
  count = var.enable_amazon_prometheus ? 1 : 0

  source         = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addon.git?ref=d76ba2d70ba17a36ba05b45e98a32c11e0729d9c"
  create_release = false
  create_role    = true
  create_policy  = false
  role_name      = format("%s-%s", local.name, "amp-ingest")
  role_policies  = { amp_policy = aws_iam_policy.grafana[0].arn }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = local.amp_namespace
      service_account = local.amp_ingest_service_account
    }
  }

  tags = local.tags
}


#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------
module "eks" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=76ee76e9514edc325f0d890ee787d16fa2e4905d"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  #WARNING: Avoid using this option (cluster_endpoint_public_access = true) in preprod or prod accounts. This feature is designed for sandbox accounts, simplifying cluster deployment and testing.
  cluster_endpoint_public_access       = false
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = [var.vpc_cidr]

  vpc_id = module.vpc.vpc_id
  # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the EKS Control Plane ENIs will be created
  subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
    substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
  )

  manage_aws_auth_configmap = true
  aws_auth_roles = [
    # We need to add in the Karpenter node IAM role for nodes launched by Karpenter
    {
      rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
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
    egress_vpc = {
      description = "Egress to VPC CIDRs"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = concat([var.vpc_cidr], var.secondary_cidr_blocks)
    }
    egress_cluster_api = {
      description                   = "Egress to cluster API"
      protocol                      = "tcp"
      from_port                     = 443
      to_port                       = 443
      type                          = "egress"
      source_cluster_security_group = true
    }
  }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # Not required, but used in the example to access the nodes to inspect mounted volumes
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }

    ebs_optimized = true
    # This block device is used only for root volume. Adjust volume according to your size.
    # NOTE: Don't use this volume for Spark workloads
    block_device_mappings = {
      xvda = {
        device_name = "/dev/xvda"
        ebs = {
          volume_size = 100
          volume_type = "gp3"
        }
      }
    }
  }

  eks_managed_node_groups = {
    #  We recommend to have a MNG to place your critical workloads and add-ons
    core_node_group = {
      name        = "core-node-group"
      description = "EKS managed node group example launch template"
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
      )

      min_size     = 3
      max_size     = 9
      desired_size = 3

      instance_types = ["m5.xlarge"]

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core-nodes"
      }

      tags = {
        Name          = "core-node-group"
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core-nodes"
      }
    }
  }
}


provider "aws" {
  region = local.region
}

# ECR always authenticates with `us-east-1` region
# Docs -> https://docs.aws.amazon.com/AmazonECR/latest/public/public-registries.html
provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
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

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

data "aws_availability_zones" "available" {
  filter {
    name   = "zone-id"
    values = ["usw2-az1", "usw2-az2"]
  }
}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

#---------------------------------------------------------------
# Example IAM policy for Spark job execution
#---------------------------------------------------------------
data "aws_iam_policy_document" "spark_operator" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::*"]

    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
    ]
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:*"]

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
  }
}

locals {
  name   = var.name
  region = var.region
  azs    = slice(data.aws_availability_zones.available.names, 0, 2)

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}


################################################################################
# Cluster
################################################################################

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_arn
}

output "cluster_name" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_id
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  value       = module.eks.cluster_endpoint
}

################################################################################
# Private Subnets
################################################################################

output "subnet_ids_starting_with_100" {
  description = "Secondary CIDR Private Subnet IDs for EKS Data Plane"
  value       = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null])
}

output "s3_bucket_id_spark_history_server" {
  description = "Spark History server logs S3 bucket ID"
  value       = module.s3_bucket.s3_bucket_id
}

output "s3_bucket_region_spark_history_server" {
  description = "Spark History server logs S3 bucket ID"
  value       = module.s3_bucket.s3_bucket_region
}

output "grafana_secret_name" {
  description = "Grafana password secret name"
  value       = aws_secretsmanager_secret.grafana.name
}

output "your_event_irsa_arn" {
  description = "the ARN of IRSA for argo events"
  value       = module.irsa_argo_events.iam_role_arn
}


locals {
  spark_team = "spark-team-a"
}

resource "kubernetes_namespace_v1" "spark_team_a" {
  metadata {
    name = local.spark_team
  }
  timeouts {
    delete = "15m"
  }
}

resource "kubernetes_service_account_v1" "spark_team_a" {
  metadata {
    name        = local.spark_team
    namespace   = kubernetes_namespace_v1.spark_team_a.metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.spark_team_a_irsa.iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "spark_team_a" {
  metadata {
    name      = "${local.spark_team}-secret"
    namespace = kubernetes_namespace_v1.spark_team_a.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.spark_team_a.metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.spark_team_a.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

#---------------------------------------------------------------
# IRSA for Spark driver/executor pods for "spark-team-a"
#---------------------------------------------------------------
module "spark_team_a_irsa" {
  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addon.git?ref=d76ba2d70ba17a36ba05b45e98a32c11e0729d9c"

  # Disable helm release
  create_release = false

  # IAM role for service account (IRSA)
  create_role   = true
  role_name     = "${local.name}-${local.spark_team}"
  create_policy = false
  role_policies = {
    spark_team_a_policy = aws_iam_policy.spark.arn
  }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = local.spark_team
      service_account = local.spark_team
    }
  }
}

#---------------------------------------------------------------
# Creates IAM policy for IRSA. Provides IAM permissions for Spark driver/executor pods
#---------------------------------------------------------------
resource "aws_iam_policy" "spark" {
  description = "IAM role policy for Spark Job execution"
  name        = "${local.name}-spark-irsa"
  policy      = data.aws_iam_policy_document.spark_operator.json
}

#---------------------------------------------------------------
# Kubernetes Cluster role for service Account spark-team-a
#---------------------------------------------------------------
resource "kubernetes_cluster_role" "spark_role" {
  metadata {
    name = "spark-cluster-role"
  }

  rule {
    verbs      = ["get", "list", "watch"]
    api_groups = [""]
    resources  = ["namespaces", "nodes", "persistentvolumes"]
  }

  rule {
    verbs      = ["list", "watch"]
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
  }
  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "deletecollection", "annotate", "patch", "label"]
    api_groups = [""]
    resources  = ["serviceaccounts", "services", "configmaps", "events", "pods", "pods/log", "persistentvolumeclaims"]
  }

  rule {
    verbs      = ["create", "patch", "delete", "watch"]
    api_groups = [""]
    resources  = ["secrets"]
  }

  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
    api_groups = ["apps"]
    resources  = ["statefulsets", "deployments"]
  }

  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
    api_groups = ["batch", "extensions"]
    resources  = ["jobs"]
  }

  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
    api_groups = ["extensions"]
    resources  = ["ingresses"]
  }

  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "deletecollection", "annotate", "patch", "label"]
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "role