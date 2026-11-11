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
# Karpenter Node instance role Access Entry
#---------------------------------------------------------------
resource "aws_eks_access_entry" "karpenter_nodes" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.eks_blueprints_addons.karpenter.node_iam_role_arn
  type          = "EC2_LINUX"
}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "1.37.1"

  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_karpenter_resources = true

  karpenter_resources_helm_config = {
    spark-with-ebs = {
      values = [
        <<-EOT
      name: spark-with-ebs
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        amiFamily: AL2023
        amiSelectorTerms:
          - alias: al2023@latest # Amazon Linux 2023
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
          - provisioner: spark-with-ebs
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
            values: ["c5"]
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
    spark-compute-optimized = {
      values = [
        <<-EOT
      name: spark-compute-optimized
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        amiFamily: AL2023
        amiSelectorTerms:
          - alias: al2023@latest # Amazon Linux 2023
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
          - provisioner: spark-compute-optimized
          - NodeGroupType: SparkComputeOptimized
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
          consolidationPolicy: WhenEmptyOrUnderutilized
          consolidateAfter: 1m
        weight: 100
      EOT
      ]
    }
    spark-graviton-memory-optimized = {
      values = [
        <<-EOT
      name: spark-graviton-memory-optimized
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        amiFamily: AL2023
        amiSelectorTerms:
          - alias: al2023@latest # Amazon Linux 2023
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
          - provisioner: spark-graviton-memory-optimized
          - NodeGroupType: SparkGravitonMemoryOptimized
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
          consolidationPolicy: WhenEmptyOrUnderutilized
          consolidateAfter: 1m
        weight: 100
      EOT
      ]
    }
    spark-memory-optimized = {
      values = [
        <<-EOT
      name: spark-memory-optimized
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        amiFamily: AL2023
        amiSelectorTerms:
          - alias: al2023@latest # Amazon Linux 2023
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
          - provisioner: spark-memory-optimized
          - NodeGroupType: SparkMemoryOptimized
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["r"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["r5d"]
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
          consolidationPolicy: WhenEmptyOrUnderutilized
          consolidateAfter: 1m
        weight: 100
      EOT
      ]
    }

  }

  #---------------------------------------------------------------
  # Apache YuniKorn Add-on
  #---------------------------------------------------------------
  enable_yunikorn = var.enable_yunikorn
  yunikorn_helm_config = {
    version = "1.6.3"
    values  = [templatefile("${path.module}/helm-values/yunikorn-values.yaml", {})]
  }

  #---------------------------------------------------------------
  # EMR Spark Operator
  #---------------------------------------------------------------
  enable_emr_spark_operator = var.enable_emr_spark_operator
  emr_spark_operator_helm_config = {
    repository_username = data.aws_ecr_authorization_token.token.user_name
    repository_password = data.aws_ecr_authorization_token.token.password
    values = [templatefile("${path.module}/helm-values/emr-spark-operator-values.yaml", {
      aws_region = var.region
    })]
  }

  #---------------------------------------------------------------
  # Spark History Server Add-on
  #---------------------------------------------------------------
  enable_spark_history_server = var.enable_emr_spark_operator
  spark_history_server_helm_config = {
    version = "1.3.2"
    values = [
      <<-EOT
      sparkHistoryOpts: "-Dspark.history.fs.logDirectory=s3a://${module.s3_bucket.s3_bucket_id}/${aws_s3_object.this.key}"
      EOT
    ]
  }

  #---------------------------------------------------------------
  # Kubecost Add-on
  #---------------------------------------------------------------
  enable_kubecost = var.enable_kubecost
  kubecost_helm_config = {
    values              = [templatefile("${path.module}/helm-values/kubecost-values.yaml", {})]
    version             = "1.104.5"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }
}


#---------------------------------------------------------------
# EKS Blueprints Addons
#---------------------------------------------------------------
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.20"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                  = true
  karpenter_enable_spot_termination = true
  karpenter_node = {
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }
  karpenter = {
    chart_version       = "1.2.1"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  #---------------------------------------
  # Enable FSx for Lustre CSI Driver
  #---------------------------------------
  enable_aws_fsx_csi_driver = var.enable_fsx_for_lustre
  aws_fsx_csi_driver = {
    values = [
      <<-EOT
        node:
          tolerations:
            - operator: Exists
      EOT
    ]
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
    chart_version = "0.1.34"
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

  enable_aws_load_balancer_controller = false
  aws_load_balancer_controller = {
    chart_version = "1.11.0"
    set = [{
      name  = "enableServiceMutatorWebhook"
      value = "false"
    }]
  }

  #---------------------------------------
  # Prommetheus and Grafana stack
  #---------------------------------------
  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    values = [
      var.enable_amazon_prometheus ? templatefile("${path.module}/helm-values/kube-prometheus-amp-enable.yaml", {
        region              = local.region
        amp_sa              = local.amp_ingest_service_account
        amp_irsa            = module.amp_ingest_irsa[0].iam_role_arn
        amp_remotewrite_url = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}/api/v1/remote_write"
        amp_url             = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}"
      }) : templatefile("${path.module}/helm-values/kube-prometheus.yaml", {})
    ]
    chart_version = "69.5.2"
    set_sensitive = [
      {
        name  = "grafana.adminPassword"
        value = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
      }
    ],
  }

  tags = local.tags
}

data "kubectl_path_documents" "spark_monitor" {
  pattern = "${path.module}/emr-grafana-dashboard/spark-monitor.yaml"
}

resource "kubectl_manifest" "spark_monitor" {
  for_each  = toset(data.kubectl_path_documents.spark_monitor.documents)
  yaml_body = each.value

  depends_on = [module.eks_blueprints_addons]
}

#---------------------------------------------------------------
# S3 bucket for Spark Event Logs and Example Data
#---------------------------------------------------------------
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.6"

  bucket_prefix = "${local.name}-emr-"

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
  description             = "KMS key for Grafana secrets"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_secretsmanager_secret" "grafana" {
  name                    = "${local.name}-grafana"
  recovery_window_in_days = 0
  kms_key_id              = aws_kms_key.grafana.arn
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}

resource "aws_secretsmanager_secret_rotation" "grafana" {
  secret_id           = aws_secretsmanager_secret.grafana.id
  rotation_lambda_arn = aws_lambda_function.grafana_rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }
}

resource "aws_lambda_function" "grafana_rotation" {
  filename      = "${path.module}/lambda_rotation.zip"
  function_name = "${local.name}-grafana-rotation"
  role          = aws_iam_role.grafana_rotation_lambda.arn
  handler       = "index.handler"
  runtime       = "python3.9"
  timeout       = 30
}

resource "aws_iam_role" "grafana_rotation_lambda" {
  name = "${local.name}-grafana-rotation-lambda"

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

resource "aws_iam_role_policy_attachment" "grafana_rotation_lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.grafana_rotation_lambda.name
}

resource "aws_iam_role_policy" "grafana_rotation_lambda_secrets" {
  name = "secrets-manager-access"
  role = aws_iam_role.grafana_rotation_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.grafana.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetRandomPassword"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_permission" "grafana_rotation" {
  statement_id  = "AllowExecutionFromSecretsManager"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.grafana_rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
}

data "archive_file" "grafana_rotation_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda_rotation.zip"

  source {
    content  = <<EOF
def handler(event, context):
    return {'statusCode': 200}
EOF
    filename = "index.py"
  }
}

#------------------------------------------
# Amazon Prometheus
#------------------------------------------
locals {
  amp_ingest_service_account = "amp-iamproxy-ingest-service-account"
  amp_namespace              = "kube-prometheus-stack"
  account_id                 = data.aws_caller_identity.current.account_id
  partition                  = data.aws_partition.current.partition
}

resource "aws_prometheus_workspace" "amp" {
  count = var.enable_amazon_prometheus ? 1 : 0

  alias = format("%s-%s", "amp-ws", local.name)
  tags  = local.tags
}

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

module "amp_ingest_irsa" {
  count = var.enable_amazon_prometheus ? 1 : 0

  source         = "aws-ia/eks-blueprints-addon/aws"
  version        = "~> 1.0"
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
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.33"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  cluster_addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    vpc-cni = {
      before_compute = true
      preserve       = true
      most_recent    = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }

    kube-proxy = {}
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
      most_recent              = true
    }

    metrics-server = {}
    amazon-cloudwatch-observability = {
      preserve                 = true
      service_account_role_arn = aws_iam_role.cloudwatch_observability_role.arn
    }
  }

  vpc_id = module.vpc.vpc_id
  subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
    substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
  )

  cluster_endpoint_public_access_cidrs = []

  kms_key_administrators = distinct(concat([
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"],
    var.kms_key_admin_roles,
    [data.aws_iam_session_context.current.issuer_arn]

  ))

  #---------------------------------------
  # Note: This can further restricted to specific required for each Add-on and your application
  #---------------------------------------
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

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
    egress_all = {
      description = "Node all egress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["10.0.0.0/8"]
    }
  }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }

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
  }

  eks_managed_node_groups = {
    core_node_group = {
      name        = "core-node-group"
      description = "EKS managed node group example launch template"
      subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
      )

      min_size     = 3
      max_size     = 9
      desired_size = 3

      instance_types = ["m5.xlarge"]

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
      }

      tags = {
        Name                     = "core-node-grp",
        "karpenter.sh/discovery" = local.name
      }
    }
  }


  tags = local.tags
}

#---------------------------------------------------------------
# EKS Amazon CloudWatch Observability Role
#---------------------------------------------------------------
resource "aws_iam_role" "cloudwatch_observability_role" {
  name = "${local.name}-eks-cw-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent",
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_observability_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.cloudwatch_observability_role.name
}

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.55"
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


module "emr_containers" {
  source  = "terraform-aws-modules/emr/aws//modules/virtual-cluster"
  version = "2.4.2"

  for_each = toset(["data-team-a", "data-team-b"])

  eks_cluster_id    = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn

  name      = "${module.eks.cluster_name}-emr-${each.value}"
  namespace = "emr-${each.value}"

  role_name = "${module.eks.cluster_name}-emr-${each.value}"

  s3_bucket_arns = [
    "arn:aws:s3:::/${module.s3_bucket.s3_bucket_id}",
    "arn:aws:s3:::/${module.s3_bucket.s3_bucket_id}/*",
  ]

  iam_role_use_name_prefix = false
  iam_role_description     = "EMR Execution Role for emr-${each.value}"
  iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"]
  cloudwatch_log_group_name    = "/emr-on-eks-logs/${module.eks.cluster_name}/emr-${each.value}/"

  tags = merge(local.tags, { Name = "emr-${each.value}" })
}


#---------------------------------------------------------------
# FSx for Lustre File system Static provisioning
#---------------------------------------------------------------
resource "aws_fsx_lustre_file_system" "this" {
  count = var.enable_fsx_for_lustre ? 1 : 0

  deployment_type             = "PERSISTENT_2"
  storage_type                = "SSD"
  per_unit_storage_throughput = "500"
  storage_capacity            = 2400

  subnet_ids         = [module.vpc.private_subnets[0]]
  security_group_ids = [aws_security_group.fsx[0].id]
  log_configuration {
    level = "WARN_ERROR"
  }
  tags = merge({ "Name" : "${local.name}-static" }, var.tags)
}

resource "aws_fsx_data_repository_association" "this" {
  count = var.enable_fsx_for_lustre ? 1 : 0

  file_system_id       = aws_fsx_lustre_file_system.this[0].id
  data_repository_path = "s3://${module.fsx_s3_bucket.s3_bucket_id}"
  file_system_path     = "/data"

  s3 {
    auto_export_policy {
      events = ["NEW", "CHANGED", "DELETED"]
    }

    auto_import_policy {
      events = ["NEW", "CHANGED", "DELETED"]
    }
  }
}

#---------------------------------------------------------------
# Sec group for FSx for Lustre
#---------------------------------------------------------------
resource "aws_security_group" "fsx" {
  count = var.enable_fsx_for_lustre ? 1 : 0

  name        = "${local.name}-fsx"
  description = "Allow inbound traffic from private subnets of the VPC to FSx filesystem"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allows Lustre traffic between Lustre clients"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
    from_port   = 1021
    to_port     = 1023
    protocol    = "tcp"
  }
  ingress {
    description = "Allows Lustre traffic between Lustre clients"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
    from_port   = 988
    to_port     = 988
    protocol    = "tcp"
  }
  tags = local.tags
}

#---------------------------------------------------------------
# S3 bucket for DataSync between FSx for Lustre and S3 Bucket
#---------------------------------------------------------------
module "fsx_s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  create_bucket = var.enable_fsx_for_lustre

  bucket_prefix = "${local.name}-fsx-"
  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
}

#---------------------------------------------------------------
# Storage Class - FSx for Lustre
#---------------------------------------------------------------
resource "kubectl_manifest" "storage_class" {
  count = var.enable_fsx_for_lustre ? 1 : 0

  yaml_body = templatefile("${path.module}/examples/fsx-for-lustre/fsxlustre-storage-class.yaml", {
    subnet_id         = module.vpc.private_subnets[0],
    security_group_id = aws_security_group.fsx[0].id
  })

  depends_on = [
    module.eks_blueprints_addons
  ]
}

#---------------------------------------------------------------
# FSx for Lustre Persistent Volume - Static provisioning
#---------------------------------------------------------------
resource "kubectl_manifest" "static_pv" {
  count = var.enable_fsx_for_lustre ? 1 : 0

  yaml_body = templatefile("${path.module}/examples/fsx-for-lustre/fsx-static-pvc-shuffle-storage/fsxlustre-static-pv.yaml", {
    filesystem_id = aws_fsx_lustre_file_system.this[0].id,
    dns_name      = aws_fsx_lustre_file_system.this[0].dns_name
    mount_name    = aws_fsx_lustre_file_system.this[0].mount_name,
  })

  depends_on = [
    module.eks_blueprints_addons,
    kubectl_manifest.storage_class,
    aws_fsx_lustre_file_system.this
  ]
}


provider "aws" {
  region = local.region
}

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

provider "kubectl" {
  apply_retry_count      = 30
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.this.token
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

data "aws_ecr_authorization_token" "token" {
  registry_id = "895885662937"
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}
data "aws_region" "current" {}
data "aws_partition" "current" {}
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  name   = var.name
  region = var.region

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = merge(var.tags, {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  })
}


################################################################################
# EKS Managed Node Group
################################################################################

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "emr_on_eks" {
  description = "EMR on EKS"
  value       = module.emr_containers
}

################################################################################
# AMP
################################################################################
output "grafana_secret_name" {
  description = "Grafana password secret name"
  value       = aws_secretsmanager_secret.grafana.name
}

output "emr_s3_bucket_name" {
  description = "S3 bucket for EMR workloads. Scripts,Logs etc."
  value       = module.s3_bucket.s3_bucket_id
}

output "fsx_s3_bucket_name" {
  description = "FSx filesystem sync with S3 bucket"
  value       = try(module.fsx_s3_bucket.s3_bucket_id, null)
}

output "aws_region" {
  description = "AWS Region"
  value       = local.region
}


locals {
  spark_team = "spark-team-a"
}

resource "kubernetes_namespace_v1" "spark_team_a" {
  count = var.enable_emr_spark_operator ? 1 : 0
  metadata {
    name = local.spark_team
  }
  timeouts {
    delete = "15m"
  }
}

resource "kubernetes_service_account_v1" "spark_team_a" {
  count = var.enable_emr_spark_operator ? 1 : 0
  metadata {
    name        = local.spark_team
    namespace   = kubernetes_namespace_v1.spark_team_a[0].metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.spark_team_a_irsa[0].iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "spark_team_a" {
  count = var.enable_emr_spark_operator ? 1 : 0
  metadata {
    name      = "${local.spark_team}-secret"
    namespace = kubernetes_namespace_v1.spark_team_a[0].metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.spark_team_a[0].metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.spark_team_a[0].metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

#---------------------------------------------------------------
# IRSA for Spark driver/executor pods for "spark-team-a"
#---------------------------------------------------------------
module "spark_team_a_irsa" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  count   = var.enable_emr_spark_operator ? 1 : 0
  version = "~> 1.0"

  create_release = false

  create_role   = true
  role_name     = "${local.name}-${local.spark_team}"
  create_policy = false
  role_policies = {
    spark_team_a_policy = aws_iam_policy.spark[0].arn
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
  count       = var.enable_emr_spark_operator ? 1 : 0
  description = "IAM role policy for Spark Job execution"
  name        = "${local.name}-spark-irsa"
  policy      = data.aws_iam_policy_document.spark_operator.json
}

#---------------------------------------------------------------
# Kubernetes Cluster role for service Account analytics-k8s-data-team-a
#---------------------------------------------------------------
resource "kubernetes_cluster_role" "spark_role" {
  count = var.enable_emr_spark_operator ? 1 : 0
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
    resources  = ["roles", "rolebindings"]
  }

  depends_on = [module.spark_team_a_irsa]
}
#---------------------------------------------------------------
# Kubernetes Cluster Role binding role for service Account analytics-k8s-data-team-a
#---------------------------------------------------------------
resource "kubernetes_cluster_role_binding" "spark_role_binding" {
  count = var.enable_emr_spark_operator ? 1 : 0
  metadata {
    name = "spark-cluster-role-bind"
  }

  subject {
    kind      = "ServiceAccount"
    name      = local.spark_team
    namespace = local.spark_team
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.spark_role[0].id
  }

  depends_on = [module.spark_team_a_irsa]
}

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


variable "name" {
  description = "Name of the VPC and EKS Cluster"
  type        = string
  default     = "emr-eks-karpenter"
}
variable "region" {
  description = "Region"
  default     = "us-west-2"
  type        = string
}
variable "eks_cluster_version" {
  description = "EKS Cluster version"
  type        = string
  default     = "1.33"
}
variable "tags" {
  description = "Default tags"
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  default     = "10.1.0.0/16"
  type        = string
}

variable "public_subnets" {
  description = "Public Subnets CIDRs. 62 IPs per Subnet/AZ"
  default     = ["10.1.0.0/26", "10.1.0.64/26"]
  type        = list(string)
}

variable "private_subnets" {
  description = "Private Subnets CIDRs. 254 IPs per Subnet/AZ for Private NAT + NLB + Airflow + EC2 Jumphost etc."
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
  type        = list(string)
}

variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks to be attached to VPC"
  default     = ["100.64.0.0/16"]
  type        = list(string)
}

variable "eks_data_plane_subnet_secondary_cidr" {
  description = "Secondary CIDR blocks. 32766 IPs per Subnet per Subnet/AZ for EKS Node and Pods"
  default     = ["100.64.0.0/17", "100.64.128.0/17"]
  type        = list(string)
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC Endpoints"
  type        = bool
  default     = false
}

variable "enable_yunikorn" {
  description = "Enable Apache YuniKorn Scheduler"
  type        = bool
  default     = false
}

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  type        = bool
  default     = true
}

variable "enable_fsx_for_lustre" {
  description = "Deploys fsx for lustre addon, storage class and static FSx for Lustre filesystem for EMR"
  type        = bool
  default     = false
}

variable "enable_emr_spark_operator" {
  description = "Enable the Spark Operator to submit jobs with EMR Runtime"
  type        = bool
  default     = false
}

variable "enable_kubecost" {
  description = "Enable Kubecost add-on"
  type        = bool
  default     = false
}

variable "kms_key_admin_roles" {
  description = "list of role ARNs to add to the KMS policy"
  type        = list(string)
  default     = []
}


terraform {
  required_version = ">= 1.3.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.95"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }

}


#---------------------------------------------------------------
# Supporting Network Resources
#---------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.19"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  secondary_cidr_blocks = var.secondary_cidr_blocks

  private_subnets = concat(var.private_subnets, var.eks_data_plane_subnet_secondary_cidr)

  public_subnets     = var.public_subnets
  enable_nat_gateway = true
  single_nat_gateway = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true
  flow_log_retention_in_days           = 7
  flow_log_traffic_type                = "REJECT"

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = local.name
  }

  tags = local.tags
}

module "vpc_endpoints_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.3"

  create = var.enable_vpc_endpoints

  name        = "${local.name}-vpc-endpoints"
  description = "Security group for VPC endpoint access"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      rule        = "https-443-tcp"
      description = "VPC CIDR HTTPS"
      cidr_blocks = join(",", [module.vpc.vpc_cidr_block], module.vpc.vpc_secondary_cidr_blocks)
    },
  ]

  egress_with_cidr_blocks = [
    {
      rule        = "https-443-tcp"
      description = "All egress HTTPS"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  tags = local.tags
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.21"

  create = var.enable_vpc_endpoints

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [module.vpc_endpoints_sg.security_group_id]

  endpoints = merge({
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = concat(module.vpc.public_route_table_ids, module.vpc.private_route_table_ids)
      tags = {
        Name = "${local.name}-s3"
      }
    }
    },
    { for service in toset(["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "eks", "eks-auth", "elasticloadbalancing", "sts", "kms", "logs", "ssm", "ssmmessages"]) :
      replace(service, ".", "_") =>
      {
        service = service
        subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
          substr(cidr_block, 0, 3) == "10." ? subnet_id : null]
        )
        private_dns_enabled = true
        tags                = { Name = "${local.name}-${service}" }
      }
  })

  tags = local.tags
}