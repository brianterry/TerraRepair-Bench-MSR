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
      "cloudtrail:Get