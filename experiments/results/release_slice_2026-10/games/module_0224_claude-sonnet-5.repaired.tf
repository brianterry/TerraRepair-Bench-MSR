```hcl
resource "aws_account_alternate_contact" "infrastructure_support_operations" {

  alternate_contact_type = "OPERATIONS"

  name          = "Infrastructure Support"
  title         = "Infrastructure Support Operations"
  email_address = local.application_tags.infrastructure-support
  phone_number  = "+0000000000"
}


terraform {
  # `backend` blocks do not support variables, so the following are hard-coded here:
  # - S3 bucket name, which is created in terraform/modernisation-platform-account/s3.tf
  backend "s3" {
    acl                  = "bucket-owner-full-control"
    bucket               = "modernisation-platform-terraform-state"
    encrypt              = true
    key                  = "terraform.tfstate"
    region               = "eu-west-2"
    use_lockfile         = true
    workspace_key_prefix = "environments/bootstrap/member-bootstrap" # This will store the object as environments/bootstrap/member-bootstrap/${workspace}/terraform.tfstate
  }
}


# read only role for collaborators
module "collaborator_readonly_role" {
  # checkov:skip=CKV_TF_1:

  count  = local.account_data.account-type == "member" || local.account_data.account-type == "core" ? 1 : 0
  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-assumable-roles?ref=de95e21a3bc51cd3a44b3b95a4c2f61000649ebb" # v5.39.1

  max_session_duration = 43200
  # Read-only role
  create_readonly_role       = true
  readonly_role_name         = "read-only"
  readonly_role_requires_mfa = true

  # Allow created users to assume these roles
  trusted_role_arns = [
    data.aws_ssm_parameter.modernisation_platform_account_id.value
  ]
}

data "aws_iam_policy" "common_policy" {
  name = "common_policy"
}

# security audit role for collaborators
module "collaborator_security_audit_role" {
  # checkov:skip=CKV_TF_1:

  count  = local.account_data.account-type == "member" || local.account_data.account-type == "core" ? 1 : 0
  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-assumable-role?ref=de95e21a3bc51cd3a44b3b95a4c2f61000649ebb" # v5.39.1

  max_session_duration = 43200

  create_role       = true
  role_name         = "security-audit"
  role_requires_mfa = true

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/SecurityAudit"
  ]

  # Allow created users to assume these roles
  trusted_role_arns = [
    data.aws_ssm_parameter.modernisation_platform_account_id.value
  ]
}

# developer role for collaborators
module "collaborator_developer_role" {
  # checkov:skip=CKV_TF_1:

  count  = local.account_data.account-type == "member" ? 1 : 0
  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-assumable-role?ref=de95e21a3bc51cd3a44b3b95a4c2f61000649ebb" # v5.39.1

  trusted_role_arns = [
    data.aws_ssm_parameter.modernisation_platform_account_id.value
  ]

  create_role       = true
  role_name         = "developer"
  role_requires_mfa = true

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
    data.aws_iam_policy.developer.arn,
    data.aws_iam_policy.common_policy.arn,
  ]
  number_of_custom_role_policy_arns = 3
}

data "aws_iam_policy" "developer" {
  name = "developer_policy"
}

# Collaborator Sandbox role
module "collaborator_sandbox_role" {
  # checkov:skip=CKV_TF_1:

  count  = (local.account_data.account-type == "member" && (local.application_environment == "development" || terraform.workspace == "youth-justice-app-framework-preproduction")) ? 1 : 0
  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-assumable-role?ref=de95e21a3bc51cd3a44b3b95a4c2f61000649ebb" # v5.39.1

  trusted_role_arns = [
    data.aws_ssm_parameter.modernisation_platform_account_id.value
  ]

  create_role       = true
  role_name         = "sandbox"
  role_requires_mfa = true

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
    data.aws_iam_policy.sandbox.arn,
    data.aws_iam_policy.common_policy.arn,
    data.aws_iam_policy.bedrock.arn,
  ]
  number_of_custom_role_policy_arns = 3
}

data "aws_iam_policy" "sandbox" {
  name = "sandbox_policy"
}

data "aws_iam_policy" "bedrock" {
  name = "bedrock_policy"
}
# Collaborator Migration role
module "collaborator_migration_role" {
  # checkov:skip=CKV_TF_1:

  count  = local.account_data.account-type == "member" ? 1 : 0
  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-assumable-role?ref=de95e21a3bc51cd3a44b3b95a4c2f61000649ebb" # v5.39.1

  trusted_role_arns = [
    data.aws_ssm_parameter.modernisation_platform_account_id.value
  ]

  create_role       = true
  role_name         = "migration"
  role_requires_mfa = true

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
    "arn:aws:iam::aws:policy/AWSApplicationMigrationFullAccess",
    "arn:aws:iam::aws:policy/AWSDataSyncFullAccess",
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess",
    "arn:aws:iam::aws:policy/ServerMigrationConnector",
    "arn:aws:iam::aws:policy/AWSApplicationMigrationEC2Access",
    data.aws_iam_policy.migration.arn,
    data.aws_iam_policy.developer.arn,
    data.aws_iam_policy.common_policy.arn,
  ]
  number_of_custom_role_policy_arns = 9
}

data "aws_iam_policy" "migration" {
  name = "migration_policy"
}

# Collaborator Instance Access role
module "collaborator_instance_access_role" {
  # checkov:skip=CKV_TF_1:

  count  = local.account_data.account-type == "member" ? 1 : 0
  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-assumable-role?ref=de95e21a3bc51cd3a44b3b95a4c2f61000649ebb" # v5.39.1

  trusted_role_arns = [
    data.aws_ssm_parameter.modernisation_platform_account_id.value
  ]

  create_role       = true
  role_name         = "instance-access"
  role_requires_mfa = true

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
    data.aws_iam_policy.instance-access.arn,
    data.aws_iam_policy.common_policy.arn,
  ]
  number_of_custom_role_policy_arns = 3
}

data "aws_iam_policy" "instance-access" {
  name = "instance_access_policy"
}

# Collaborator Database Management role
module "collaborator_database_mgmt_role" {
  # checkov:skip=CKV_TF_1:

  count  = local.account_data.account-type == "member" ? 1 : 0
  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-assumable-role?ref=de95e21a3bc51cd3a44b3b95a4c2f61000649ebb" # v5.39.1

  trusted_role_arns = [
    data.aws_ssm_parameter.modernisation_platform_account_id.value
  ]

  create_role       = true
  role_name         = "instance-management"
  role_requires_mfa = true

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
    data.aws_iam_policy.instance-management.arn,
    data.aws_iam_policy.common_policy.arn,
  ]
  number_of_custom_role_policy_arns = 3
}

data "aws_iam_policy" "instance-management" {
  name = "instance_management_policy"
}

# fleet-manager role for collaborators
module "collaborator_fleet_manager_role" {
  # checkov:skip=CKV_TF_1:

  count  = local.account_data.account-type == "member" ? 1 : 0
  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-assumable-role?ref=de95e21a3bc51cd3a44b3b95a4c2f61000649ebb" # v5.39.1

  trusted_role_arns = [
    data.aws_ssm_parameter.modernisation_platform_account_id.value
  ]

  create_role       = true
  role_name         = "fleet-manager"
  role_requires_mfa = true

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
    data.aws_iam_policy.fleet_manager.arn,
    data.aws_iam_policy.common_policy.arn,
  ]
  number_of_custom_role_policy_arns = 3
}

data "aws_iam_policy" "fleet_manager" {
  name = "fleet_manager_policy"
}

# s3-upload role for collaborators
module "collaborator_s3_upload_role" {
  # checkov:skip=CKV_TF_1:

  count  = local.account_data.account-type == "member" ? 1 : 0
  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-assumable-role?ref=de95e21a3bc51cd3a44b3b95a4c2f61000649ebb" # v5.39.1

  trusted_role_arns = [
    data.aws_ssm_parameter.modernisation_platform_account_id.value
  ]

  create_role       = true
  role_name         = "s3-upload"
  role_requires_mfa = true

  custom_role_policy_arns = [
    data.aws_iam_policy.s3_upload.arn
  ]
  number_of_custom_role_policy_arns = 1
}

data "aws_iam_policy" "s3_upload" {
  name = "s3_upload_policy"
}

# Collaborator Instance Access role
module "collaborator_platform_engineer_admin_role" {
  # checkov:skip=CKV_TF_1:

  count  = local.account_data.account-type == "member" ? 1 : 0
  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-assumable-role?ref=de95e21a3bc51cd3a44b3b95a4c2f61000649ebb" # v5.39.1

  trusted_role_arns = [
    data.aws_ssm_parameter.modernisation_platform_account_id.value
  ]

  create_role       = true
  role_name         = "platform-engineer-admin"
  role_requires_mfa = true

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
    data.aws_iam_policy.platform_engineer_admin.arn,
    data.aws_iam_policy.common_policy.arn,
  ]
  number_of_custom_role_policy_arns = 3
}

data "aws_iam_policy" "platform_engineer_admin" {
  name = "platform_engineer_admin_policy"
}

# Collaborator Reporting-Operations role
module "collaborator_reporting_operations_role" {
  # checkov:skip=CKV_TF_1:

  count  = local.account_data.account-type == "member" ? 1 : 0
  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-assumable-role?ref=de95e21a3bc51cd3a44b3b95a4c2f61000649ebb" # v5.39.1

  trusted_role_arns = [
    data.aws_ssm_parameter.modernisation_platform_account_id.value
  ]

  create_role       = true
  role_name         = "reporting-operations"
  role_requires_mfa = true

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
    data.aws_iam_policy.reporting_operations.arn,
    data.aws_iam_policy.common_policy.arn,
  ]
  number_of_custom_role_policy_arns = 3
}

data "aws_iam_policy" "reporting_operations" {
  name = "reporting_operations_policy"
}

# SSM Session Access role
module "collaborator_ssm_session_access_role" {
  # checkov:skip=CKV_TF_1:

  count  = local.account_data.account-type == "member" ? 1 : 0
  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-assumable-role?ref=de95e21a3bc51cd3a44b3b95a4c2f61000649ebb" # v5.39.1

  trusted_role_arns = [
    data.aws_ssm_parameter.modernisation_platform_account_id.value
  ]

  create_role       = true
  role_name         = "ssm-session-access"
  role_requires_mfa = true

  custom_role_policy_arns = [
    data.aws_iam_policy.ssm_session_access.arn
  ]
  number_of_custom_role_policy_arns = 1
}

data "aws_iam_policy" "ssm_session_access" {
  name = "ssm_session_access_policy"
}


# Quicksight admin role
module "collaborator_quicksight_admin_role" {
  # checkov:skip=CKV_TF_1:

  count  = local.account_data.account-type == "member" ? 1 : 0
  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-assumable-role?ref=de95e21a3bc51cd3a44b3b95a4c2f61000649ebb" # v5.39.1

  trusted_role_arns = [
    data.aws_ssm_parameter.modernisation_platform_account_id.value
  ]

  create_role       = true
  role_name         = "quicksight-admin-access"
  role_requires_mfa = true

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
    data.aws_iam_policy.quicksight_administrator.arn,
    data.aws_iam_policy.common_policy.arn,
  ]
  number_of_custom_role_policy_arns = 3
}

data "aws_iam_policy" "quicksight_administrator" {
  name = "quicksight_administrator_policy"
}

# Data Scientist role

module "collaborator_data_scientist_role" {
  # checkov:skip=CKV_TF_1:

  count  = local.account_data.account-type == "member" ? 1 : 0
  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-assumable-role?ref=de95e21a3bc51cd3a44b3b95a4c2f61000649ebb" # v5.39.1

  trusted_role_arns = [
    data.aws_ssm_parameter.modernisation_platform_account_id.value
  ]

  create_role       = true
  role_name         = "data-scientist"
  role_requires_mfa = true

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonRedshiftQueryEditorV2FullAccess",
    data.aws_iam_policy.data_scientist.arn,
  ]
  number_of_custom_role_policy_arns = 2
}

data "aws_iam_policy" "data_scientist" {
  name = "data_scientist_policy"
}

locals {
  enable_malware_notifications = startswith(terraform.workspace, "ccms-ebs")
}

# KMS Key for SNS Encryption
resource "aws_kms_key" "kms_guardduty_ec2_malware" {
  count               = local.enable_malware_notifications ? 1 : 0
  description         = "KMS key for encrypting SNS topic for GuardDuty EC2 malware"
  enable_key_rotation = true
}

# Attach an Alias for the KMS Key 
resource "aws_kms_alias" "alias_guardduty_ec2_malware" {
  count         = local.enable_malware_notifications ? 1 : 0
  name          = "alias/guardduty_ec2_malware"
  target_key_id = aws_kms_key.kms_guardduty_ec2_malware[0].id
}

resource "aws_kms_key_policy" "sns_kms_key_policy" {
  count  = local.enable_malware_notifications ? 1 : 0
  key_id = aws_kms_key.kms_guardduty_ec2_malware[0].id
  policy = data.aws_iam_policy_document.sns_kms_key_policy[0].json
}

data "aws_iam_policy_document" "sns_kms_key_policy" {
  # checkov:skip=CKV_AWS_109: "Key policy requires asterisk resource"
  # checkov:skip=CKV_AWS_111: "Key policy requires asterisk resource"
  # checkov:skip=CKV_AWS_356: "Key policy requires asterisk resource"
  count = local.enable_malware_notifications ? 1 : 0
  statement {
    sid       = "Allow management access of the key to the core-shared-services-account"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowSNSandEventBridgeToUseKMSKey"
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt"
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com", "events.amazonaws.com"]
    }
  }
}


# SNS Topic
resource "aws_sns_topic" "sns_guardduty_ec2_malware" {
  count             = local.enable_malware_notifications ? 1 : 0
  name              = "guardduty_ec2_malware"
  kms_master_key_id = aws_kms_key.kms_guardduty_ec2_malware[0].arn
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "sns_policy_guardduty_ec2_malware" {
  count  = local.enable_malware_notifications ? 1 : 0
  arn    = aws_sns_topic.sns_guardduty_ec2_malware[0].arn
  policy = data.aws_iam_policy_document.s3_malware_scan_sns_policy[0].json
}

#  IAM Policy Document for SNS Permissions 
data "aws_iam_policy_document" "s3_malware_scan_sns_policy" {
  count     = local.enable_malware_notifications ? 1 : 0
  policy_id = "s3 malware scan sns policy"
  statement {
    sid    = "AllowTopicOwnerToManageSNS"
    effect = "Allow"
    actions = [
      "sns:Publish",
      "sns:RemovePermission",
      "sns:SetTopicAttributes",
      "sns:DeleteTopic",
      "sns:ListSubscriptionsByTopic",
      "sns:GetTopicAttributes",
      "sns:AddPermission",
      "sns:Subscribe"
    ]
    resources = [
      aws_sns_topic.sns_guardduty_ec2_malware[0].arn
    ]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values = [
        data.aws_caller_identity.current.account_id
      ]
    }
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }

  ###  Allow EventBridge to Publish Messages to SNS
  statement {
    sid    = "AllowEventBridgeToPublishToSNS"
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = [
      aws_sns_topic.sns_guardduty_ec2_malware[0].arn
    ]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

# EventBridge IAM Role
resource "aws_iam_role" "eventbridge_guardduty_ec2_malware" {
  count = local.enable_malware_notifications ? 1 : 0

  name = "guardduty_ec2_malware"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_guardduty_ec2_malware" {
  count = local.enable_malware_notifications ? 1 : 0
  name  = "guardduty_ec2_malware"
  role  = aws_iam_role.eventbridge_guardduty_ec2_malware[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.sns_guardduty_ec2_malware[0].arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.kms_guardduty_ec2_malware[0].arn
      }
    ]
  })
}

# EventBridge Rule
resource "aws_cloudwatch_event_rule" "eb_rule_guardduty_ec2_malware" {
  count       = local.enable_malware_notifications ? 1 : 0
  name        = "guardduty_ec2_malware_alert"
  description = "Trigger SNS on GuardDuty EC2 malware findings"

  event_pattern = jsonencode({
    source = ["aws.guardduty"]
    detail = {
      type = ["Execution:EC2/MaliciousFile"]
    }
  })
}

# EventBridge Target (SNS)
resource "aws_cloudwatch_event_target" "eb_target_sns_guardduty_ec2_malware" {
  count     = local.enable_malware_notifications ? 1 : 0
  rule      = aws_cloudwatch_event_rule.eb_rule_guardduty_ec2_malware[0].name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.sns_guardduty_ec2_malware[0].arn
  role_arn  = aws_iam_role.eventbridge_guardduty_ec2_malware[0].arn
}

# link the sns topics to the pagerduty service
module "pagerduty_malware_alerts" {
  count                     = local.enable_malware_notifications ? 1 : 0
  depends_on                = [aws_sns_topic.sns_guardduty_ec2_malware]
  source                    = "github.com/ministryofjustice/modernisation-platform-terraform-pagerduty-integration?ref=d88bd90d490268896670a898edfaba24bba2f8ab" # v3.0.0
  sns_topics                = [aws_sns_topic.sns_guardduty_ec2_malware[0].name]
  pagerduty_integration_key = local.pagerduty_integration_keys["core_alerts_high_priority_cloudwatch"]
}


# GuardDuty Malware Protection Role

module "guardduty_malware_protection_role" {
  # checkov:skip=CKV_TF_1:
  count  = local.account_data.account-type == "member" || local.account_data.account-type == "core" ? 1 : 0
  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-assumable-role?ref=e20e0b9a42084bbc885fd5abb18b8744810bd567" # v5.48.0

  trusted_role_services = [
    "malware-protection-plan.guardduty.amazonaws.com"
  ]
  create_role       = true
  role_name         = "GuardDutyS3MalwareProtectionRole"
  role_requires_mfa = false

  custom_role_policy_arns = [
    aws_iam_policy.guardduty_policy.arn
  ]
  number_of_custom_role_policy_arns = 1
}

#  Attach IAM policy to the role
resource "aws_iam_role_policy_attachment" "guardduty_malware_protection_attach" {
  count      = local.account_data.account-type == "member" || local.account_data.account-type == "core" ? 1 : 0
  role       = module.guardduty_malware_protection_role[0].iam_role_name
  policy_arn = aws_iam_policy.guardduty_policy.arn
}

# IAM Policy for GuardDuty Malware Protection
resource "aws_iam_policy" "guardduty_policy" {
  name        = "GuardDutyMalwareProtectionPolicy"
  description = "Policy for GuardDuty Malware Protection Plan"
  policy      = data.aws_iam_policy_document.guardduty_malware_protection_policy.json
}

# IAM Policy Document for GuardDuty Malware Protection
data "aws_iam_policy_document" "guardduty_malware_protection_policy" {
  statement {
    sid    = "EventBridgeActionsForGuardDuty"
    effect = "Allow"
    actions = [
      "events:*Rule",
      "events:*Targets",
      "events:DescribeRule",
      "events:ListTargetsByRule"
    ]
    resources = [
    "arn:aws:events:eu-west-2:${local.environment_management.account_ids[terraform.workspace]}:rule/DO-NOT-DELETE-AmazonGuardDutyMalwareProtectionS3*"]
    condition {
      test     = "StringLike"
      variable = "events:ManagedBy"
      values   = ["malware-protection-plan.guardduty.amazonaws.com"]
    }
  }
  statement {
    sid    = "S3ActionsForGuardDuty"
    effect = "Allow"
    actions = [
      "s3:PutObject*",
      "s3:GetObject*",
      "s3:GetBucket*",
      "s3:ListBucket",
      "s3:PutBucketNotification",
      "s3:GetBucketNotification"
    ]
    resources = [
      "arn:aws:s3:::*/malware-protection-resource-validation-object",
      "arn:aws:s3:::*"
    ]
    condition {
      test     = "ForAllValues:StringEqualsIfExists"
      variable = "aws:CalledVia"
      values   = ["guardduty.amazonaws.com"]
    }
  }
  statement {
    sid    = "AllowDecryptForMalwareScan"
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt"
    ]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values   = ["s3.eu-west-2.amazonaws.com"]
    }
  }
}


locals {
  account_name = try(regex("^bichard*.|^remote-supervisio*.", terraform.workspace), replace(terraform.workspace, regex("-[^-]*$", terraform.workspace), ""))
  account_data = jsondecode(file("../../../../environments/${local.account_name}.json"))

  wiz_base_account_name = replace(terraform.workspace, regex("-[^-]*$", terraform.workspace), "")

  wiz_resource_count_allowlist = toset([
    "apex",
    "ccms-ebs-upgrade",
    "ccms-ebs",
    "ccms-edrms",
    "ccms-oia",
    "ccms-pui-internal",
    "ccms-pui",
    "contract-work-administration",
    "laa-ccms-soa",
    "laa-cst-security-dashboard",
    "laa-enterprise-service-bus",
    "laa-mail-relay",
    "laa-oem",
    "laa-pui-secure-browser",
    "laa-stabilisation-cdc-poc",
    "maat",
    "maatdb",
    "mlra",
    "mojfin",
    "oas",
    "portal",
    "cooker",
    "sprinkler",
  ])

  wiz_role_enabled = contains(local.wiz_resource_count_allowlist, local.wiz_base_account_name)
}

#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "wiz_resource_count" {
  #checkov:skip=CKV_AWS_356: Needs to access multiple resources
  count = local.wiz_role_enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "sts:GetCallerIdentity",

      "ec2:DescribeRegions",
      "ec2:DescribeInstances",

      "lightsail:GetRegions",
      "lightsail:GetInstances",

      "ecs:ListClusters",
      "ecs:ListContainerInstances",
      "ecs:ListTasks",
      "ecs:DescribeTasks",

      "eks:ListClusters",
      "eks:DescribeCluster",
      "eks:ListFargateProfiles",

      "lambda:ListFunctions",
      "lambda:ListVersionsByFunction",

      "sagemaker:ListDomains",
      "sagemaker:ListEndpoints",

      "ecr:DescribeRepositories",
      "ecr:ListImages",

      "s3:ListAllMyBuckets",
      "docdb:DescribeDBClusters",
      "rds:DescribeDBClusters",
      "rds:DescribeDBInstances",
      "redshift:DescribeClusters",
      "dynamodb:ListTables"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "wiz_resource_count" {
  count       = local.wiz_role_enabled ? 1 : 0
  name        = "WizResourceCountReadOnly"
  description = "Read-only permissions for wiz/resource-count-aws-v2.py (supports --data and --images)"
  policy      = data.aws_iam_policy_document.wiz_resource_count[0].json
}

module "wiz-resource-count-access" {
  count      = local.wiz_role_enabled ? 1 : 0
  source     = "github.com/ministryofjustice/modernisation-platform-terraform-cross-account-access?ref=321b0bcb8699b952a2a66f60c6242876048480d5"
  account_id = data.aws_ssm_parameter.modernisation_platform_account_id.value
  additional_trust_roles = [
    one(data.aws_iam_roles.member-sso-admin-access.arns)
  ]
  policy_arn = aws_iam_policy.wiz_resource_count[0].arn
  role_name  = "WizResourceCountAccess"
}

module "member-access" {
  count      = (local.account_data.account-type == "member" && terraform.workspace != "testing-test" && terraform.workspace != "sprinkler-development") ? 1 : 0
  source     = "github.com/ministryofjustice/modernisation-platform-terraform-cross-account-access?ref=321b0bcb8699b952a2a66f60c6242876048480d5" #v4.0.0
  account_id = data.aws_ssm_parameter.modernisation_platform_account_id.value
  additional_trust_roles = compact([
    module.github-oidc[0].github_actions_role,
    try(module.github_actions_terraform_dev_test[0].role, null),
    one(data.aws_iam_roles.member-sso-admin-access.arns),
  ])
  role_name = "MemberInfrastructureAccess"
}

resource "aws_iam_role_policy_attachment" "member_infrastructure_access_role_compute" {
  count      = (local.account_data.account-type == "member" && terraform.workspace != "testing-test" && terraform.workspace != "sprinkler-development") ? 1 : 0
  role       = "MemberInfrastructureAccess"
  policy_arn = aws_iam_policy.member-access-compute[0].arn
}

resource "aws_iam_role_policy_attachment" "member_infrastructure_access_role_data" {
  count      = (local.account_data.account-type == "member" && terraform.workspace != "testing-test" && terraform.workspace != "sprinkler-development") ? 1 : 0
  role       = "MemberInfrastructureAccess"
  policy_arn = aws_iam_policy.member-access-data[0].arn
}

resource "aws_iam_role_policy_attachment" "member_infrastructure_access_role_network" {
  count      = (local.account_data.account-type == "member" && terraform.workspace != "testing-test" && terraform.workspace != "sprinkler-development") ? 1 : 0
  role       = "MemberInfrastructureAccess"
  policy_arn = aws_iam_policy.member-access-network[0].arn
}

module "member-access-sprinkler" {
  count                  = (terraform.workspace == "sprinkler-development") ? 1 : 0
  source                 = "github.com/ministryofjustice/modernisation-platform-terraform-cross-account-access?ref=321b0bcb8699b952a2a66f60c6242876048480d5" #v4.0.0
  account_id             = data.aws_ssm_parameter.modernisation_platform_account_id.value
  additional_trust_roles = [data.aws_iam_role.sprinkler_oidc[0].arn, data.aws_iam_role.sprinkler_environments_read_only[0].arn, data.aws_iam_role.sprinkler_environments_dev_test[0].arn, one(data.aws_iam_roles.member-sso-admin-access.arns)]
  role_name              = "MemberInfrastructureAccess"
}

resource "aws_iam_role_policy_attachment" "member_infrastructure_access_sprinkler_role_compute" {
  count      = (terraform.workspace == "sprinkler-development") ? 1 : 0
  role       = "MemberInfrastructureAccess"
  policy_arn = aws_iam_policy.member-access-compute[0].arn
}

resource "aws_iam_role_policy_attachment" "member_infrastructure_access_sprinkler_role_data" {
  count      = (terraform.workspace == "sprinkler-development") ? 1 : 0
  role       = "MemberInfrastructureAccess"
  policy_arn = aws_iam_policy.member-access-data[0].arn
}

resource "aws_iam_role_policy_attachment" "member_infrastructure_access_sprinkler_role_network" {
  count      = (terraform.workspace == "sprinkler-development") ? 1 : 0
  role       = "MemberInfrastructureAccess"
  policy_arn = aws_iam_policy.member-access-network[0].arn
}


# Policy 1: Compute, Containers, and Core Services
#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "member-access-compute" {
  statement {
    #checkov:skip=CKV_AWS_108
    #checkov:skip=CKV_AWS_111
    #checkov:skip=CKV_AWS_107
    #checkov:skip=CKV_AWS_109
    #checkov:skip=CKV_AWS_110
    #checkov:skip=CKV2_AWS_40
    #checkov:skip=CKV_AWS_356: Needs to access multiple resources
    effect = "Allow"
    actions = [
      "acm-pca:*",
      "acm:*",
      "airflow:*",
      "apigateway:*",
      "application-autoscaling:*",
      "applicationinsights:*",
      "autoscaling:*",
      "backup:*",
      "backup-storage:MountCapsule",
      "cloudformation:*",
      "cloudfront:*",
      "cloudwatch:*",
      "cloudtrail:AddTags",
      "cloudtrail:CancelQuery",
      "cloudtrail:Create*",
      "cloudtrail:StartLogging",
      "cloudtrail:PutEventSelectors",
      "cloudtrail:DescribeTrails",
      "cloudtrail:Get*",
      "cloudtrail:List*",
      "codebuild:*",
      "codedeploy:*",
      "codepipeline:*",
      "cognito-idp:*",
      "config:*",
      "ds:*",
      "ec2:AssociateVpcCidrBlock",
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:DisassociateVpcCidrBlock",
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:*RouteTable*",
      "ec2:CreateVpcEndpoint",
      "ec2:DeleteVpcEndpoints",
      "ec2:CreateVpcEndpointServiceConfiguration",
      "ec2:DeleteVpcEndpointServiceConfigurations",
      "ec2:CreateVpcPeeringConnection",
      "ec2:DeleteVpcPeeringConnection",
      "ec2:DisableSerialConsoleAccess",
      "ec2:EnableSerialConsoleAccess",
      "ec2:GetSerialConsoleAccessStatus",
      "ec2:ModifyVpc*",
      "ec2:Describe*",
      "ec2:*NetworkAcl*",
      "ec2:*FlowLogs",
      "ec2:*SecurityGroup*",
      "ec2:*KeyPair*",
      "ec2:*Tags*",
      "ec2:*Volume*",
      "ec2:*Snapshot*",
      "ec2:*Ebs*",
      "ec2:*NetworkInterface*",
      "ec2:*Address*",
      "ec2:*Image*",
      "ec2:*Event*",
      "ec2:*Instance*",
      "ec2:*CapacityReservation*",
      "ec2:*Fleet*",
      "ec2:Get*",
      "ec2:SendDiagnosticInterrupt",
      "ec2:*LaunchTemplate*",
      "ec2:*PlacementGroup*",
      "ec2:*IdFormat*",
      "ec2:*Spot*",
      "ec2:*InternetGateway*",
      "ec2:*NatGateway*",
      "ec2:*TransitGatewayVpcAttachment*",
      "ec2:*ManagedPrefixList*",
      "ec2:*EncryptionControl*",
      "ecr-public:*",
      "ecr:*",
      "ecs:*",
      "eks:*",
      "elasticloadbalancing:*",
      "events:*",
      "fis:*",
      "iam:*",
      "kms:*",
      "lambda:*",
      "logs:*",
      "workspaces:*",
      "workspaces-web:*"
    ]
    resources = ["*"] #tfsec:ignore:AWS099 tfsec:ignore:AWS097
  }
}

# Policy 2: Data and Analytics Services
#tfsec:ignore:aws-iam-no-policy-wildcards
#trivy:ignore:AVD-AWS-0345: Required for member account access to S3
data "aws_iam_policy_document" "member-access-data" {
  statement {
    #checkov:skip=CKV_AWS_108
    #checkov:skip=CKV_AWS_111
    #checkov:skip=CKV_AWS_107
    #checkov:skip=CKV_AWS_109
    #checkov:skip=CKV_AWS_110
    #checkov:skip=CKV2_AWS_40
    #checkov:skip=CKV_AWS_356: Needs to access multiple resources
    effect = "Allow"
    actions = [
      "athena:*",
      "datasync:*",
      "dbqms:*",
      "dlm:*",
      "dms:*",
      "dynamodb:*",
      "ebs:*",
      "elasticache:*",
      "elasticfilesystem:*",
      "es:*",
      "fsx:*",
      "glacier:*",
      "glue:*",
      "kinesis:*",
      "kinesisanalytics:*Application*",
      "kinesisanalytics:*Resource",
      "lakeformation:*",
      "macie2:*",
      "quicksight:*",
      "rds-db:*",
      "rds:*",
      "rds-data:*",
      "redshift:*",
      "redshift-data:*",
      "redshift-serverless:*",
      "s3:*",
      "firehose:*"
    ]
    resources = ["*"] #tfsec:ignore:AWS099 tfsec:ignore:AWS097
  }
}

# Policy 3: Networking, Security, and Additional Services
#tfsec:ignore:aws-iam-no-policy-wildcards
#trivy:ignore:AVD-AWS-0345: Required for member account access to S3
data "aws_iam_policy_document" "member-access-network" {
  statement {
    #checkov:skip=CKV_AWS_108
    #checkov:skip=CKV_AWS_111
    #checkov:skip=CKV_AWS_107
    #checkov:skip=CKV_AWS_109
    #checkov:skip=CKV_AWS_110
    #checkov:skip=CKV2_AWS_40
    #checkov:skip=CKV_AWS_356: Needs to access multiple resources
    effect = "Allow"
    actions = [
      "aps:*",
      "aoss:*",
      "bcm-data-exports:*",
      "bedrock:*",
      "chatbot:*",
      "cur:DeleteReportDefinition",
      "cur:DescribeReportDefinitions",
      "cur:ListTagsForResource",
      "cur:PutReportDefinition",
      "ds:CheckAlias",
      "ds:Describe*",
      "ds:List*",
      "ds:*Tags*",
      "ds:CancelSchemaExtension",
      "ds:CreateComputer",
      "ds:CreateAlias",
      "ds:CreateDirectory",
      "ds:CreateLogSubscription",
      "ds:CreateMicrosoftAD",
      "ds:CreateSnapshot",
      "ds:CreateTrust",
      "ds:Delete*",
      "ds:Deregister*",
      "ds:Disable*",
      "ds:Enable*",
      "ds:RegisterCertificate",
      "ds:RegisterEventTopic",
      "ds:ResetUserPassword",
      "ds:RestoreFromSnapshot",
      "ds:StartSchemaExtension",
      "ds:Update*",
      "ds:VerifyTrust",
      "ds-data:*",
      "grafana:*",
      "guardduty:get*",
      "networkflowmonitor:*",
      "networkmonitor:*",
      "network-firewall:*",
      "organizations:Describe*",
      "organizations:List*",
      "oam:*",
      "ram:AssociateResourceShare",
      "ram:CreateResourceShare",
      "ram:DeleteResourceShare",
      "ram:Get*",
      "ram:List*",
      "route53:*",
      "route53resolver:*",
      "scheduler:*",
      "secretsmanager:*",
      "ses:*",
      "shield:*",
      "signer:*",
      "sns:*",
      "sqs:*",
      "ssm:*",
      "sso:CreateApplicationAssignment",
      "sso:DeleteApplicationAssignment",
      "sso:DescribeApplicationAssignment",
      "sso:DescribeRegisteredRegions",
      "sso:GetApplicationAssignmentConfiguration",
      "sso:GetSharedSsoConfiguration",
      "sso:ListApplicationAssignments",
      "sso:ListApplicationAssignmentsForPrincipal",
      "sso:ListDirectoryAssociations",
      "sso:GetManagedApplicationInstance",
      "sso:ListProfiles",
      "sso:AssociateProfile",
      "sso:DisassociateProfile",
      "sso:GetProfile",
      "sso:CreateApplication",
      "sso:ListInstances",
      "sso:DeleteApplication",
      "sso:PutApplicationAssignmentConfiguration",
      "sso:PutApplicationGrant",
      "sso:PutApplicationAuthenticationMethod",
      "sso:ListProfileAssociations",
      "sso-directory:DescribeUser",
      "sso-directory:DescribeGroup",
      "states:*",
      "synthetics:*",
      "tag:ListRequiredTags",
      "waf:*",
      "wafv2:*",
      "resource-groups:*",
      "resource-explorer-2:*",
      "transfer:*",
      "vpce:*",
      "sagemaker:*"
    ]
    resources = ["*"] #tfsec:ignore:AWS099 tfsec:ignore:AWS097
  }
  statement {
    effect    = "Allow"
    actions   = ["cloudtrail:DeleteTrail"]
    resources = ["arn:aws:cloudtrail:*:*:trail/cloudtrail-test*"]
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values = [
        local.environment_management.account_ids["testing-test"]
      ]
    }
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:DeleteObject"]
    resources = ["arn:aws:s3:::cloudtrail-test*/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values = [
        local.environment_management.account_ids["testing-test"]
      ]
    }
  }
  statement {
    sid    = "GuardDutyMalwareProtectionActions"
    effect = "Allow"
    actions = [
      "guardduty:CreateMalwareProtectionPlan",
      "guardduty:DeleteMalwareProtectionPlan",
      "guardduty:ListDetectors",
      "guardduty:ListTagsForResource",
      "guardduty:TagResource",
      "guardduty:UpdateMalwareProtectionPlan"
    ]
    resources = [
      "arn:aws:guardduty:eu-west-2:*:malware-protection-plan/*"
    ]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:CalledVia"
      values   = ["guardduty.amazonaws.com"]
    }
  }
  # Only grant Rekognition permissions for e-supervision application
  statement {
    effect    = "Allow"
    actions   = ["rekognition:*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values = [
        local.environment_management.account_ids["hmpps-esupervision-development"],
        local.environment_management.account_ids["hmpps-esupervision-production"]
      ]
    }
  }
  statement {
    effect = "Deny"
    actions = [
      "iam:AddUserToGroup",
      "iam:AttachGroupPolicy",
      "iam:CreateAccountAlias",
      "iam:CreateGroup",
      "iam:CreateLoginProfile",
      "iam:CreateSAMLProvider",
      "iam:CreateVirtualMFADevice",
      "iam:DeactivateMFADevice",
      "iam:DeleteAccountAlias",
      "iam:DeleteAccountPasswordPolicy",
      "iam:DeleteGroup",
      "iam:DeleteGroupPolicy",
      "iam:DeleteLoginProfile",
      "iam:DeleteSAMLProvider",
      "iam:DeleteUserPermissionsBoundary",
      "iam:DeleteVirtualMFADevice",
      "iam:DetachGroupPolicy",
      "iam:EnableMFADevice",
      "iam:RemoveUserFromGroup",
      "iam:ResyncMFADevice",
      "iam:UpdateAccountPasswordPolicy",
      "iam:UpdateGroup",
      "iam:UpdateLoginProfile",
      "iam:UpdateSAMLProvider",
      "iam:UpdateUser"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Deny"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DeleteRole",
      "iam:DeleteRolePermissionsBoundary",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePermissionsBoundary",
      "iam:PutRolePolicy",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription"
    ]
    resources = ["arn:aws:iam::*:user/cicd-member-user"]
  }
  statement {
    actions = ["iam:PassRole"]
    effect  = "Deny"
    resources = [
      "arn:aws:iam::${local.environment_management.account_ids[terraform.workspace]}:role/GuardDutyS3MalwareProtectionRole"
    ]
    condition {
      test     = "StringNotEquals"
      variable = "iam:PassedToService"
      values = [
        "malware-protection-plan.guardduty.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_policy" "member-access-compute" {
  count       = local.account_data.account-type == "member" ? 1 : 0
  name        = "MemberInfrastructureAccessActionsCompute"
  description = "Restricted admin policy for member CI/CD - Compute services"
  policy      = data.aws_iam_policy_document.member-access-compute.json
}

resource "aws_iam_policy" "member-access-data" {
  count       = local.account_data.account-type == "member" ? 1 : 0
  name        = "MemberInfrastructureAccessActionsData"
  description = "Restricted admin policy for member CI/CD - Data services"
  policy      = data.aws_iam_policy_document.member-access-data.json
}

resource "aws_iam_policy" "member-access-network" {
  count       = local.account_data.account-type == "member" ? 1 : 0
  name        = "MemberInfrastructureAccessActionsNetwork"
  description = "Restricted admin policy for member CI/CD - Network and security services"
  policy      = data.aws_iam_policy_document.member-access-network.json
}

# Legacy policy name kept for backwards compatibility - combines all three
resource "aws_iam_policy" "member-access" {
  count       = 0 # Deprecated - use split policies instead
  name        = "MemberInfrastructureAccessActions"
  description = "Deprecated - split into multiple policies"
  policy      = data.aws_iam_policy_document.member-access-compute.json
}

# Testing-test member access - separate as need the testing user created in the testing account to be able to access as well
data "aws_iam_policy_document" "assume_role_policy" {
  version = "2012-10-17"

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_ssm_parameter.modernisation_platform_account_id.value}:root",
        "arn:aws:iam::${local.environment_management.account_ids[terraform.workspace]}:user/testing-ci",
        one(data.aws_iam_roles.member-sso-admin-access.arns)
      ]
    }
  }
}

# IAM role to be assumed
resource "aws_iam_role" "testing_member_infrastructure_access_role" {
  count              = terraform.workspace == "testing-test" ? 1 : 0
  name               = "MemberInfrastructureAccess"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

# IAM role attached policies
resource "aws_iam_role_policy_attachment" "testing_member_infrastructure_access_role_compute" {
  count      = terraform.workspace == "testing-test" ? 1 : 0
  role       = aws_iam_role.testing_member_infrastructure_access_role[0].id
  policy_arn = aws_iam_policy.member-access-compute[0].arn
}

resource "aws_iam_role_policy_attachment" "testing_member_infrastructure_access_role_data" {
  count      = terraform.workspace == "testing-test" ? 1 : 0
  role       = aws_iam_role.testing_member_infrastructure_access_role[0].id
  policy_arn = aws_iam_policy.member-access-data[0].arn
}

resource "aws_iam_role_policy_attachment" "testing_member_infrastructure_access_role_network" {
  count      = terraform.workspace == "testing-test" ? 1 : 0
  role       = aws_iam_role.testing_member_infrastructure_access_role[0].id
  policy_arn = aws_iam_policy.member-access-network[0].arn
}

# MemberInfrastructureAccessUSEast
module "member-access-us-east" {
  count      = (local.account_data.account-type == "member" && terraform.workspace != "testing-test" && terraform.workspace != "sprinkler-development") ? 1 : 0
  source     = "github.com/ministryofjustice/modernisation-platform-terraform-cross-account-access?ref=321b0bcb8699b952a2a66f60c6242876048480d5" #v4.0.0
  account_id = data.aws_ssm_parameter.modernisation_platform_account_id.value
  additional_trust_roles = compact([
    module.github-oidc[0].github_actions_role,
    try(module.github_actions_terraform_dev_test[0].role, null),
    one(data.aws_iam_roles.member-sso-admin-access.arns),
  ])
  policy_arn = aws_iam_policy.member-access-us-east[0].id
  role_name  = "MemberInfrastructureAccessUSEast"
}

module "member-access-us-east-sprinkler" {
  count                  = (terraform.workspace == "sprinkler-development") ? 1 : 0
  source                 = "github.com/ministryofjustice/modernisation-platform-terraform-cross-account-access?ref=321b0bcb8699b952a2a66f60c6242876048480d5" #v4.0.0
  account_id             = data.aws_ssm_parameter.modernisation_platform_account_id.value
  additional_trust_roles = [data.aws_iam_role.sprinkler_oidc[0].arn, data.aws_iam_role.sprinkler_environments_read_only[0].arn, data.aws_iam_role.sprinkler_environments_dev_test[0].arn, one(data.aws_iam_roles.member-sso-admin-access.arns)]
  policy_arn             = aws_iam_policy.member-access-us-east[0].id
  role_name              = "MemberInfrastructureAccessUSEast"
}

# lots of SCA ignores and skips on this one as it is the main role allowing members to build most things in the platform
#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "member-access-us-east" {
  statement {
    #checkov:skip=CKV_AWS_108
    #checkov:skip=CKV_AWS_111
    #checkov:skip=CKV_AWS_107
    #checkov:skip=CKV_AWS_109
    #checkov:skip=CKV_AWS_110
    #checkov:skip=CKV2_AWS_40
    #checkov:skip=CKV_AWS_356: Needs to access multiple resources
    effect = "Allow"
    actions = [
      "acm:*",
      "iam:ListRoles",
      "lambda:*",
      "logs:*",
      "waf:*",
      "wafv2:*",
      "cur:PutReportDefinition",
      "cur:DeleteReportDefinition",
      "cur:ModifyReportDefinition",
      "cur:DescribeReportDefinitions"
    ]
    resources = ["*"] #tfsec:ignore:AWS099 tfsec:ignore:AWS097
  }
  statement {
    effect = "Deny"
    actions = [
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:AddUserToGroup",
      "iam:AttachGroupPolicy",
      "iam:AttachUserPolicy",
      "iam:CreateAccountAlias",
      "iam:CreateGroup",
      "iam:CreateLoginProfile",
      "iam:CreateOpenIDConnectProvider",
      "iam:CreateSAMLProvider",
      "iam:CreateUser",
      "iam:CreateVirtualMFADevice",
      "iam:DeactivateMFADevice",
      "iam:DeleteAccountAlias",
      "iam:DeleteAccountPasswordPolicy",
      "iam:DeleteGroup",
      "iam:DeleteGroupPolicy",
      "iam:DeleteLoginProfile",
      "iam:DeleteOpenIDConnectProvider",
      "iam:DeleteSAMLProvider",
      "iam:DeleteUser",
      "iam:DeleteUserPermissionsBoundary",
      "iam:DeleteUserPolicy",
      "iam:DeleteVirtualMFADevice",
      "iam:DetachGroupPolicy",
      "iam:DetachUserPolicy",
      "iam:EnableMFADevice",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
      "iam:RemoveUserFromGroup",
      "iam:ResyncMFADevice",
      "iam:UpdateAccountPasswordPolicy",
      "iam:UpdateGroup",
      "iam:UpdateLoginProfile",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:UpdateSAMLProvider",
      "iam:UpdateUser"
    ]
    resources = ["*"]
  }

  statement {
    actions   = ["iam:PassRole"]
    effect    = "Deny"
    resources = ["arn:aws:iam::*:role/MemberInfrastructureAccessUSEast"]
  }

  statement {
    actions   = ["iam:PassRole"]
    effect    = "Allow"
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

}

resource "aws_iam_policy" "member-access-us-east" {
  count       = local.account_data.account-type == "member" ? 1 : 0
  name        = "MemberInfrastructureAccessUSEastActions"
  description = "Restricted policy for US East usage"
  policy      = data.aws_iam_policy_document.member-access-us-east.json
}

# Github OIDC role
module "github_oidc_role" {
  count                = length(compact(jsondecode(data.http.environments_file.response_body).github-oidc-team-repositories)) > 0 ? 1 : 0
  source               = "github.com/ministryofjustice/modernisation-platform-github-oidc-role?ref=b40748ec162b446f8f8d282f767a85b6501fd192" # v4.0.0
  github_repositories  = jsondecode(data.http.environments_file.response_body).github-oidc-team-repositories
  max_session_duration = 21600
  role_name            = "modernisation-platform-oidc-cicd"
  policy_jsons         = [data.aws_iam_policy_document.policy.json]
  tags                 = local.tags
}

#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "policy" {
  #checkov:skip=CKV_AWS_289
  #checkov:skip=CKV_AWS_288
  #checkov:skip=CKV_AWS_290
  #checkov:skip=CKV_AWS_355: Allows access to multiple unknown resources
  statement {
    #checkov:skip=CKV_AWS_108
    #checkov:skip=CKV_AWS_111
    #checkov:skip=CKV_AWS_107
    #checkov:skip=CKV_AWS_109
    #checkov:skip=CKV_AWS_110
    #checkov:skip=CKV2_AWS_40
    #checkov:skip=CKV_AWS_356: Needs to access multiple resources
    effect = "Allow"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "autoscaling:PutScheduledUpdateGroupAction",
      "autoscaling:SetDesiredCapacity",
      "backup:*",
      "cloudwatch:PutMetricData",
      "codebuild:Start*",
      "codebuild:StartBuild",
      "codebuild:BatchGetBuilds",
      "codepipeline:StartPipelineExecution",
      "datasync:Create*",
      "datasync:Delete*",
      "datasync:Describe*",
      "datasync:List*",
      "datasync:StartTaskExecution",
      "datasync:*Tag*",
      "dms:StartReplicationTask",
      "dms:StopReplicationTask",
      "dms:TestConnection",
      "dms:StartReplicationTaskAssessment",
      "dms:StartReplicationTaskAssessmentRun",
      "dms:DescribeEndpoints",
      "dms:DescribeEndpointSettings",
      "dms:*Certificate",
      "dms:ModifyEndpoint",
      "dms:RebootReplicationInstance",
      "ds:AccessDSData",
      "ds:DescribeDirectories",
      "ds:EnableDirectoryDataAccess",
      "ds:ResetUserPassword",
      "ds-data:*",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "ecs:ExecuteCommand",
      "ecs:*Service*",
      "ecs:*Task*",
      "ecs:*Tag*",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:GetAuthorizationToken",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:UploadLayerPart",
      "ec2:DescribeInstances",
      "ec2:CreateNetworkInterface",
      "ec2:CreateNetworkInterfacePermission",
      "ec2:AttachNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DeregisterImage",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeNetworkInterfaces",
      "ec2:ModifyNetworkInterfaceAttribute",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "elasticfilesystem:Describe*",
      "elasticfilesystem:Create*",
      "elasticfilesystem:Delete*",
      "elasticfilesystem:restore",
      "elasticloadbalancing:SetRulePriorities",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:ModifyListener",
      "glue:GetJobRuns",
      "glue:StartJobRun",
      "glue:GetJobs",
      "glue:GetTable",
      "glue:BatchGetJobs",
      "glue:ListJobs",
      "glue:StartJobRun",
      "glue:StartTrigger",
      "glue:StopSession",
      "glue:StopTrigger",
      "glue:BatchStopJobRun",
      "glue:StopWorkflowRun",
      "glue:UpdateJob",
      "iam:getRole",
      "iam:getRolePolicy",
      "iam:listAttachedRolePolicies",
      "iam:listInstanceProfilesForRole",
      "iam:listRolePolicies",
      "iam:ListRoles",
      "kinesis:PutRecord",
      "kms:DescribeKey",
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "lambda:GetCodeSigningConfig",
      "lambda:UpdateFunctionCode",
      "logs:CreateLogGroup",
      "logs:DescribeLogGroups",
      "logs:DescribeResourcePolicies",
      "logs:GetLogEvents",
      "rds:*Tag*",
      "rds:*Snapshot*",
      "rds:StartDBInstance",
      "rds:StopDBInstance",
      "route53:ChangeResourceRecordSets",
      "route53:GetHostedZone",
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListAllMyBuckets",
      "s3:*Object*",
      "s3:*Tag*",
      "quicksight:*",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:GetSecretValue",
      "secretsmanager:ListSecrets",
      "secretsmanager:PutSecretValue",
      "secretsmanager:RotateSecret",
      "secretsmanager:UpdateSecretVersionStage",
      "ses:*SuppressedDestination",
      "ssm:GetParameter",
      "ssm:PutParameter",
      "ssm:DescribeSessions",
      "ssm:ResumeSession",
      "ssm:SendCommand",
      "ssm:StartSession",
      "ssm:TerminateSession",
      "vpc:DescribeSubnets"
    ]
    resources = ["*"] #tfsec:ignore:AWS099 tfsec:ignore:AWS097
  }

  statement {
    actions = ["iam:PassRole"]
    effect  = "Allow"
    resources = [
      "arn:aws:iam::${local.environment_management.account_ids[terraform.workspace]}:role/*"
    ]
    condition {
      test     = "StringEquals"
      values   = ["ssm.amazonaws.com", "ecs.amazonaws.com", "ecs-tasks.amazonaws.com", "backup.amazonaws.com", "datasync.amazonaws.com"]
      variable = "iam:PassedToService"
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:CreateGrant"
    ]

    resources = [
      "arn:aws:kms:eu-west-2:${local.environment_management.account_ids["core-shared-services-production"]}:key/*",
      "arn:aws:kms:eu-west-2:${local.environment_management.account_ids["electronic-monitoring-data-development"]}:key/*",
      "arn:aws:kms:eu-west-2:${local.environment_management.account_ids["electronic-monitoring-data-test"]}:key/*",
      "arn:aws:kms:eu-west-2:${local.environment_management.account_ids["electronic-monitoring-data-preproduction"]}:key/*",
      "arn:aws:kms:eu-west-2:${local.environment_management.account_ids["electronic-monitoring-data-production"]}:key/*"
    ]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

# MemberInfrastructureBedrockEuCentral
module "member-access-eu-central" {
  count      = (local.account_data.account-type == "member" && terraform.workspace != "testing-test" && terraform.workspace != "sprinkler-development") ? 1 : 0
  source     = "github.com/ministryofjustice/modernisation-platform-terraform-cross-account-access?ref=321b0bcb8699b952a2a66f60c6242876048480d5" #v4.0.0
  account_id = data.aws_ssm_parameter.modernisation_platform_account_id.value
  additional_trust_roles = compact([
    module.github-oidc[0].github_actions_role,
    try(module.github_actions_terraform_dev_test[0].role, null),
    one(data.aws_iam_roles.member-sso-admin-access.arns),
  ])
  policy_arn = aws_iam_policy.member-access-eu-central[0].id
  role_name  = "MemberInfrastructureBedrockEuCentral"
}

module "member-access-eu-central-sprinkler" {
  count                  = (terraform.workspace == "sprinkler-development") ? 1 : 0
  source                 = "github.com/ministryofjustice/modernisation-platform-terraform-cross-account-access?ref=321b0bcb8699b952a2a66f60c6242876048480d5" #v4.0.0
  account_id             = data.aws_ssm_parameter.modernisation_platform_account_id.value
  additional_trust_roles = [data.aws_iam_role.sprinkler_oidc[0].arn, data.aws_iam_role.sprinkler_environments_read_only[0].arn, data.aws_iam_role.sprinkler_environments_dev_test[0].arn, one(data.aws_iam_roles.member-sso-admin-access.arns)]
  policy_arn             = aws_iam_policy.member-access-eu-central[0].id
  role_name              = "MemberInfrastructureBedrockEuCentral"
}

# lots of SCA ignores and skips on this one as it is the main role allowing members to build most things in the platform
#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "member-access-eu-central" {
  statement {
    #checkov:skip=CKV_AWS_108
    #checkov:skip=CKV_AWS_111
    #checkov:skip=CKV_AWS_107
    #checkov:skip=CKV_AWS_109
    #checkov:skip=CKV_AWS_110
    #checkov:skip=CKV2_AWS_40
    effect = "Allow"
    actions = [
      "bedrock:*"
    ]
    resources = ["*"] #tfsec:ignore:AWS099 tfsec:ignore:AWS097
  }
  statement {
    effect = "Deny"
    actions = [
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:AddUserToGroup",
      "iam:AttachGroupPolicy",
      "iam:AttachUserPolicy",
      "iam:CreateAccountAlias",
      "iam:CreateGroup",
      "iam:CreateLoginProfile",
      "iam:CreateOpenIDConnectProvider",
      "iam:CreateSAMLProvider",
      "iam:CreateUser",
      "iam:CreateVirtualMFADevice",
      "iam:DeactivateMFADevice",
      "iam:DeleteAccountAlias",
      "iam:DeleteAccountPasswordPolicy",
      "iam:DeleteGroup",
      "iam:DeleteGroupPolicy",
      "iam:DeleteLoginProfile",
      "iam:DeleteOpenIDConnectProvider",
      "iam:DeleteSAMLProvider",
      "iam:DeleteUser",
      "iam:DeleteUserPermissionsBoundary",
      "iam:DeleteUserPolicy",
      "iam:DeleteVirtualMFADevice",
      "iam:DetachGroupPolicy",
      "iam:DetachUserPolicy",
      "iam:EnableMFADevice",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
      "iam:RemoveUserFromGroup",
      "iam:ResyncMFADevice",
      "iam:UpdateAccountPasswordPolicy",
      "iam:UpdateGroup",
      "iam:UpdateLoginProfile",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:UpdateSAMLProvider",
      "iam:UpdateUser"
    ]
    resources = ["*"]
  }

  statement {
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "member-access-eu-central" {
  count       = local.account_data.account-type == "member" ? 1 : 0
  name        = "MemberInfrastructureBedrockEuCentralActions"
  description = "Restricted policy for US East usage"
  policy      = data.aws_iam_policy_document.member-access-eu-central.json
}

# Create a parameter for the modernisation platform environment management secret ARN that can be used to gain
# access to the environments parameter when running a tf plan locally

resource "aws_ssm_parameter" "environment_management_arn" {
  #checkov:skip=CKV_AWS_337: Standard key is fine here
  name  = "environment_management_arn"
  type  = "SecureString"
  value = data.aws_secretsmanager_secret.environment_management.arn
  tags  = local.tags
}

# Create a parameter for the modernisation platform account id that can be used
# by providers in member accounts to assume a role in MP

resource "aws_ssm_parameter" "modernisation_platform_account_id" {
  #checkov:skip=CKV_AWS_337: Standard key is fine here
  name  = "modernisation_platform_account_id"
  type  = "SecureString"
  value = local.environment_management.modernisation_platform_account_id
  tags  = local.tags
}

# Github OIDC provider
module "github-oidc" {
  count                  = (local.account_data.account-type == "member" && terraform.workspace != "testing-test" && terraform.workspace != "sprinkler-development") ? 1 : 0
  source                 = "github.com/ministryofjustice/modernisation-platform-github-oidc-provider?ref=5dc9bc211d10c58de4247fa751c318a3985fc87b" # v4.0.0
  additional_permissions = data.aws_iam_policy_document.oidc_assume_role_member[0].json
  github_repositories    = ["ministryofjustice/modernisation-platform-environments:*"]
  tags_common            = { "Name" = format("%s-oidc", terraform.workspace) }
  tags_prefix            = ""
}

#trivy:ignore:AVD-AWS-0345: Required for reading/writing Terraform state from S3
data "aws_iam_policy_document" "oidc_assume_role_member" {
  count = (local.account_data.account-type == "member" && terraform.workspace != "testing-test" && terraform.workspace != "sprinkler-development") ? 1 : 0
  statement {
    sid    = "AllowOIDCToAssumeRoles"
    effect = "Allow"
    resources = compact([
      # skip for cloud-platform as it uses a different account naming convention and does not need a member-delegation role
      local.application_name != "cloud-platform" ? format("arn:aws:iam::%s:role/member-delegation-%s-%s", local.environment_management.account_ids[format("core-vpc-%s", local.application_environment)], lower(local.business_unit), local.application_environment) : "",
      format("arn:aws:iam::%s:role/modify-dns-records", local.environment_management.account_ids["core-network-services-production"]),
      format("arn:aws:iam::%s:role/modernisation-account-limited-read-member-access", local.environment_management.modernisation_platform_account_id),
      format("arn:aws:iam::%s:role/ModernisationPlatformSSOReadOnly", local.environment_management.aws_organizations_root_account_id),
      # the following are required as cooker have development accounts but are in the sandbox vpc
      local.application_name == "cooker" ? format("arn:aws:iam::%s:role/member-delegation-house-sandbox", local.environment_management.account_ids["core-vpc-sandbox"]) : format("arn:aws:iam::%s:role/modernisation-account-limited-read-member-access", local.environment_management.modernisation_platform_account_id)
    ])
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [data.aws_organizations_organization.root_account.id]
    }
    actions = ["sts:AssumeRole"]
  }

  # checkov:skip=CKV_AWS_111: "Cannot restrict by KMS alias so leaving open"
  # checkov:skip=CKV_AWS_356: "Cannot restrict by KMS alias so leaving open"
  statement {
    sid       = "AllowOIDCToDecryptKMS"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["kms:Decrypt"]
  }

  statement {
    sid    = "AllowOIDCReadState"
    effect = "Allow"

    resources = [
      "arn:aws:s3:::modernisation-platform-terraform-state/*",
      "arn:aws:s3:::modernisation-platform-terraform-state/"
    ]
    actions = [
      "s3:Get*",
      "s3:List*"
    ]
  }

  statement {
    sid       = "AllowOIDCWriteState"
    effect    = "Allow"
    resources = ["arn:aws:s3:::modernisation-platform-terraform-state/environments/members/*"]
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]
  }

  statement {
    sid       = "AllowOIDCDeleteLock"
    effect    = "Allow"
    resources = ["arn:aws:s3:::modernisation-platform-terraform-state/environments/members/*.tflock"]
    actions = [
      "s3:DeleteObject"
    ]
  }
}

# AWS Shield Advanced SRT (Shield Response Team) support role
module "shield_response_team_role" {
  # checkov:skip=CKV_TF_1:

  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-assumable-role?ref=de95e21a3bc51cd3a44b3b95a4c2f61000649ebb" # v5.39.1

  trusted_role_services = ["drt.shield.amazonaws.com"]

  create_role       = true
  role_name         = "AWSSRTSupport"
  role_requires_mfa = false

  custom_role_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSShieldDRTAccessPolicy"]

  number_of_custom_role_policy_arns = 1
}

# Manages the account alias for the AWS Account.
resource "aws_iam_account_alias" "alias" {
  count         = (local.account_data.account-type != "member-unrestricted") && !(contains(local.skip_alias, terraform.workspace)) ? 1 : 0
  account_alias = terraform.workspace
}

# Github OIDC provider for development and test environments
module "github_actions_dev_test_role" {
  count               = can(regex("development$|test$", terraform.workspace)) ? 1 : 0
  source              = "github.com/ministryofjustice/modernisation-platform-github-oidc-role?ref=b40748ec162b446f8f8d282f767a85b6501fd192" # v4.0.0
  github_repositories = ["ministryofjustice/modernisation-platform"]
  role_name           = "github-actions-dev-test"
  policy_arns         = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  policy_jsons        = [data.aws_iam_policy_document.oidc_assume_role_dev_test[0].json]
  tags                = { "Name" = format("%s-oidc-dev-test", terraform.workspace) }
}

data "aws_iam_policy_document" "oidc_assume_role_dev_test" {
  count = can(regex("development$|test$", terraform.workspace)) ? 1 : 0
  statement {
    sid    = "AllowO