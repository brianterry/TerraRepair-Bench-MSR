module "this" {
  source  = "cloudposse/label/null#v0.25.0"
  version = "0.25.0"

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

variable "context" {
  type = any
  default = {
    enabled             = true
    namespace           = null
    tenant              = null
    environment         = null
    stage               = null
    name                = null
    delimiter           = null
    attributes          = []
    tags                = {}
    additional_tag_map  = {}
    regex_replace_chars = null
    label_order         = []
    id_length_limit     = null
    label_key_case      = null
    label_value_case    = null
    descriptor_formats  = {}
    labels_as_tags = ["unset"]
  }
  description = <<-EOT
    Single object for setting entire context at once.
    See description of individual variables for details.
    Leave string and numeric variables as `null` to use default value.
    Individual variable settings (non-null) override settings in context object,
    except for attributes, tags, and additional_tag_map, which are merged.
  EOT

  validation {
    condition     = lookup(var.context, "label_key_case", null) == null ? true : contains(["lower", "title", "upper"], var.context["label_key_case"])
    error_message = "Allowed values: `lower`, `title`, `upper`."
  }

  validation {
    condition     = lookup(var.context, "label_value_case", null) == null ? true : contains(["lower", "title", "upper", "none"], var.context["label_value_case"])
    error_message = "Allowed values: `lower`, `title`, `upper`, `none`."
  }
}

variable "enabled" {
  type        = bool
  default     = null
  description = "Set to false to prevent the module from creating any resources"
}

variable "namespace" {
  type        = string
  default     = null
  description = "ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique"
}

variable "tenant" {
  type        = string
  default     = null
  description = "ID element _(Rarely used, not included by default)_. A customer identifier, indicating who this instance of a resource is for"
}

variable "environment" {
  type        = string
  default     = null
  description = "ID element. Usually used for region e.g. 'uw2', 'us-west-2', OR role 'prod', 'staging', 'dev', 'UAT'"
}

variable "stage" {
  type        = string
  default     = null
  description = "ID element. Usually used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release'"
}

variable "name" {
  type        = string
  default     = null
  description = <<-EOT
    ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.
    This is the only ID element not also included as a `tag`.
    The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input.
  EOT
}

variable "delimiter" {
  type        = string
  default     = null
  description = <<-EOT
    Delimiter to be used between ID elements.
    Defaults to `-` (hyphen). Set to `""` to use no delimiter at all.
  EOT
}

variable "attributes" {
  type        = list(string)
  default     = []
  description = <<-EOT
    ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,
    in the order they appear in the list. New attributes are appended to the
    end of the list. The elements of the list are joined by the `delimiter`
    and treated as a single ID element.
  EOT
}

variable "labels_as_tags" {
  type        = set(string)
  default     = ["default"]
  description = <<-EOT
    Set of labels (ID elements) to include as tags in the `tags` output.
    Default is to include all labels.
    Tags with empty values will not be included in the `tags` output.
    Set to `[]` to suppress all generated tags.
    **Notes:**
      The value of the `name` tag, if included, will be the `id`, not the `name`.
      Unlike other `null-label` inputs, the initial setting of `labels_as_tags` cannot be
      changed in later chained modules. Attempts to change it will be silently ignored.
  EOT
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).
    Neither the tag keys nor the tag values will be modified by this module.
  EOT
}

variable "additional_tag_map" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.
    This is for some rare cases where resources want additional configuration of tags
    and therefore take a list of maps with tag key, value, and additional configuration.
  EOT
}

variable "label_order" {
  type        = list(string)
  default     = null
  description = <<-EOT
    The order in which the labels (ID elements) appear in the `id`.
    Defaults to ["namespace", "environment", "stage", "name", "attributes"].
    You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present.
  EOT
}

variable "regex_replace_chars" {
  type        = string
  default     = null
  description = <<-EOT
    Terraform regular expression (regex) string.
    Characters matching the regex will be removed from the ID elements.
    If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits.
  EOT
}

variable "id_length_limit" {
  type        = number
  default     = null
  description = <<-EOT
    Limit `id` to this many characters (minimum 6).
    Set to `0` for unlimited length.
    Set to `null` for keep the existing setting, which defaults to `0`.
    Does not affect `id_full`.
  EOT
  validation {
    condition     = var.id_length_limit == null ? true : var.id_length_limit >= 6 || var.id_length_limit == 0
    error_message = "The id_length_limit must be >= 6 if supplied (not null), or 0 for unlimited length."
  }
}

variable "label_key_case" {
  type        = string
  default     = null
  description = <<-EOT
    Controls the letter case of the `tags` keys (label names) for tags generated by this module.
    Does not affect keys of tags passed in via the `tags` input.
    Possible values: `lower`, `title`, `upper`.
    Default value: `title`.
  EOT

  validation {
    condition     = var.label_key_case == null ? true : contains(["lower", "title", "upper"], var.label_key_case)
    error_message = "Allowed values: `lower`, `title`, `upper`."
  }
}

variable "label_value_case" {
  type        = string
  default     = null
  description = <<-EOT
    Controls the letter case of ID elements (labels) as included in `id`,
    set as tag values, and output by this module individually.
    Does not affect values of tags passed in via the `tags` input.
    Possible values: `lower`, `title`, `upper` and `none` (no transformation).
    Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.
    Default value: `lower`.
  EOT

  validation {
    condition     = var.label_value_case == null ? true : contains(["lower", "title", "upper", "none"], var.label_value_case)
    error_message = "Allowed values: `lower`, `title`, `upper`, `none`."
  }
}

variable "descriptor_formats" {
  type        = any
  default     = {}
  description = <<-EOT
    Describe additional descriptors to be output in the `descriptors` output map.
    Map of maps. Keys are names of descriptors. Values are maps of the form
    `{
       format = string
       labels = list(string)
    }`
    (Type is `any` so the map values can later be enhanced to provide additional options.)
    `format` is a Terraform format string to be passed to the `format()` function.
    `labels` is a list of labels, in order, to pass to `format()` function.
    Label values will be normalized before being passed to `format()` so they will be
    identical to how they appear in `id`.
    Default is `{}` (`descriptors` output will be empty).
  EOT
}

locals {
  controller_policy_v1alpha_json = <<-EndOfPolicy
        {
          "Version": "2012-10-17",
          "Statement": [
            {
              "Sid": "AllowScopedDeletionV1alpha",
              "Effect": "Allow",
              "Resource": [
                "arn:${local.aws_partition}:ec2:${var.region}:*:instance/*",
                "arn:${local.aws_partition}:ec2:${var.region}:*:launch-template/*"
              ],
              "Action": [
                "ec2:TerminateInstances",
                "ec2:DeleteLaunchTemplate"
              ],
              "Condition": {
                "StringEquals": {
                  "ec2:ResourceTag/karpenter.k8s.aws/cluster": "${local.eks_cluster_id}"
                },
                "StringLike": {
                  "ec2:ResourceTag/karpenter.sh/provisioner-name": "*"
                }
              }
            },
            {
              "Sid": "AllowScopedInstanceProfileActionsV1alpha",
              "Effect": "Allow",
              "Resource": "*",
              "Action": [
                "iam:AddRoleToInstanceProfile",
                "iam:RemoveRoleFromInstanceProfile",
                "iam:DeleteInstanceProfile"
              ],
              "Condition": {
                "StringEquals": {
                  "aws:ResourceTag/kubernetes.io/cluster/${local.eks_cluster_id}": "owned",
                  "aws:ResourceTag/topology.kubernetes.io/region": "${var.region}"
                },
                "ArnEquals": {
                   "ec2:InstanceProfile": "${replace(local.karpenter_node_role_arn, "role", "instance-profile")}"
                }
              }
            }
          ]
        }
  EndOfPolicy
}

resource "aws_iam_policy" "v1alpha" {
  count = local.enabled ? 1 : 0

  name        = "${module.this.id}-v1alpha"
  description = "Legacy Karpenter controller policy for v1alpha workloads"
  policy      = local.controller_policy_v1alpha_json
  tags        = module.this.tags
}

resource "aws_iam_role_policy_attachment" "v1alpha" {
  count = local.enabled ? 1 : 0

  role       = module.karpenter.service_account_role_name
  policy_arn = one(aws_iam_policy.v1alpha[*].arn)
}

locals {
  controller_policy_json = <<-EndOfPolicy
        {
          "Version": "2012-10-17",
          "Statement": [
            {
              "Sid": "AllowScopedEC2InstanceAccessActions",
              "Effect": "Allow",
              "Resource": [
                "arn:${local.aws_partition}:ec2:${var.region}::image/*",
                "arn:${local.aws_partition}:ec2:${var.region}::snapshot/*",
                "arn:${local.aws_partition}:ec2:${var.region}:*:security-group/*",
                "arn:${local.aws_partition}:ec2:${var.region}:*:subnet/*"
              ],
              "Action": [
                "ec2:RunInstances",
                "ec2:CreateFleet"
              ]
            },
            {
              "Sid": "AllowScopedEC2LaunchTemplateAccessActions",
              "Effect": "Allow",
              "Resource": "arn:${local.aws_partition}:ec2:${var.region}:*:launch-template/*",
              "Action": [
                "ec2:RunInstances",
                "ec2:CreateFleet"
              ],
              "Condition": {
                "StringEquals": {
                  "aws:ResourceTag/kubernetes.io/cluster/${local.eks_cluster_id}": "owned"
                },
                "StringLike": {
                  "aws:ResourceTag/karpenter.sh/nodepool": "*"
                }
              }
            },
            {
              "Sid": "AllowScopedEC2InstanceActionsWithTags",
              "Effect": "Allow",
              "Resource": [
                "arn:${local.aws_partition}:ec2:${var.region}:*:fleet/*",
                "arn:${local.aws_partition}:ec2:${var.region}:*:instance/*",
                "arn:${local.aws_partition}:ec2:${var.region}:*:volume/*",
                "arn:${local.aws_partition}:ec2:${var.region}:*:network-interface/*",
                "arn:${local.aws_partition}:ec2:${var.region}:*:launch-template/*",
                "arn:${local.aws_partition}:ec2:${var.region}:*:spot-instances-request/*"
              ],
              "Action": [
                "ec2:RunInstances",
                "ec2:CreateFleet",
                "ec2:CreateLaunchTemplate"
              ],
              "Condition": {
                "StringEquals": {
                  "aws:RequestTag/kubernetes.io/cluster/${local.eks_cluster_id}": "owned"
                },
                "StringLike": {
                  "aws:RequestTag/karpenter.sh/nodepool": "*"
                }
              }
            },
            {
              "Sid": "AllowScopedResourceCreationTagging",
              "Effect": "Allow",
              "Resource": [
                "arn:${local.aws_partition}:ec2:${var.region}:*:fleet/*",
                "arn:${local.aws_partition}:ec2:${var.region}:*:instance/*",
                "arn:${local.aws_partition}:ec2:${var.region}:*:volume/*",
                "arn:${local.aws_partition}:ec2:${var.region}:*:network-interface/*",
                "arn:${local.aws_partition}:ec2:${var.region}:*:launch-template/*",
                "arn:${local.aws_partition}:ec2:${var.region}:*:spot-instances-request/*"
              ],
              "Action": "ec2:CreateTags",
              "Condition": {
                "StringEquals": {
                  "aws:RequestTag/kubernetes.io/cluster/${local.eks_cluster_id}": "owned",
                  "ec2:CreateAction": [
                    "RunInstances",
                    "CreateFleet",
                    "CreateLaunchTemplate"
                  ]
                },
                "StringLike": {
                  "aws:RequestTag/karpenter.sh/nodepool": "*"
                }
              }
            },
            {
              "Sid": "AllowScopedResourceTagging",
              "Effect": "Allow",
              "Resource": "arn:${local.aws_partition}:ec2:${var.region}:*:instance/*",
              "Action": "ec2:CreateTags",
              "Condition": {
                "StringEquals": {
                  "aws:ResourceTag/kubernetes.io/cluster/${local.eks_cluster_id}": "owned"
                },
                "StringLike": {
                  "aws:ResourceTag/karpenter.sh/nodepool": "*"
                },
                "ForAllValues:StringEquals": {
                  "aws:TagKeys": [
                    "karpenter.sh/nodeclaim",
                    "Name"
                  ]
                }
              }
            },
            {
              "Sid": "AllowScopedDeletion",
              "Effect": "Allow",
              "Resource": [
                "arn:${local.aws_partition}:ec2:${var.region}:*:instance/*",
                "arn:${local.aws_partition}:ec2:${var.region}:*:launch-template/*"
              ],
              "Action": [
                "ec2:TerminateInstances",
                "ec2:DeleteLaunchTemplate"
              ],
              "Condition": {
                "StringEquals": {
                  "aws:ResourceTag/kubernetes.io/cluster/${local.eks_cluster_id}": "owned"
                },
                "StringLike": {
                  "aws:ResourceTag/karpenter.sh/nodepool": "*"
                }
              }
            },
            {
              "Sid": "AllowRegionalReadActions",
              "Effect": "Allow",
              "Resource": "*",
              "Action": [
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeImages",
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceTypeOfferings",
                "ec2:DescribeInstanceTypes",
                "ec2:DescribeLaunchTemplates",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSpotPriceHistory",
                "ec2:DescribeSubnets"
              ],
              "Condition": {
                "StringEquals": {
                  "aws:RequestedRegion": "${var.region}"
                }
              }
            },
            {
              "Sid": "AllowSSMReadActions",
              "Effect": "Allow",
              "Resource": "arn:${local.aws_partition}:ssm:${var.region}::parameter/aws/service/*",
              "Action": "ssm:GetParameter"
            },
            {
              "Sid": "AllowPricingReadActions",
              "Effect": "Allow",
              "Resource": "*",
              "Action": "pricing:GetProducts"
            },
            %{if local.interruption_handler_enabled}
            {
              "Sid": "AllowInterruptionQueueActions",
              "Effect": "Allow",
              "Resource": "${local.interruption_handler_queue_arn}",
              "Action": [
                "sqs:DeleteMessage",
                "sqs:GetQueueUrl",
                "sqs:ReceiveMessage"
              ]
            },
            %{endif}
            {
              "Sid": "AllowPassingInstanceRole",
              "Effect": "Allow",
              "Resource": "${local.karpenter_node_role_arn}",
              "Action": "iam:PassRole",
              "Condition": {
                "StringEquals": {
                  "iam:PassedToService": "ec2.amazonaws.com"
                }
              }
            },
            {
              "Sid": "AllowScopedInstanceProfileCreationActions",
              "Effect": "Allow",
              "Resource": "*",
              "Action": [
                "iam:CreateInstanceProfile"
              ],
              "Condition": {
                "StringEquals": {
                  "aws:RequestTag/kubernetes.io/cluster/${local.eks_cluster_id}": "owned",
                  "aws:RequestTag/topology.kubernetes.io/region": "${var.region}"
                },
                "StringLike": {
                  "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass": "*"
                }
              }
            },
            {
              "Sid": "AllowScopedInstanceProfileTagActions",
              "Effect": "Allow",
              "Resource": "*",
              "Action": [
                "iam:TagInstanceProfile"
              ],
              "Condition": {
                "StringEquals": {
                  "aws:ResourceTag/kubernetes.io/cluster/${local.eks_cluster_id}": "owned",
                  "aws:ResourceTag/topology.kubernetes.io/region": "${var.region}",
                  "aws:RequestTag/kubernetes.io/cluster/${local.eks_cluster_id}": "owned",
                  "aws:RequestTag/topology.kubernetes.io/region": "${var.region}"
                },
                "StringLike": {
                  "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass": "*",
                  "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass": "*"
                }
              }
            },
            {
              "Sid": "AllowScopedInstanceProfileActions",
              "Effect": "Allow",
              "Resource": "*",
              "Action": [
                "iam:AddRoleToInstanceProfile",
                "iam:RemoveRoleFromInstanceProfile",
                "iam:DeleteInstanceProfile"
              ],
              "Condition": {
                "StringEquals": {
                  "aws:ResourceTag/kubernetes.io/cluster/${local.eks_cluster_id}": "owned",
                  "aws:ResourceTag/topology.kubernetes.io/region": "${var.region}"
                },
                "StringLike": {
                  "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass": "*"
                }
              }
            },
            {
              "Sid": "AllowInstanceProfileReadActions",
              "Effect": "Allow",
              "Resource": "*",
              "Action": "iam:GetInstanceProfile"
            },
            {
              "Sid": "AllowAPIServerEndpointDiscovery",
              "Effect": "Allow",
              "Resource": "${local.eks_cluster_arn}",
              "Action": "eks:DescribeCluster"
            }
          ]
        }
  EndOfPolicy
}

locals {
  interruption_handler_enabled    = local.enabled && var.interruption_handler_enabled
  interruption_handler_queue_name = module.this.id
  interruption_handler_queue_arn  = one(aws_sqs_queue.interruption_handler[*].arn)

  dns_suffix = join("", data.aws_partition.current[*].dns_suffix)

  events = {
    health_event = {
      name        = "HealthEvent"
      description = "Karpenter interrupt - AWS health event"
      event_pattern = {
        source      = ["aws.health"]
        detail-type = ["AWS Health Event"]
      }
    }
    spot_interupt = {
      name        = "SpotInterrupt"
      description = "Karpenter interrupt - EC2 spot instance interruption warning"
      event_pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Spot Instance Interruption Warning"]
      }
    }
    instance_rebalance = {
      name        = "InstanceRebalance"
      description = "Karpenter interrupt - EC2 instance rebalance recommendation"
      event_pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance Rebalance Recommendation"]
      }
    }
    instance_state_change = {
      name        = "InstanceStateChange"
      description = "Karpenter interrupt - EC2 instance state-change notification"
      event_pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance State-change Notification"]
      }
    }
  }
}

resource "aws_sqs_queue" "interruption_handler" {
  count = local.interruption_handler_enabled ? 1 : 0

  name                      = local.interruption_handler_queue_name
  message_retention_seconds = var.interruption_queue_message_retention
  sqs_managed_sse_enabled   = true

  tags = module.this.tags
}

data "aws_iam_policy_document" "interruption_handler" {
  count = local.interruption_handler_enabled ? 1 : 0

  statement {
    sid       = "SqsWrite"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption_handler[0].arn]

    principals {
      type = "Service"
      identifiers = [
        "events.${local.dns_suffix}",
        "sqs.${local.dns_suffix}",
      ]
    }
  }
}

resource "aws_sqs_queue_policy" "interruption_handler" {
  count = local.interruption_handler_enabled ? 1 : 0

  queue_url = aws_sqs_queue.interruption_handler[0].url
  policy    = data.aws_iam_policy_document.interruption_handler[0].json
}

resource "aws_cloudwatch_event_rule" "interruption_handler" {
  for_each = { for k, v in local.events : k => v if local.interruption_handler_enabled }

  name          = "${module.this.id}-${each.value.name}"
  description   = each.value.description
  event_pattern = jsonencode(each.value.event_pattern)

  tags = module.this.tags
}

resource "aws_cloudwatch_event_target" "interruption_handler" {
  for_each = { for k, v in local.events : k => v if local.interruption_handler_enabled }

  rule      = aws_cloudwatch_event_rule.interruption_handler[each.key].name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.interruption_handler[0].arn
}

locals {
  enabled = module.this.enabled

  aws_partition = coalesce(one(data.aws_partition.current[*].partition), "aws")

  eks_cluster_arn                  = module.eks.outputs.eks_cluster_arn
  eks_cluster_identity_oidc_issuer = module.eks.outputs.eks_cluster_identity_oidc_issuer

  karpenter_node_role_arn = module.eks.outputs.karpenter_iam_role_arn

  kubernetes_namespace = "kube-system"
}

data "aws_partition" "current" {
  count = local.enabled ? 1 : 0
}

module "karpenter_crd" {
  source  = "cloudposse/helm-release/aws#v0.10.1"
  version = "0.10.1"

  enabled = local.enabled && var.crd_chart_enabled

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
  kubernetes_namespace             = local.kubernetes_namespace

  eks_cluster_oidc_issuer_url = coalesce(replace(local.eks_cluster_identity_oidc_issuer, "https://", ""), "deleted")

  context = module.this.context
}

module "karpenter" {
  source  = "cloudposse/helm-release/aws#v0.10.1"
  version = "0.10.1"

  chart           = var.chart
  repository      = var.chart_repository
  description     = var.chart_description
  chart_version   = var.chart_version
  wait            = var.wait
  atomic          = var.atomic
  cleanup_on_fail = var.cleanup_on_fail
  timeout         = var.timeout

  create_namespace_with_kubernetes = false 
  kubernetes_namespace             = local.kubernetes_namespace

  eks_cluster_oidc_issuer_url = coalesce(replace(local.eks_cluster_identity_oidc_issuer, "https://", ""), "deleted")

  service_account_name      = module.this.name
  service_account_namespace = local.kubernetes_namespace

  service_account_role_arn_annotation_enabled = true

  iam_role_enabled            = true
  iam_source_policy_documents = [local.controller_policy_json]

  values = compact([
    yamlencode({
      fullnameOverride = module.this.name
      serviceAccount = {
        name = module.this.name
      }
      controller = {
        resources = var.resources
      }
      replicas = var.replicas
    }),
    yamlencode({
      logConfig = {
        enabled = var.logging.enabled
        logLevel = {
          controller = var.logging.level.controller
          global     = var.logging.level.global
          webhook    = var.logging.level.webhook
        }
      }
      settings = merge({
        batchIdleDuration = var.settings.batch_idle_duration
        batchMaxDuration  = var.settings.batch_max_duration
        clusterName       = local.eks_cluster_id
        },
        local.interruption_handler_enabled ? {
          interruptionQueue = local.interruption_handler_queue_name
        } : {}
      )
    }),
    yamlencode(var.chart_values)
  ])

  context = module.this.context

  depends_on = [
    module.karpenter_crd,
    aws_cloudwatch_event_rule.interruption_handler,
    aws_cloudwatch_event_target.interruption_handler,
    aws_sqs_queue.interruption_handler,
    aws_sqs_queue_policy.interruption_handler,
  ]
}

output "metadata" {
  value       = module.karpenter.metadata
  description = "Block status of the deployed release"
}

variable "region" {
  type        = string
  description = "AWS Region"
}

variable "chart_description" {
  type        = string
  description = "Set release description attribute (visible in the history)"
  default     = null
}

variable "chart" {
  type        = string
  description = "Chart name to be installed. The chart name can be local path, a URL to a chart, or the name of the chart if `repository` is specified. It is also possible to use the `<repository>/<chart>` format here if you are running Terraform on a system that the repository has been added to with `helm repo add` but this is not recommended"
}

variable "chart_repository" {
  type        = string
  description = "Repository URL where to locate the requested chart"
}

variable "chart_version" {
  type        = string
  description = "Specify the exact chart version to install. If this is not specified, the latest version is installed"
  default     = null
}

variable "crd_chart_enabled" {
  type        = bool
  description = "`karpenter-crd` can be installed as an independent helm chart to manage the lifecycle of Karpenter CRDs. Set to `true` to install this CRD helm chart before the primary karpenter chart."
  default     = false
}

variable "crd_chart" {
  type        = string
  description = "The name of the Karpenter CRD chart to be installed, if `var.crd_chart_enabled` is set to `true`."
  default     = "karpenter-crd"
}

variable "resources" {
  type = object({
    limits = object({
      cpu    = string
      memory = string
    })
    requests = object({
      cpu    = string
      memory = string
    })
  })
  description = "The CPU and memory of the deployment's limits and requests"
}

variable "timeout" {
  type        = number
  description = "Time in seconds to wait for any individual kubernetes operation (like Jobs for hooks). Defaults to `300` seconds"
  default     = null
}

variable "cleanup_on_fail" {
  type        = bool
  description = "Allow deletion of new resources created in this upgrade when upgrade fails"
  default     = true
}

variable "atomic" {
  type        = bool
  description = "If set, installation process purges chart on fail. The wait flag will be set automatically if atomic is used"
  default     = true
}

variable "wait" {
  type        = bool
  description = "Will wait until all resources are in a ready state before marking the release as successful. It will wait for as long as `timeout`. Defaults to `true`"
  default     = null
}

variable "chart_values" {
  type        = any
  description = "Additional values to yamlencode as `helm_release` values"
  default     = {}
}

variable "rbac_enabled" {
  type        = bool
  description = "Enable/disable RBAC"
  default     = true
}

variable "eks_component_name" {
  type        = string
  description = "The name of the eks component"
  default     = "eks/cluster"
}

variable "interruption_handler_enabled" {
  type        = bool
  default     = true
  description = <<EOD
  If `true`, deploy a SQS queue and Event Bridge rules to enable interruption handling by Karpenter.
  https://karpenter.sh/docs/concepts/disruption/#interruption
  EOD
}

variable "interruption_queue_message_retention" {
  type        = number
  default     = 300
  description = "The message retention in seconds for the interruption handler SQS queue."
}

variable "replicas" {
  type        = number
  description = "The number of Karpenter controller replicas to run"
  default     = 2
}

variable "settings" {
  type = object({
    batch_idle_duration = optional(string, "1s")
    batch_max_duration  = optional(string, "10s")
  })
  description = <<-EOT
  A subset of the settings for the Karpenter controller.
  Some settings are implicitly set by this component, such as `clusterName` and
  `interruptionQueue`. All settings can be overridden by providing a `settings`
  section in the `chart_values` variable. The settings provided here are the ones
  mostly likely to be set to other than default values, and are provided here for convenience.
  EOT
  default     = {}
  nullable    = false
}

variable "logging" {
  type = object({
    enabled = optional(bool, true)
    level = optional(object({
      controller = optional(string, "info")
      global     = optional(string, "info")
      webhook    = optional(string, "error")
    }), {})
  })
  description = "A subset of the logging settings for the Karpenter controller"
  default     = {}
  nullable    = false
}

variable "kubeconfig_file_enabled" {
  type        = bool
  default     = false
  description = "If `true`, configure the Kubernetes provider with `kubeconfig_file` and use that kubeconfig file for authenticating to the EKS cluster"
  nullable    = false
}

variable "kubeconfig_file" {
  type        = string
  default     = ""
  description = "The Kubernetes provider `config_path` setting to use when `kubeconfig_file_enabled` is `true`"
  nullable    = false
}

variable "kubeconfig_context" {
  type        = string
  default     = ""
  description = <<-EOT
    Context to choose from the Kubernetes config file.
    If supplied, `kubeconfig_context_format` will be ignored.
  EOT
  nullable    = false
}

variable "kubeconfig_context_format" {
  type        = string
  default     = ""
  description = <<-EOT
    A format string to use for creating the `kubectl` context name when
    `kubeconfig_file_enabled` is `true` and `kubeconfig_context` is not supplied.
    Must include a single `%s` which will be replaced with the cluster name.
  EOT
  nullable    = false
}

variable "kube_data_auth_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    If `true`, use an `aws_eks_cluster_auth` data source to authenticate to the EKS cluster.
    Disabled by `kubeconfig_file_enabled` or `kube_exec_auth_enabled`.
  EOT
  nullable    = false
}

variable "kube_exec_auth_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
    If `true`, use the Kubernetes provider `exec` feature to execute `aws eks get-token` to authenticate to the EKS cluster.
    Disabled by `kubeconfig_file_enabled`, overrides `kube_data_auth_enabled`.
  EOT
  nullable    = false
}

variable "kube_exec_auth_role_arn" {
  type        = string
  default     = ""
  description = "The role ARN for `aws eks get-token` to use"
  nullable    = false
}

variable "kube_exec_auth_role_arn_enabled" {
  type        = bool
  default     = true
  description = "If `true`, pass `kube_exec_auth_role_arn` as the role ARN to `aws eks get-token`"
  nullable    = false
}

variable "kube_exec_auth_aws_profile" {
  type        = string
  default     = ""
  description = "The AWS config profile for `aws eks get-token` to use"
  nullable    = false
}

variable "kube_exec_auth_aws_profile_enabled" {
  type        = bool
  default     = false
  description = "If `true`, pass `kube_exec_auth_aws_profile` as the `profile` to `aws eks get-token`"
  nullable    = false
}

variable "kubeconfig_exec_auth_api_version" {
  type        = string
  default     = "client.authentication.k8s.io/v1beta1"
  description = "The Kubernetes API version of the credentials returned by the `exec` auth plugin"
  nullable    = false
}

variable "helm_manifest_experiment_enabled" {
  type        = bool
  default     = false
  description = "Enable storing of the rendered manifest for helm_release so the full diff of what is changing can been seen in the plan"
  nullable    = false
}

locals {
  kubeconfig_file_enabled = var.kubeconfig_file_enabled
  kubeconfig_file         = local.kubeconfig_file_enabled ? var.kubeconfig_file : ""
  kubeconfig_context = !local.kubeconfig_file_enabled ? "" : (
    length(var.kubeconfig_context) != 0 ? var.kubeconfig_context : (
      length(var.kubeconfig_context_format) != 0 ? format(var.kubeconfig_context_format, local.eks_cluster_id) : ""
    )
  )

  kube_exec_auth_enabled = local.kubeconfig_file_enabled ? false : var.kube_exec_auth_enabled
  kube_data_auth_enabled = local.kube_exec_auth_enabled ? false : var.kube_data_auth_enabled

  kubeconfig_exec_auth_api_version = var.kubeconfig_exec_auth_api_version

  exec_profile = local.kube_exec_auth_enabled && var.kube_exec_auth_aws