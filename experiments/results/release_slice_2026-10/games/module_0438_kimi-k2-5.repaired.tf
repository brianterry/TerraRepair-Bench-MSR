#
# ONLY EDIT THIS FILE IN github.com/cloudposse/terraform-null-label
# All other instances of this file should be a copy of that one
#
#
# Copy this file from https://github.com/cloudposse/terraform-null-label/blob/master/exports/context.tf
# and then place it in your Terraform module to automatically get
# Cloud Posse's standard configuration inputs suitable for passing
# to Cloud Posse modules.
#
# curl -sL https://raw.githubusercontent.com/cloudposse/terraform-null-label/master/exports/context.tf -o context.tf
#
# Modules should access the whole context as `module.this.context`
# to get the input variables with nulls for defaults,
# for example `context = module.this.context`,
# and access individual variables as `module.this.<var>`,
# with final values filled in.
#
# For example, when using defaults, `module.this.context.delimiter`
# will be null, and `module.this.delimiter` will be `-` (hyphen).
#

module "this" {
  source  = "cloudposse/label/null"
  version = "0.25.0" # requires Terraform >= 0.13.0

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

# Copy contents of cloudposse/terraform-null-label/variables.tf here

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
    # Note: we have to use [] instead of null for unset lists due to
    # https://github.com/hashicorp/terraform/issues/28137
    # which was not fixed until Terraform 1.0.0,
    # but we want the default to be all the labels in `label_order`
    # and we want users to be able to prevent all tag generation
    # by setting `labels_as_tags` to `[]`, so we need
    # a different sentinel to indicate "default"
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

#### End of copy of cloudposse/terraform-null-label/variables.tf


#####
# The primary and current (v1beta API) controller policy is in the controller-policy.tf file.
#
# However, if you have workloads that were deployed under the v1alpha API, you need to also
# apply this controller-policy-v1alpha.tf policy to the Karpenter controller to give it permission
# to manage (an in particular, delete) those workloads, and give it permission to manage the
# EC2 Instance Profile possibly created by the EKS cluster component.
#
# This policy is not needed for workloads deployed under the v1beta API with the
# EC2 Instance Profile created by the Karpenter controller.
#
# This allows it to terminate instances and delete launch templates that are tagged with the
# v1alpha API tag "karpenter.sh/provisioner-name" and to manage the EC2 Instance Profile
# created by the EKS cluster component.
#
# We create a separate policy and attach it separately to the Karpenter controller role
# because the main policy is near the 6,144 character limit for an IAM policy, and
# adding this to it can push it over. See:
#   https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_iam-quotas.html#reference_iam-quotas-entities
#

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

# We create a separate policy and attach it separately to the Karpenter controller role
# because the main policy is near the 6,144 character limit for an IAM policy, and
# adding this to it can push it over. See:
#   https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_iam-quotas.html#reference_iam-quotas-entities
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


# Unfortunately, Karpenter does not provide the Karpenter controller IAM policy in JSON directly:
#   https://github.com/aws/karpenter/issues/2649
#
# You can get it from the `data.aws_iam_policy_document.karpenter_controller` in
#  https://github.com/terraform-aws-modules/terraform-aws-iam/blob/master/modules/iam-role-for-service-accounts-eks/policies.tf
# but that is not guaranteed to be up-to-date.
#
# Instead, we download the official source of truth, the CloudFormation template, and extract the IAM policy from it.
#
# The policy is not guaranteed to be stable from version to version.
# However, it seems stable enough, and we will leave for later the task of supporting multiple versions.
#
# To get the policy for a given Karpenter version >= 0.32.0, run:
#
# KARPENTER_VERSION=<version>
# curl -O -fsSL https://raw.githubusercontent.com/aws/karpenter-provider-aws/v"${KARPENTER_VERSION}"/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml
#
# Then open the downloaded cloudformation.yaml file and look for this resource (there may be other lines in between):
#
#  KarpenterControllerPolicy:
#    Type: AWS::IAM::ManagedPolicy
#    Properties:
#      PolicyDocument: !Sub |
#
# After which should be the IAM policy document in JSON format, with
# CloudFormation substitutions like
#
#   "Resource": "arn:${local.aws_partition}:eks:${var.region}:${AWS::AccountId}:cluster/${local.eks_cluster_id}"
#
# NOTE: As a special case, the above multiple substitutions which create the ARN for the EKS cluster
# should be replaced with a single substitution, `${local.eks_cluster_arn}` to avoid needing to
# look up the account ID and because it is more robust.
#
# Review the existing HEREDOC below to find conditionals such as:
#    %{if local.interruption_handler_enabled }
# and figure out how you want to re-incorporate them into the new policy, if needed.
#
# Paste the new policy into the HEREDOC below, then replace the CloudFormation substitutions with Terraform substitutions,
# e.g. ${var.region} -> ${var.region}
#
# and restore the conditionals.
#

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


# These event definitions, queue policies, and SQS queue definition
# come from the Karpenter CloudFormation template.
# See comments in `controller-policy.tf` for more information.

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


# https://aws.amazon.com/blogs/aws/introducing-karpenter-an-open-source-high-performance-kubernetes-cluster-autoscaler/
# https://karpenter.sh/

locals {
  enabled = module.this.enabled

  # We need aws_partition to be non-null even when this module is disabled, because it is used in a string template
  aws_partition = coalesce(one(data.aws_partition.current[*].partition), "aws")

  # eks_cluster_id is defined in provider-helm.tf
  # eks_cluster_id = module.eks.outputs.eks_cluster_id
  eks_cluster_arn                  = module.eks.outputs.eks_cluster_arn
  eks_cluster_identity_oidc_issuer = module.eks.outputs.eks_cluster_identity_oidc_issuer

  karpenter_node_role_arn = module.eks.outputs.karpenter_iam_role_arn

  # Prior to Karpenter v0.32.0 (the v1Alpha APIs), Karpenter recommended using a dedicated namespace for Karpenter resources.
  # Starting with Karpenter v0.32.0, Karpenter recommends installing Karpenter resources in the kube-system namespace.
  # https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/#preventing-apiserver-request-throttling
  kubernetes_namespace = "kube-system"
}

data "aws_partition" "current" {
  count = local.enabled ? 1 : 0
}


# Deploy karpenter-crd helm chart
# "karpenter-crd" can be installed as an independent helm chart to manage the lifecycle of Karpenter CRDs
module "karpenter_crd" {
  enabled = local.enabled && var.crd_chart_enabled

  source = "cloudposse/helm-release/aws?ref=0.10.1"

  name            = var.crd_chart
  chart           = var.crd_chart
  repository      = var.chart_repository
  description     = var.chart_description
  chart_version   = var.chart_version
  wait            = var.wait
  atomic          = var.atomic
  cleanup_on_fail = var.cleanup_on_fail
  timeout         = var.timeout

  create_namespace_with_kubernetes = false # Namespace is created by EKS/Kubernetes by default
  kubernetes_namespace             = local.kubernetes_namespace

  eks_cluster_oidc_issuer_url = coalesce(replace(local.eks_cluster_identity_oidc_issuer, "https://", ""), "deleted")

  context = module.this.context
}

# Deploy Karpenter helm chart
module "karpenter" {
  source = "cloudposse/helm-release/aws?ref=0.10.1"

  chart           = var.chart
  repository      = var.chart_repository
  description     = var.chart_description
  chart_version   = var.chart_version
  wait            = var.wait
  atomic          = var.atomic
  cleanup_on_fail = var.cleanup_on_fail
  timeout         = var.timeout

  create_namespace_with_kubernetes = false # Namespace is created with kubernetes_namespace resources to be shared between charts
  kubernetes_namespace             = local.kubernetes_namespace

  eks_cluster_oidc_issuer_url = coalesce(replace(local.eks_cluster_identity_oidc_issuer, "https://", ""), "deleted")

  service_account_name      = module.this.name
  service_account_namespace = local.kubernetes_namespace

  # Defaults to true, but set it here so it can be disabled when switching to Pod Identities
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
    #  karpenter-specific values
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
      }
    ),
    # additional values
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


##################
#
# This file is a drop-in to provide a helm provider.
#
# It depends on 2 standard Cloud Posse data source modules to be already
# defined in the same component:
#
#   1. module.iam_roles to provide the AWS profile or Role ARN to use to access the cluster
#   2. module.eks to provide the EKS cluster information
#
# All the following variables are just about configuring the Kubernetes provider
# to be able to modify EKS cluster. The reason there are so many options is
# because at various times, each one of them has had problems, so we give you a choice.
#
# The reason there are so many "enabled" inputs rather than automatically
# detecting whether or not they are enabled based on the value of the input
# is that any logic based on input values requires the values to be known during
# the "plan" phase of Terraform, and often they are not, which causes problems.
#
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

  # Eventually we might try to get this from an environment variable
  kubeconfig_exec_auth_api_version = var.kubeconfig_exec_auth_api_version

  exec_profile = local.kube_exec_auth_enabled && var.kube_exec_auth_aws_profile_enabled ? [
    "--profile", var.kube_exec_auth_aws_profile
  ] : []

  kube_exec_auth_role_arn = coalesce(var.kube_exec_auth_role_arn, module.iam_roles.terraform_role_arn)
  exec_role = local.kube_exec_auth_enabled && var.kube_exec_auth_role_arn_enabled ? [
    "--role-arn", local.kube_exec_auth_role_arn
  ] : []

  # Provide dummy configuration for the case where the EKS cluster is not available.
  certificate_authority_data = local.kubeconfig_file_enabled ? null : try(module.eks.outputs.eks_cluster_certificate_authority_data, null)
  cluster_ca_certificate     = local.kubeconfig_file_enabled ? null : try(base64decode(local.certificate_authority_data), null)
  # Use coalesce+try to handle both the case where the output is missing and the case where it is empty.
  eks_cluster_id       = coalesce(try(module.eks.outputs.eks_cluster_id, ""), "missing")
  eks_cluster_endpoint = local.kubeconfig_file_enabled ? null : try(module.eks.outputs.eks_cluster_endpoint, "")
}

data "aws_eks_cluster_auth" "eks" {
  count = local.kube_data_auth_enabled ? 1 : 0
  name  = local.eks_cluster_id
}

provider "helm" {
  kubernetes {
    host                   = local.eks_cluster_endpoint
    cluster_ca_certificate = local.cluster_ca_certificate
    token                  = local.kube_data_auth_enabled ? one(data.aws_eks_cluster_auth.eks[*].token) : null
    # It is too confusing to allow the Kubernetes provider to use environment variables to set authentication
    # in this module because we have so many options, so we override environment variables like `KUBE_CONFIG_PATH`
    # in all cases. People can still use environment variables by setting TF_VAR_kubeconfig_file.
    config_path    = local.kubeconfig_file
    config_context = local.kubeconfig_context

    dynamic "exec" {
      for_each = local.kube_exec_auth_enabled && local.certificate_authority_data != null ? ["exec"] : []
      content {
        api_version = local.kubeconfig_exec_auth_api_version
        command     = "aws"
        args = concat(local.exec_profile, [
          "eks", "get-token", "--cluster-name", local.eks_cluster_id
        ], local.exec_role)
      }
    }
  }
  experiments {
    manifest = var.helm_manifest_experiment_enabled && module.this.enabled
  }
}

provider "kubernetes" {
  host                   = local.eks_cluster_endpoint
  cluster_ca_certificate = local.cluster_ca_certificate
  token                  = local.kube_data_auth_enabled ? one(data.aws_eks_cluster_auth.eks[*].token) : null
  # It is too confusing to allow the Kubernetes provider to use environment variables to set authentication
  # in this module because we have so many options, so we override environment variables like `KUBE_CONFIG_PATH`
  # in all cases. People can still use environment variables by setting TF_VAR_kubeconfig_file.
  config_path    = local.kubeconfig_file
  config_context = local.kubeconfig_context

  dynamic "exec" {
    for_each = local.kube_exec_auth_enabled && local.certificate_authority_data != null ? ["exec"] : []
    content {
      api_version = local.kubeconfig_exec_auth_api_version
      command     = "aws"
      args = concat(local.exec_profile, [
        "eks", "get-token", "--cluster-name", local.eks_cluster_id
      ], local.exec_role)
    }
  }
}


provider "aws" {
  region = var.region

  # Profile is deprecated in favor of terraform_role_arn. When profiles are not in use, terraform_profile_name is null.
  profile = module.iam_roles.terraform_profile_name

  dynamic "assume_role" {
    # module.iam_roles.terraform_role_arn may be null, in which case do not assume a role.
    for_each = compact([module.iam_roles.terraform_role_arn])
    content {
      role_arn = assume_role.value
    }
  }
}

module "iam_roles" {
  source  = "../../account-map/modules/iam-roles"
  context = module.this.context
}


module "eks" {
  source = "cloudposse/stack-config/yaml//modules/remote-state?ref=1.5.0"

  component = var.eks_component_name

  context = module.this.context

  # Attempt to allow this component to be deleted from Terraform state even after the EKS cluster has been deleted
  defaults = {
    eks_cluster_id                   = "deleted"
    eks_cluster_arn                  = "deleted"
    eks_cluster_identity_oidc_issuer = "deleted"
    karpenter_node_role_arn          = "deleted"
  }
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


terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.9.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.7.1, != 2.21.0"
    }
  }
}