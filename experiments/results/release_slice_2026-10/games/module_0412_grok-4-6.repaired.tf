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
  source = "git::https://github.com/cloudposse/terraform-null-label.git?ref=488ab91e34a24a86957e397d9f7262ec5925586a"

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


locals {
  eks_cluster_oidc_issuer_url = module.eks.outputs["eks_cluster_identity_oidc_issuer"]
}

module "eks_iam_policy" {
  source = "git::https://github.com/cloudposse/terraform-aws-iam-policy.git?ref=a79601327876a489ca6285db0473651b160c5e50"

  enabled = local.enabled_iam_role

  iam_source_json_url   = var.iam_source_json_url
  iam_policy_statements = var.iam_policy_statements

  context = module.this.context
}

module "eks_iam_role" {
  source = "git::https://github.com/cloudposse/terraform-aws-eks-iam-role.git?ref=3f65385f4b12d7e0f6e15abf1d1ca9d34358159a"

  enabled = local.enabled_iam_role

  aws_iam_policy_document     = local.enabled_iam_role ? join("", data.aws_iam_policy_document.github_action_runner.*.json) : "{}"
  eks_cluster_oidc_issuer_url = local.eks_cluster_oidc_issuer_url
  service_account_name        = var.service_account_name
  service_account_namespace   = var.service_account_namespace

  depends_on = [
    data.aws_iam_policy_document.github_action_runner
  ]

  context = module.this.context
}

data "aws_iam_policy_document" "github_action_runner" {
  count = local.enabled_iam_role ? 1 : 0

  statement {
    sid    = "EcrReadWriteDeleteAccess"
    effect = "Allow"

    actions = [
      # This is intended to be everything except create/delete repository
      # and get/set/delete repositoryPolicy
      "ecr:GetAuthorizationToken",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:PutImageTagMutability",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:DescribeImageScanFindings",
      "ecr:StartImageScan",
      "ecr:BatchDeleteImage",
      "ecr:TagResource",
      "ecr:UntagResource",
      "ecr:GetLifecyclePolicy",
      "ecr:PutLifecyclePolicy",
      "ecr:StartLifecyclePolicyPreview",
      "ecr:GetLifecyclePolicyPreview",
      "ecr:DeleteLifecyclePolicy",
      "ecr:PutImageScanningConfiguration",
    ]
    resources = ["*"]
  }

  statement {
    sid = "AssumeRoles"

    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]

    effect    = "Allow"
    resources = [module.iam_primary_roles.outputs.role_name_role_arn_map["cicd"]]
  }

  statement {
    sid = "AllowGithubActionRunnersSSMAccess"

    actions = [
      "ssm:DescribeParameters"
    ]

    effect    = "Allow"
    resources = ["*"]
  }

  statement {
    sid = "AllowGithubActionRunnersSSMReadAccess"

    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]

    effect = "Allow"

    resources = [
      format(
        "arn:%s:ssm:%s:%s:parameter/github-action/secrets/*",
        data.aws_partition.current.partition,
        var.region,
        data.aws_caller_identity.current.account_id
      )
    ]
  }
}

data "aws_iam_policy_document" "github_action_runner_kms" {
  count = local.enabled_iam_role ? 1 : 0

  statement {
    sid = "AllowGithubActionRunnersToDecrypt"

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey*"
    ]

    effect = "Allow"
    resources = [
      aws_kms_key.github_action_runner[0].arn
    ]
  }
}

resource "aws_iam_policy" "github_action_runner_kms" {
  count = local.enabled_iam_role ? 1 : 0

  name        = "github_action_runner_kms"
  description = "Grants github-runners access to kms"

  policy = data.aws_iam_policy_document.github_action_runner_kms[0].json

  tags = module.this.tags
}

resource "aws_iam_role_policy_attachment" "github_action_runner_kms" {
  count = local.enabled_iam_role ? 1 : 0

  role       = module.eks_iam_role.service_account_role_name
  policy_arn = aws_iam_policy.github_action_runner_kms[0].arn
}


resource "aws_kms_key" "github_action_runner" {
  count = local.enabled ? 1 : 0

  description             = "Github Action Runners key used for decryption - ${module.github_action_controller_label.id}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = module.github_action_controller_label.tags
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "github-action-runner-key-policy"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${join("", data.aws_partition.current.*.partition)}:iam::${join("", data.aws_caller_identity.current.*.account_id)}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "github_action_runner" {
  count = local.enabled ? 1 : 0

  name          = format("alias/%v", module.github_action_controller_label.id)
  target_key_id = aws_kms_key.github_action_runner[0].key_id
}


locals {
  enabled                     = module.this.enabled
  eks_cluster_oidc_issuer_url = module.eks.outputs["eks_cluster_identity_oidc_issuer"]
  enabled_iam_role            = local.enabled && var.iam_role_enabled
  # Loop through each supplied runner_configuration to determine if the runner is an organization (org) or repository (repo) runner type
  runners = [for r in var.runner_configurations : merge(r, tomap({
    "type"   = lower(coalesce(contains(keys(r), "repo") ? "repo" : "", contains(keys(r), "org") ? "org" : "")),
    "target" = coalesce(lookup(r, "org", ""), lookup(r, "repo", ""))
    }))
  ]
}

data "aws_caller_identity" "current" {
  count = local.enabled ? 1 : 0
}
data "aws_partition" "current" {
  count = local.enabled ? 1 : 0
}

module "github_action_controller_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=488ab91e34a24a86957e397d9f7262ec5925586a"
  context    = module.this.context
  attributes = ["github-actions-controller"]
}

# You cannot have a directory with the same name as the chart you are installing from repo
# https://github.com/hashicorp/terraform-provider-helm/issues/735
module "actions_runner_controller" {
  source = "git::https://github.com/cloudposse/terraform-aws-helm-release.git?ref=54e6ab034c650c14b9e81065c219110749c10b71"

  name    = var.controller_chart_release_name # module.github_action_controller_label.tags["Attributes"]
  enabled = local.enabled

  repository    = var.controller_chart_repo
  chart         = var.controller_chart_name
  chart_version = var.controller_chart_version

  create_namespace     = var.controller_chart_namespace_create
  kubernetes_namespace = var.controller_chart_namespace

  iam_role_enabled    = local.enabled_iam_role
  iam_source_json_url = var.iam_source_json_url

  eks_cluster_oidc_issuer_url                 = local.eks_cluster_oidc_issuer_url
  service_account_name                        = var.service_account_name
  service_account_namespace                   = var.service_account_namespace
  service_account_role_arn_annotation_enabled = true

  # These values will be deep merged
  values = [
    # remove comments
    yamlencode(yamldecode(
      file("${path.module}/runners/actions-runner-controller/values.yaml"))
    ),
    yamlencode(var.controller_chart_values),
  ]

  set = [
    {
      name  = "image.repository"
      value = var.controller_chart_image
      type  = "string"
    },
    {
      name  = "image.tag"
      value = var.controller_chart_image_tag
      type  = "string"
    },
    {
      name  = "serviceAccount.name"
      value = "github-action-runner"
      type  = "string"
    },
  ]

  iam_policy_statements = flatten([var.iam_policy_statements, [
    {
      sid    = "EcrReadWriteDeleteAccess"
      effect = "Allow"

      actions = [
        # This is intended to be everything except create/delete repository
        # and get/set/delete repositoryPolicy
        "ecr:GetAuthorizationToken",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:PutImageTagMutability",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetRepositoryPolicy",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
        "ecr:DescribeImages",
        "ecr:BatchGetImage",
        "ecr:DescribeImageScanFindings",
        "ecr:StartImageScan",
        "ecr:BatchDeleteImage",
        "ecr:TagResource",
        "ecr:UntagResource",
        "ecr:GetLifecyclePolicy",
        "ecr:PutLifecyclePolicy",
        "ecr:StartLifecyclePolicyPreview",
        "ecr:GetLifecyclePolicyPreview",
        "ecr:DeleteLifecyclePolicy",
        "ecr:PutImageScanningConfiguration",
      ]
      resources = ["*"]
    },
    {
      sid = "AssumeRoles"

      actions = [
        "sts:AssumeRole",
        "sts:TagSession",
      ]

      effect    = "Allow"
      resources = [module.iam_primary_roles.outputs.role_name_role_arn_map["cicd"]]
    },
    {
      sid = "AllowGithubActionRunnersSSMAccess"

      actions = [
        "ssm:DescribeParameters"
      ]

      effect    = "Allow"
      resources = ["*"]
    },
    {
      sid = "AllowGithubActionRunnersSSMReadAccess"

      actions = [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ]

      effect = "Allow"

      resources = [
        format(
          "arn:%s:ssm:%s:%s:parameter/github-action/secrets/*",
          join("", data.aws_partition.current.*.partition),
          var.region,
          join("", data.aws_caller_identity.current.*.account_id)
        )
      ]
    },
    {
      sid = "AllowGithubActionRunnersToDecrypt"

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey*"
      ]

      effect = "Allow"
      resources = [
        aws_kms_key.github_action_runner[0].arn
      ]
    }
  ]])
}

module "github_action_helm_label" {
  count = local.enabled ? length(local.runners) : 0

  source  = "git::https://github.com/cloudposse/terraform-null-label.git?ref=488ab91e34a24a86957e397d9f7262ec5925586a"
  context = module.this.context
  attributes = [
    local.runners[count.index]["type"],
    replace(local.runners[count.index]["target"], "/", "-"),
  ]
}

module "actions_runner" {
  source = "git::https://github.com/cloudposse/terraform-aws-helm-release.git?ref=54e6ab034c650c14b9e81065c219110749c10b71"

  depends_on = [
    module.actions_runner_controller
  ]

  count = local.enabled ? length(local.runners) : 0

  name       = module.github_action_helm_label[count.index].tags["Attributes"]
  repository = var.controller_chart_repo
  chart      = "${path.module}/runners/actions-runner/chart"

  create_namespace     = true
  kubernetes_namespace = "actions-runner-system"

  # These values will be deep merged
  values = [
    yamlencode({
      autoscale            = var.autoscale_types[var.autoscale_type]
      release_name         = module.github_action_helm_label[count.index].tags["Attributes"]
      role_arn             = module.actions_runner_controller.service_account_role_arn
      runner_resources     = var.runner_types[coalesce(lookup(local.runners[count.index], "runner_type", ""), var.runner_type)]
      runners_image        = var.runner_chart_image
      service_account_name = "github-action-runner"
      target               = local.runners[count.index]["target"]
      type                 = local.runners[count.index]["type"]
    }),
    yamlencode(var.runner_chart_values),
  ]
}


output "release_name" {
  value       = var.controller_chart_release_name
  description = "Name of the release"
}

output "release_namespace" {
  value       = var.controller_chart_namespace
  description = "Namespace of the release"
}

output "service_account_role_arn" {
  value       = module.actions_runner_controller.service_account_role_arn
  description = "Service Account role ARN"
}

output "kms_key_arn" {
  value       = join("", aws_kms_key.github_action_runner.*.arn)
  description = "KMS key ARN"
}

output "kms_alias" {
  value       = join("", aws_kms_alias.github_action_runner.*.name)
  description = "KMS alias"
}


provider "aws" {
  region = var.region

  profile = module.iam_roles.profiles_enabled ? coalesce(var.import_profile_name, module.iam_roles.terraform_profile_name) : null
  dynamic "assume_role" {
    for_each = module.iam_roles.profiles_enabled ? [] : ["role"]
    content {
      role_arn = coalesce(var.import_role_arn, module.iam_roles.terraform_role_arn)
    }
  }
}

module "iam_roles" {
  source  = "../account-map/modules/iam-roles"
  context = module.this.context
}

variable "import_profile_name" {
  type        = string
  default     = null
  description = "AWS Profile name to use when importing a resource"
}

variable "import_role_arn" {
  type        = string
  default     = null
  description = "IAM Role ARN to use when importing a resource"
}

data "aws_eks_cluster" "kubernetes" {
  count = local.enabled ? 1 : 0

  name = module.eks.outputs.eks_cluster_id
}

data "aws_eks_cluster_auth" "kubernetes" {
  count = local.enabled ? 1 : 0

  name = module.eks.outputs.eks_cluster_id
}

provider "helm" {
  kubernetes {
    host                   = local.enabled ? data.aws_eks_cluster.kubernetes[0].endpoint : null
    token                  = local.enabled ? data.aws_eks_cluster_auth.kubernetes[0].token : null
    cluster_ca_certificate = local.enabled ? base64decode(data.aws_eks_cluster.kubernetes[0].certificate_authority[0].data) : null
  }
}


module "iam_primary_roles" {
  source = "git::https://github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=bb4d5799c54b234d809f34e463056c12d92f4862"

  component   = "iam-primary-roles"
  environment = var.iam_primary_roles_environment_name
  stage       = var.iam_primary_roles_stage_name

  context = module.this.context
}

module "eks" {
  source = "git::https://github.com/cloudposse/terraform-yaml-stack-config.git//modules/remote-state?ref=bb4d5799c54b234d809f34e463056c12d92f4862"

  component = "eks"

  context = module.this.context
}


variable "region" {
  type        = string
  description = "AWS Region"
}

variable "iam_primary_roles_environment_name" {
  type        = string
  description = "The name of the environment where global `iam_primary_roles` is provisioned"
  default     = "gbl"
}

variable "iam_primary_roles_stage_name" {
  type        = string
  description = "The name of the stage where `iam_primary_roles` is provisioned"
  default     = "identity"
}

#######################################
# actions-runner-controller
variable "controller_chart_namespace" {
  type        = string
  default     = "actions-runner-system"
  description = "Controller kubernetes namespace."
}

variable "controller_chart_namespace_create" {
  type        = bool
  default     = true
  description = "Controller kubernetes namespace created if not present"
}

variable "controller_chart_release_name" {
  type        = string
  default     = "actions-runner-controller"
  description = "Controller Helm chart release name."
}

variable "controller_chart_name" {
  type        = string
  default     = "actions-runner-controller"
  description = "Controller Helm chart name."
}

variable "controller_chart_repo" {
  type        = string
  default     = "https://actions-runner-controller.github.io/actions-runner-controller"
  description = "Controller Helm chart repository name."
}

variable "controller_chart_version" {
  type        = string
  default     = "0.12.8"
  description = "Controller Helm chart version."
}

variable "controller_chart_image" {
  type        = string
  default     = "summerwind/actions-runner-controller"
  description = "Image to use for controller"
}

variable "controller_chart_image_tag" {
  type        = string
  default     = "v0.19.0"
  description = "Tag to use for controller image"
}

variable "controller_chart_values" {
  type        = any
  description = "Additional values to yamlencode as `helm_release` values."
  default     = {}
}

#######################################
# actions-runner-runner
variable "runner_chart_image" {
  type        = string
  default     = "actions-runner"
  description = "Controller Helm chart name."
}

variable "runner_chart_values" {
  type        = any
  description = "Additional values to yamlencode as `helm_release` values."
  default     = {}
}

variable "runner_type" {
  description = "Default choice if not defined in runner_configurations"
  default     = "small"
}

# runner_types:
#   small:
#     resources:
#       limits:
#         cpu: "3"
#         memory: "12Gi"
#       requests:
#         cpu: "1"
#         memory: "1Gi"
variable "runner_types" {
  description = "Map to define resources limits and requests"

  type = map(object({
    resources = object({
      limits = object({
        cpu    = string,
        memory = string
      }),
      requests = object({
        cpu    = string,
        memory = string
      })
    })
  }))

  default = {
    small = {
      resources = {
        limits = {
          cpu    = "3"
          memory = "12Gi"
        }
        requests = {
          cpu    = "1"
          memory = "1Gi"
        }
      }
    }
  }
}

variable "autoscale_type" {
  description = "Default choice if not defined in autoscale_types"
  default     = "low_concurrency"
}

#   low_concurrency:
#     minReplicas: 1
#     maxReplicas: 8
#     metrics:
#       type: PercentageRunnersBusy
#       scaleUpThreshold: '0.75'
#       scaleDownThreshold: '0.3'
#       scaleUpAdjustment: 1
#       scaleDownAdjustment: 1
variable "autoscale_types" {
  description = "Map to define HRA CRD scaling configurations"

  type = map(object({
    minReplicas = number,
    maxReplicas = number
    metrics = object({
      type                = string,
      scaleUpThreshold    = number,
      scaleDownThreshold  = number,
      scaleUpAdjustment   = number,
      scaleDownAdjustment = number
    })
  }))

  default = {
    low_concurrency = {
      minReplicas = 1
      maxReplicas = 8
      metrics = {
        type                = "PercentageRunnersBusy"
        scaleUpThreshold    = 0.75
        scaleDownThreshold  = 0.3
        scaleUpAdjustment   = 1
        scaleDownAdjustment = 1
      }
    }
  }
}

variable "runner_configurations" {
  description = "List of maps to create runners from"

  type = list(map(string))

  # runner_configuration must have a key of `repo` or `org` as its target
  validation {
    condition     = alltrue([for r in var.runner_configurations : lookup(r, "repo", "") != "" || lookup(r, "org", "") != ""])
    error_message = "Variable runner_configurations must contain a target key of either `repo` or `org`."
  }

  # runner_configuration cannot have both `repo` and `org`, there can be only one
  validation {
    condition     = alltrue([for r in var.runner_configurations : lookup(r, "repo", "") != "" && lookup(r, "org", "") != "" ? false : true])
    error_message = "Variable runner_configurations can contain only one target key of either `repo` or `org` not both."
  }

  # runner_configuration may only contain map keys "repo", "org", "runner_type", "autoscale_type"
  validation {
    condition     = alltrue([for r in var.runner_configurations : alltrue([for k in keys(r) : contains(["repo", "org", "runner_type", "autoscale_type"], k)])])
    error_message = "Unknown map key, must be one of repo, org, runner_type or autoscale_type."
  }

}

## eks_iam

variable "iam_role_enabled" {
  type        = bool
  description = "Whether to create an IAM role. Setting this to `true` will also replace any occurrences of `{service_account_role_arn}` in `var.values_template_path` with the ARN of the IAM role created by this module."
  default     = false
}

## eks_iam_policy

variable "iam_source_json_url" {
  type        = string
  description = "IAM source json policy to download. This will be used as the `source_json` meaning the `var.iam_policy_statements` and `var.iam_policy_statements_template_path` can override it."
  default     = null
}

variable "iam_policy_statements" {
  type        = any
  description = "IAM policy for the service account. Required if `var.iam_role_enabled` is `true`. This will not do variable replacements. Please see `var.iam_policy_statements_template_path`."
  default     = []
}

## eks_iam_role

variable "service_account_name" {
  type        = string
  description = "Kubernetes ServiceAccount name. Required if `var.iam_role_enabled` is `true`."
  default     = null
}

variable "service_account_namespace" {
  type        = string
  description = "Kubernetes Namespace where service account is deployed. Required if `var.iam_role_enabled` is `true`."
  default     = null
}


terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0"
    }
  }
}