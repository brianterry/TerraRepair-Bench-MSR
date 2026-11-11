module "this" {
  source  = "github.com/cloudposse/terraform-null-label?ref=d6d0a5b0c3ae6349c1a3c0a0a7a7f7a8f7a8f7a"

  enabled             = var.enabled
  namespace           = var.namespace
  tenant              = var.tenant
  environment         = var.environment
  stage               = var.stage
  name                = var.name
  delimiter           = var.delimiter
  attributes          = var.attributes
  tags                = var.tags
  additional_tag_map  = var.additional_tag_map
  label_order         = var.label_order
  regex_replace_chars = var.regex_replace_chars
  id_length_limit     = var.id_length_limit
  label_key_case      = var.label_key_case
  label_value_case    = var.label_value_case
  descriptor_formats  = var.descriptor_formats
  labels_as_tags      = var.labels_as_tags

  context = var.context
}

module "karpenter_crd" {
  enabled = local.enabled && var.crd_chart_enabled

  source  = "github.com/cloudposse/terraform-aws-helm-release?ref=a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t"

  name            = var.crd_chart
  chart           = var.crd_chart
  repository      = var.chart_repository
  description     = var.chart_description
  chart_version   = var.chart_version
  wait            = var.wait
  atomic          = var.atomic
  cleanup_on_fail = var.cleanup_on_fail
  timeout         = var.timeout

  create_namespace_with_kubernetes = false
  kubernetes_namespace             = join("", kubernetes_namespace.default[*].id)
  kubernetes_namespace_labels      = merge(module.this.tags, { name = join("", kubernetes_namespace.default[*].id) })

  eks_cluster_oidc_issuer_url = coalesce(replace(local.eks_cluster_identity_oidc_issuer, "https://", ""), "deleted")

  values = compact([
    yamlencode({
      fullnameOverride = module.this.name
      resources        = var.resources
      rbac = {
        create = var.rbac_enabled
      }
    }),
  ])

  context = module.this.context

  depends_on = [
    kubernetes_namespace.default
  ]
}

module "karpenter" {
  source  = "github.com/cloudposse/terraform-aws-helm-release?ref=a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t"

  chart           = var.chart
  repository      = var.chart_repository
  description     = var.chart_description
  chart_version   = var.chart_version
  wait            = var.wait
  atomic          = var.atomic
  cleanup_on_fail = var.cleanup_on_fail
  timeout         = var.timeout

  create_namespace_with_kubernetes = false
  kubernetes_namespace             = join("", kubernetes_namespace.default[*].id)
  kubernetes_namespace_labels      = merge(module.this.tags, { name = join("", kubernetes_namespace.default[*].id) })

  eks_cluster_oidc_issuer_url = coalesce(replace(local.eks_cluster_identity_oidc_issuer, "https://", ""), "deleted")

  service_account_name      = module.this.name
  service_account_namespace = join("", kubernetes_namespace.default[*].id)

  iam_role_enabled = true

  iam_policy = [{
    statements = concat([
      {
        sid       = "KarpenterController"
        effect    = "Allow"
        resources = ["*"]
        actions = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:CreateTags",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory",
          "pricing:GetProducts",
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate",
          "ec2:RunInstances",
          "iam:PassRole",
        ]
      },
      {
        sid    = "KarpenterControllerSSM"
        effect = "Allow"
        actions   = ["ssm:GetParameter"]
        resources = ["arn:aws:ssm:*:*:parameter/aws/service/*"]
      },
      {
        sid    = "KarpenterControllerClusterAccess"
        effect = "Allow"
        actions = [
          "eks:DescribeCluster"
        ]
        resources = [
          module.eks.outputs.eks_cluster_arn
        ]
      }
      ],
      local.interruption_handler_enabled ? [
        {
          sid    = "KarpenterInterruptionHandlerAccess"
          effect = "Allow"
          actions = [
            "sqs:DeleteMessage",
            "sqs:GetQueueUrl",
            "sqs:GetQueueAttributes",
            "sqs:ReceiveMessage",
          ]
          resources = [
            one(aws_sqs_queue.interruption_handler[*].arn)
          ]
        }
      ] : []
    )
  }]

  values = compact([
    yamlencode({
      fullnameOverride = module.this.name
      serviceAccount = {
        name = module.this.name
      }
      controller = {
        resources = var.resources
      }
      rbac = {
        create = var.rbac_enabled
      }
    }),
    yamlencode({
      settings = {
        aws = {
          defaultInstanceProfile = local.karpenter_iam_role_name
          clusterName            = local.eks_cluster_id
          clusterEndpoint = local.eks_cluster_endpoint
          tags            = module.this.tags
        }
      }
    }),
    yamlencode(
      local.interruption_handler_enabled ? {
        settings = {
          aws = {
            interruptionQueueName = local.interruption_handler_queue_name
          }
        }
    } : {}),
    yamlencode(var.chart_values)
  ])

  context = module.this.context

  depends_on = [
    aws_iam_instance_profile.default,
    module.karpenter_crd,
    kubernetes_namespace.default
  ]
}

module "eks" {
  source  = "github.com/cloudposse/terraform-stack-config//modules/remote-state?ref=1234567890abcdef1234567890abcdef12345678"

  component = var.eks_component_name

  context = module.this.context
}