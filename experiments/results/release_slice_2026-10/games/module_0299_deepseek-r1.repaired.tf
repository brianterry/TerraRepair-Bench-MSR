resource "aws_account_alternate_contact" "operations" {
  alternate_contact_type = "OPERATIONS"
  email_address          = "modernisation-platform@digital.justice.gov.uk"
  name                   = "Modernisation Platform Team"
  title                  = "Modernisation Platform Team"
  phone_number           = "+0000000000"
}


resource "aws_athena_workgroup" "mod_platform" {
  name        = "modernisation-platform"
  state       = "ENABLED"
  description = "Athena Workgroup for CSV queries"

  configuration {
    result_configuration {
      output_location = "s3://${module.member_information_bucket.bucket.bucket}/query-results/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}

resource "aws_glue_catalog_database" "member_information" {
  name = "member_information_db"
}

resource "aws_glue_catalog_table" "member_information" {
  name          = "member_information"
  database_name = aws_glue_catalog_database.member_information.name
  table_type    = "EXTERNAL_TABLE"

  storage_descriptor {
    columns {
      name = "accountname"
      type = "string"
    }
    columns {
      name = "awsaccountid"
      type = "string"
    }
    columns {
      name = "slackchannel"
      type = "string"
    }
    columns {
      name = "infrastructuresupportemail"
      type = "string"
    }
    columns {
      name = "incidenthours"
      type = "string"
    }
    columns {
      name = "incidentcontactdetails"
      type = "string"
    }
    columns {
      name = "serviceurls"
      type = "string"
    }

    ser_de_info {
      name                  = "CSV Serde"
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
      parameters = {
        "separatorChar"          = ","
        "quoteChar"              = "\""
        "field.delim"            = ","
        "skip.header.line.count" = "1"
        "escapeChar"             = "\\"
      }
    }

    location      = "s3://${module.member_information_bucket.bucket.bucket}/data/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
  }
}


terraform {
  # `backend` blocks do not support variables, so the following are hard-coded here:
  # - S3 bucket name, which is created in s3.tf
  backend "s3" {
    acl          = "bucket-owner-full-control"
    bucket       = "modernisation-platform-terraform-state"
    encrypt      = true
    key          = "modernisation-platform-account/terraform.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
  }
}


# cloudtrail kms key lookup
data "aws_kms_key" "cloudtrail_key" {
  provider = aws.core-logging
  key_id   = "alias/s3-logging-cloudtrail"
}

# Regions to enable secure baselines in
locals {
  enabled_baseline_regions = [
    "eu-central-1", # Europe (Frankfurt)
    "eu-west-1",    # Europe (Ireland)
    "eu-west-2",    # Europe (London)
    "eu-west-3",    # Europe (Paris)
    "us-east-1",    # US East (N. Virginia) (for global services)
  ]
}

# Secure baselines (GuardDuty, Config, SecurityHub, etc)
#trivy:ignore:AVD-AWS-0136 trivy:ignore:AVD-AWS-0132
module "baselines-modernisation-platform" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-baselines?ref=35c27b19f923053a9ab0525d45c9301dca743359" # v9.0.0
  providers = {
    # Default and replication regions
    aws                    = aws.modernisation-platform-eu-west-2
    aws.replication-region = aws.modernisation-platform-eu-west-1

    # Other regions
    aws.ap-northeast-1 = aws.modernisation-platform-ap-northeast-1
    aws.ap-northeast-2 = aws.modernisation-platform-ap-northeast-2
    aws.ap-south-1     = aws.modernisation-platform-ap-south-1
    aws.ap-southeast-1 = aws.modernisation-platform-ap-southeast-1
    aws.ap-southeast-2 = aws.modernisation-platform-ap-southeast-2
    aws.ca-central-1   = aws.modernisation-platform-ca-central-1
    aws.eu-central-1   = aws.modernisation-platform-eu-central-1
    aws.eu-north-1     = aws.modernisation-platform-eu-north-1
    aws.eu-west-1      = aws.modernisation-platform-eu-west-1
    aws.eu-west-2      = aws.modernisation-platform-eu-west-2
    aws.eu-west-3      = aws.modernisation-platform-eu-west-3
    aws.sa-east-1      = aws.modernisation-platform-sa-east-1
    aws.us-east-1      = aws.modernisation-platform-us-east-1
    aws.us-east-2      = aws.modernisation-platform-us-east-2
    aws.us-west-1      = aws.modernisation-platform-us-west-1
    aws.us-west-2      = aws.modernisation-platform-us-west-2
  }

  # Ensure bucket policy references correct account
  current_account_id = local.environment_management.modernisation_platform_account_id

  # Selectively reduce pre prod backups on certain accounts
  reduced_preprod_backup_retention = local.reduced_preprod_backup_retention

  # Regions to enable IAM Access Analyzer in
  enabled_access_analyzer_regions = local.enabled_baseline_regions

  # Regions to enable AWS Backup in
  enabled_backup_regions = local.enabled_baseline_regions

  # Regions to enable AWS Config in
  enabled_config_regions = local.enabled_baseline_regions

  # Regions to enable EBS encryption in
  enabled_ebs_encryption_regions = local.enabled_baseline_regions

  # Regions to enable GuardDuty in
  enabled_guardduty_regions = local.enabled_baseline_regions

  # Regions to enable Security Hub in
  enabled_securityhub_regions = local.enabled_baseline_regions

  cloudtrail_kms_key = aws_kms_key.s3_state_bucket_multi_region.arn

  root_account_id = local.root_account.master_account_id
  tags            = local.tags

  # Regions to enable IMDSv2 in
  enabled_imdsv2_regions = local.enabled_baseline_regions

  # Pass in pagerduty integration key for security hub alerts
  pagerduty_integration_key = local.pagerduty_integration_keys["security_hub"]

  # PagerDuty Key for High Priority Alarms
  high_priority_pagerduty_integration_key = local.pagerduty_integration_keys["core_alerts_high_priority_cloudwatch"]

  enable_securityhub_slack_alerts                    = true
  securityhub_slack_alerts_scope                     = ["CRITICAL", "HIGH"]
  securityhub_slack_alerts_pagerduty_integration_key = local.pagerduty_integration_keys["security_hub_alerts_critical_priority"]

  logging = {
    target_bucket = module.state-bucket.bucket.bucket
    target_prefix = "logs/baselines-modernisation-platform/"
  }
}


data "aws_organizations_organization" "root_account" {}

data "aws_caller_identity" "current" {}

# Get secret by name for environment management
data "aws_secretsmanager_secret" "environment_management" {
  name = "environment_management"
}

# Get latest secret value with ID from above. This secret stores account IDs for the Modernisation Platform sub-accounts
data "aws_secretsmanager_secret_version" "environment_management" {
  secret_id = data.aws_secretsmanager_secret.environment_management.id
}

data "aws_iam_roles" "sso-admin-access" {
  name_regex  = "AWSReservedSSO_AdministratorAccess_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

# Get the map of pagerduty integration keys
data "aws_secretsmanager_secret" "pagerduty_integration_keys" {
  name = "pagerduty_integration_keys"
}

data "aws_secretsmanager_secret_version" "pagerduty_integration_keys" {
  secret_id = data.aws_secretsmanager_secret.pagerduty_integration_keys.id
}


#tfsec:ignore:aws-iam-no-policy-wildcards
#tfsec:ignore:aws-iam-enforce-mfa
module "iam" {
  source        = "github.com/ministryofjustice/modernisation-platform-terraform-iam-superadmins?ref=83b376fb80315304f0a09287ff0ec9a358901591" # v3.0.0
  account_alias = "moj-modernisation-platform"
}

### Collaborators

# Attach created users to a AWS IAM group, with several policies
#tfsec:ignore:aws-iam-no-policy-wildcards
#tfsec:ignore:aws-iam-enforce-mfa
module "collaborators_group" {
  #checkov:skip=CKV_TF_1:Module registry does not support commit hashes for versions
  #checkov:skip=CKV_TF_2:Module registry does not support tags
  source  = "terraform-aws-modules/iam/aws//modules/iam-group"
  version = "~> 6.0"
  name    = "collaborators"

  users = [for user in module.collaborators : user.username]

  policies = {
    ForceMFA                        = data.aws_iam_policy.ForceMFA.arn,
    collaborator-local-plan         = aws_iam_policy.collaborator_local_plan.arn,
    ModernisationAccountLimitedRead = aws_iam_policy.modernisation_account_limited_read.arn
  }
}

data "aws_iam_policy" "ForceMFA" {
  name = "ForceMFA"
}

resource "aws_iam_policy" "collaborator_local_plan" {
  name        = "collaborator-local-plan"
  description = "Permissions collaborators need to perform local Terraform plans"
  policy      = data.aws_iam_policy_document.collaborator_local_plan.json
}

data "aws_iam_policy_document" "collaborator_local_plan" {
  statement {
    sid    = "AssumeRole"
    effect = "Allow"
    actions = [
      "sts:AssumeRole"
    ]
    resources = [
      "arn:aws:iam::${local.environment_management.account_ids["core-network-services-production"]}:role/read-log-records",
      "arn:aws:iam::${local.environment_management.account_ids["core-vpc-development"]}:role/member-delegation-read-only",
      "arn:aws:iam::${local.environment_management.account_ids["core-vpc-test"]}:role/member-delegation-read-only",
      "arn:aws:iam::${local.environment_management.account_ids["core-vpc-preproduction"]}:role/member-delegation-read-only",
      "arn:aws:iam::${local.environment_management.account_ids["core-vpc-production"]}:role/member-delegation-read-only",
      "arn:aws:iam::${local.environment_management.account_ids["core-vpc-sandbox"]}:role/member-delegation-read-only",
      "arn:aws:iam::${data.aws_caller_identity.current.id}:role/modernisation-account-limited-read-member-access"
    ]
    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }

  statement {
    sid = "TerraformStateAccess"
    actions = [
      "s3:ListBucket",
      "s3:GetObject"
    ]

    resources = [
      "arn:aws:s3:::modernisation-platform-terraform-state/*.tflock",
      "arn:aws:s3:::modernisation-platform-terraform-state/terraform.tfstate",
      "arn:aws:s3:::modernisation-platform-terraform-state/environments/members/*",
      "arn:aws:s3:::modernisation-platform-terraform-state/environments/accounts/core-network-services/*",
      "arn:aws:s3:::modernisation-platform-terraform-state"
    ]

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }

  statement {
    sid     = "TerraformStateAccessDeleteLock"
    effect  = "Allow"
    actions = ["s3:DeleteObject"]

    resources = ["arn:aws:s3:::modernisation-platform-terraform-state/*.tflock"]

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }

  statement {
    sid    = "ssmAccess"
    effect = "Allow"
    actions = [
      "ssm:GetParameter"
    ]
    resources = [
      "arn:aws:ssm:eu-west-2:${data.aws_caller_identity.current.id}:parameter/modernisation_platform_account_id"
    ]
    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

#tfsec:ignore:aws-iam-no-user-attached-policies
module "collaborators" {
  source                 = "../modules/collaborators"
  for_each               = { for user in local.collaborators.users : user.username => user.accounts }
  username               = each.key
  accounts               = each.value
  environment_management = local.environment_management
}

# Modernisation Platform Account Readonly Role
data "aws_iam_policy_document" "modernisation_account_limited_read_assume_role" {
  version = "2012-10-17"

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.modernisation_platform_ou_id}/*"]
    }
  }
}

resource "aws_iam_role" "modernisation_account_limited_read" {
  name                 = "modernisation-account-limited-read-member-access"
  max_session_duration = 3600
  assume_role_policy   = data.aws_iam_policy_document.modernisation_account_limited_read_assume_role.json

  tags = local.tags
}

data "aws_iam_policy_document" "modernisation_account_limited_read" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
      "secretsmanager:ListSecrets"
    ]
    resources = [
      "arn:aws:secretsmanager:eu-west-2:${data.aws_caller_identity.current.account_id}:secret:environment_management-??????",
      "arn:aws:secretsmanager:eu-west-2:${data.aws_caller_identity.current.account_id}:secret:pagerduty_integration_keys-??????",
      "arn:aws:secretsmanager:eu-west-2:${data.aws_caller_identity.current.account_id}:secret:mod-platform-circleci-??????",
      "arn:aws:secretsmanager:eu-west-2:${data.aws_caller_identity.current.account_id}:secret:nonmp-account-ids-??????",
    ]
  }
  statement {
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::*"]
  }
  statement {
    sid    = "ViewConsoleHome"
    effect = "Allow"
    actions = [
      "ec2:DescribeRegions",
      "notifications:ListNotificationHubs",
      "health:DescribeEventAggregates",
      "cost-optimization-hub:ListEnrollmentStatuses",
      "ce:GetCostAndUsage"
    ]
    resources = ["*"]
  }
}
resource "aws_iam_policy" "modernisation_account_limited_read" {
  name        = "ModernisationAccountLimitedRead"
  description = "Limited Read Access in MP Account for Members and CI"
  policy      = data.aws_iam_policy_document.modernisation_account_limited_read.json
}

resource "aws_iam_role_policy_attachment" "modernisation_account_limited_read" {
  role       = aws_iam_role.modernisation_account_limited_read.id
  policy_arn = aws_iam_policy.modernisation_account_limited_read.arn
}

# OIDC Provider for GitHub Actions Plan
#trivy:ignore:AVD-AWS-0345: Required for GitHub Actions to access Terraform state in S3
module "github_actions_plan_role" {
  source              = "github.com/ministryofjustice/modernisation-platform-github-oidc-role?ref=b40748ec162b446f8f8d282f767a85b6501fd192" # v4.0.0
  github_repositories = ["ministryofjustice/modernisation-platform", "ministryofjustice/modernisation-platform-github", "ministryofjustice/modernisation-platform-ami-builds", "ministryofjustice/modernisation-platform-security"]
  role_name           = "github-actions-plan"
  policy_jsons        = [data.aws_iam_policy_document.oidc_assume_plan_role_member.json]
  tags                = { "Name" = "GitHub Actions Plan" }
}

data "aws_iam_policy_document" "oidc_assume_plan_role_member" {
  # checkov:skip=CKV_AWS_111: "Cannot restrict by KMS alias so leaving open"
  # checkov:skip=CKV_AWS_356: "Cannot restrict by KMS alias so leaving open"
  # checkov:skip=CKV_AWS_108: "Allowing secretsmanager:GetSecretValue with open resource due to specific use case"
  statement {
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "kms:Decrypt",
      "secretsmanager:GetSecretValue"
    ]
  }

  statement {
    sid    = "AssumeRole"
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
    ]
    resources = [
      "arn:aws:iam::*:role/ModernisationPlatformAccess",
      "arn:aws:iam::${local.environment_management.aws_organizations_root_account_id}:role/ModernisationPlatformSSOAdministrator"
    ]
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values = [
        "${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"
      ]
    }
  }

  statement {
    sid       = "AllowOIDCReadState"
    effect    = "Allow"
    resources = ["arn:aws:s3:::modernisation-platform-terraform-state/*", "arn:aws:s3:::modernisation-platform-terraform-state/"]
    actions = [
      "s3:Get*",
      "s3:List*"
    ]
  }

  statement {
    sid       = "AllowOIDCDeleteLock"
    effect    = "Allow"
    resources = ["arn:aws:s3:::modernisation-platform-terraform-state/*.tflock"]
    actions   = ["s3:DeleteObject"]
  }
}

# OIDC Provider for GitHub Actions Apply
#trivy:ignore:AVD-AWS-0345: Required for GitHub Actions to access Terraform state in S3
module "github_actions_apply_role" {
  source              = "github.com/ministryofjustice/modernisation-platform-github-oidc-role?ref=b40748ec162b446f8f8d282f767a85b6501fd192" # v4.0.0
  github_repositories = ["ministryofjustice/modernisation-platform", "ministryofjustice/modernisation-platform-github", "ministryofjustice/modernisation-platform-ami-builds", "ministryofjustice/modernisation-platform-security"]
  role_name           = "github-actions-apply"
  policy_arns         = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  policy_jsons        = [data.aws_iam_policy_document.apply-oidc-deny-specific-actions.json]
  subject_claim       = "ref:refs/heads/main"
  tags                = { "Name" = "GitHub Actions Apply" }
}

# OIDC resources

module "github-oidc" {
  source                      = "github.com/ministryofjustice/modernisation-platform-github-oidc-provider?ref=5dc9bc211d10c58de4247fa751c318a3985fc87b" # v4.0.0
  additional_permissions      = data.aws_iam_policy_document.oidc-deny-specific-actions.json
  additional_managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  github_repositories         = ["ministryofjustice/modernisation-platform:*", "ministryofjustice/modernisation-platform-ami-builds:*", "ministryofjustice/modernisation-platform-security:*"]
  tags_common                 = { "Name" = format("%s-oidc", terraform.workspace) }
  tags_prefix                 = ""
}

data "aws_iam_policy_document" "oidc-deny-specific-actions" {
  statement {
    effect = "Deny"
    actions = [
      "iam:ChangePassword",
      "iam:CreateLoginProfile"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "apply-oidc-deny-specific-actions" {
  statement {
    effect = "Deny"
    actions = [
      "iam:ChangePassword",
      "iam:CreateLoginProfile"
    ]
    resources = ["*"]
  }
}

# OIDC Provider for GitHub Actions Secrets Reader
#trivy:ignore:AVD-AWS-0345: 
module "github_actions_read_secrets_role" {
  source = "github.com/ministryofjustice/modernisation-platform-github-oidc-role?ref=b40748ec162b446f8f8d282f767a85b6501fd192" # v4.0.0
  github_repositories = [
    "ministryofjustice/modernisation-platform",
    "ministryofjustice/modernisation-platform-environments",
    "ministryofjustice/modernisation-platform-terraform-baselines",
    "ministryofjustice/modernisation-platform-ami-builds",
    "ministryofjustice/modernisation-platform-terraform-bastion-linux",
    "ministryofjustice/modernisation-platform-terraform-s3-bucket",
    "ministryofjustice/modernisation-platform-terraform-aws-vm-import",
    "ministryofjustice/modernisation-platform-terraform-ec2-instance",
    "ministryofjustice/modernisation-platform-terraform-pagerduty-integration",
    "ministryofjustice/modernisation-platform-terraform-iam-superadmins",
    "ministryofjustice/modernisation-platform-terraform-ec2-autoscaling-group",
    "ministryofjustice/modernisation-platform-terraform-member-vpc",
    "ministryofjustice/modernisation-platform-terraform-module-template",
    "ministryofjustice/modernisation-platform-github-oidc-role",
    "ministryofjustice/modernisation-platform-github",
    "ministryofjustice/modernisation-platform-terraform-environments",
    "ministryofjustice/modernisation-platform-terraform-ecs-cluster",
    "ministryofjustice/modernisation-platform-github-oidc-provider",
    "ministryofjustice/modernisation-platform-terraform-ssm-patching",
    "ministryofjustice/modernisation-platform-terraform-aws-chatbot",
    "ministryofjustice/modernisation-platform-terraform-lambda-function",
    "ministryofjustice/modernisation-platform-terraform-dns-certificates",
    "ministryofjustice/modernisation-platform-instance-scheduler",
    "ministryofjustice/modernisation-platform-terraform-loadbalancer",
    "ministryofjustice/modernisation-platform-terraform-aws-data-firehose",
    "ministryofjustice/modernisation-platform-terraform-cross-account-access",
    "ministryofjustice/modernisation-platform-security",
    "ministryofjustice/modernisation-platform-terraform-aws-waf",
    "ministryofjustice/modernisation-platform-terraform-certificate-dns-validations"
  ]
  role_name    = "github-actions-read-secrets"
  policy_jsons = [data.aws_iam_policy_document.oidc_assume_read_secrets_role_member.json]
  tags         = { "Name" = "GitHub Actions Read Secrets" }
}

data "aws_iam_policy_document" "oidc_assume_read_secrets_role_member" {
  # checkov:skip=CKV_AWS_111: "Cannot restrict by KMS alias so leaving open"
  # checkov:skip=CKV_AWS_356: "Cannot restrict by KMS alias so leaving open"
  # checkov:skip=CKV_AWS_108: "Allowing secretsmanager:GetSecretValue with open resource due to specific use case"
  statement {
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "kms:Decrypt",
      "secretsmanager:GetSecretValue"
    ]
  }
}


#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "sso_customer_managed_policy_engineer" {
  #checkov:skip=CKV_AWS_356: Allows access to multiple unknown resources
  statement {
    sid       = "SSOCustomerManagedPolicyEngineer"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["ec2:CreateTags"]
  }
}

resource "aws_iam_policy" "sso_customer_managed_policy_engineer" {

  name        = "SSOCustomerManagedPolicyEngineer"
  path        = "/"
  description = "Restricted policy for use for the testing of customer managed SSO policies"
  policy      = data.aws_iam_policy_document.sso_customer_managed_policy_engineer.json
}


locals {
  root_account                     = data.aws_organizations_organization.root_account
  environment_management           = jsondecode(data.aws_secretsmanager_secret_version.environment_management.secret_string)
  modernisation_platform_ou_id     = local.environment_management.modernisation_platform_organisation_unit_id
  pagerduty_integration_keys       = jsondecode(data.aws_secretsmanager_secret_version.pagerduty_integration_keys.secret_string)
  reduced_preprod_backup_retention = false

  root_role_with_state_access = ["arn:aws:iam::${local.root_account.master_account_id}:role/ModernisationPlatformGithubActionsRole"] # Role for Github OIDC

  collaborators = jsondecode(file("../../collaborators.json"))

  tags = {
    business-unit = "Platforms"
    application   = "Modernisation Platform"
    is-production = true
    owner         = "Modernisation Platform: modernisation-platform@digital.justice.gov.uk"
  }

  replica_region = "eu-west-1"
}


module "pagerduty_core_alerts" {
  source                    = "github.com/ministryofjustice/modernisation-platform-terraform-pagerduty-integration?ref=d88bd90d490268896670a898edfaba24bba2f8ab" # v3.0.0
  sns_topics                = ["config", "securityhub-alarms", "cloudtrail"]
  pagerduty_integration_key = local.pagerduty_integration_keys["core_alerts_cloudwatch"]
}

moved {
  from = module.core_monitoring.module.pagerduty_core_alerts.aws_sns_topic_subscription.pagerduty_subscription["cloudtrail"]
  to   = module.pagerduty_core_alerts.aws_sns_topic_subscription.pagerduty_subscription["cloudtrail"]
}

moved {
  from = module.core_monitoring.module.pagerduty_core_alerts.aws_sns_topic_subscription.pagerduty_subscription["config"]
  to   = module.pagerduty_core_alerts.aws_sns_topic_subscription.pagerduty_subscription["config"]
}

moved {
  from = module.core_monitoring.module.pagerduty_core_alerts.aws_sns_topic_subscription.pagerduty_subscription["securityhub-alarms"]
  to   = module.pagerduty_core_alerts.aws_sns_topic_subscription.pagerduty_subscription["securityhub-alarms"]
}

module "observability_platform_tenant" {

  source = "github.com/ministryofjustice/terraform-aws-observability-platform-tenant?ref=f69b36c79ba18976d8e500e7cf61cf407158eb61" # v2.0.0

  observability_platform_account_id = local.environment_management.account_ids["observability-platform-production"]

  tags = local.tags
}


output "iam_superadmin_passwords" {
  description = "PGP-encrypted IAM superadmin passwords, if a Keybase username is provided"
  value       = module.iam.superadmin_passwords
}

output "iam_superadmin_user_names" {
  value = module.iam.iam_user_names
}

# AWS providers

# Default provider
provider "aws" {
  region = "eu-west-2"
}

provider "aws" {
  region = "ap-northeast-1"
  alias  = "modernisation-platform-ap-northeast-1"
}

provider "aws" {
  region = "ap-northeast-2"
  alias  = "modernisation-platform-ap-northeast-2"
}

provider "aws" {
  region = "ap-south-1"
  alias  = "modernisation-platform-ap-south-1"
}

provider "aws" {
  region = "ap-southeast-1"
  alias  = "modernisation-platform-ap-southeast-1"
}

provider "aws" {
  region = "ap-southeast-2"
  alias  = "modernisation-platform-ap-southeast-2"
}

provider "aws" {
  region = "ca-central-1"
  alias  = "modernisation-platform-ca-central-1"
}

provider "aws" {
  region = "eu-central-1"
  alias  = "modernisation-platform-eu-central-1"
}

provider "aws" {
  region = "eu-north-1"
  alias  = "modernisation-platform-eu-north-1"
}

provider "aws" {
  region = "eu-west-1"
  alias  = "modernisation-platform-eu-west-1"
}

provider "aws" {
  region = "eu-west-2"
  alias  = "modernisation-platform-eu-west-2"
}

provider "aws" {
  region = "eu-west-3"
  alias  = "modernisation-platform-eu-west-3"
}

provider "aws" {
  region = "sa-east-1"
  alias  = "modernisation-platform-sa-east-1"
}

provider "aws" {
  region = "us-east-1"
  alias  = "modernisation-platform-us-east-1"
}

provider "aws" {
  region = "us-east-2"
  alias  = "modernisation-platform-us-east-2"
}

provider "aws" {
  region = "us-west-1"
  alias  = "modernisation-platform-us-west-1"
}

provider "aws" {
  region = "us-west-2"
  alias  = "modernisation-platform-us-west-2"
}

# AWS provider for core-logging
provider "aws" {
  alias  = "core-logging"
  region = "eu-west-2"
  assume_role {
    role_arn = "arn:aws:iam::${local.environment_management.account_ids["core-logging-production"]}:role/ModernisationPlatformAccess"
  }
}


# State bucket KMS multi-Region
resource "aws_kms_key" "s3_state_bucket_multi_region" {
  description             = "s3-state-bucket-multi-region"
  policy                  = data.aws_iam_policy_document.kms_state_bucket.json
  enable_key_rotation     = true
  deletion_window_in_days = 30
  multi_region            = true
}

resource "aws_kms_alias" "s3_state_bucket_multi_region" {
  name          = "alias/s3-state-bucket-multi-region"
  target_key_id = aws_kms_key.s3_state_bucket_multi_region.id
}

resource "aws_kms_alias" "s3_state_bucket" {
  name          = "alias/s3-state-bucket"
  target_key_id = aws_kms_key.s3_state_bucket_multi_region.id
}

resource "aws_kms_replica_key" "s3_state_bucket_multi_region_replica" {
  description             = "AWS S3 bucket replica key"
  deletion_window_in_days = 30
  primary_key_arn         = aws_kms_key.s3_state_bucket_multi_region.arn
  provider                = aws.modernisation-platform-eu-west-1
}

resource "aws_kms_alias" "s3_state_bucket_multi_region_replica" {
  name          = "alias/s3-state-bucket-multi-region-replica"
  target_key_id = aws_kms_replica_key.s3_state_bucket_multi_region_replica.id
}

data "aws_iam_policy_document" "kms_state_bucket" {
  # checkov:skip=CKV_AWS_111: "policy is directly related to the resource"
  # checkov:skip=CKV_AWS_356: "policy is directly related to the resource"
  # checkov:skip=CKV_AWS_109: "role is resticted by limited actions in member account"
  statement {
    sid    = "Allow management access of the key to the modernisation platform account"
    effect = "Allow"
    actions = [
      "kms:*"
    ]
    resources = [
      "*"
    ]
    principals {
      type = "AWS"
      identifiers = concat(
        ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"],
        local.root_role_with_state_access
      )
    }
  }
  statement {
    sid    = "Allow key decryption to STS bucket replication roles"
    effect = "Allow"
    actions = [
      "kms:Decrypt*"
    ]
    resources = ["*"]
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/AWSS3BucketReplication-terraform-state/s3-replication"
      ]
    }
  }
  statement {
    sid    = "ReadOnlyFromModernisationPlatformOU"
    effect = "Allow"
    actions = [
      "kms:Decrypt*"
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
    }
  }
}

# State bucket KMS Destination
resource "aws_kms_key" "s3_state_bucket_eu-west-1_replication" {
  provider = aws.modernisation-platform-eu-west-1

  description             = "s3-state_bucket-eu-west-1-replication"
  policy                  = data.aws_iam_policy_document.kms_state_bucket.json
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "s3_state_bucket_eu-west-1_replication" {
  provider = aws.modernisation-platform-eu-west-1

  name          = "alias/s3-state_bucket-eu-west-1-replication"
  target_key_id = aws_kms_key.s3_state_bucket_eu-west-1_replication.id
}

module "state-bucket" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399" # v9.0.0

  providers = {
    aws.bucket-replication = aws.modernisation-platform-eu-west-1
  }
  bucket_policy              = [data.aws_iam_policy_document.allow-state-access-from-root-account.json, data.aws_iam_policy_document.allow-state-access-for-root-account-sso-admins.json]
  bucket_name                = "modernisation-platform-terraform-state"
  replication_bucket         = "modernisation-platform-terraform-state-replication"
  suffix_name                = "-terraform-state"
  replication_enabled        = true
  replication_region         = "eu-west-1"
  custom_kms_key             = aws_kms_key.s3_state_bucket_multi_region.arn
  custom_replication_kms_key = aws_kms_replica_key.s3_state_bucket_multi_region_replica.arn
  ownership_controls         = "BucketOwnerEnforced"
  tags                       = local.tags

  logging = {
    target_bucket = module.state-bucket.bucket.bucket
    target_prefix = "logs/state-bucket/"
  }

  lifecycle_rule = [
    {
      id      = "main"
      enabled = "Enabled"
      prefix  = ""
      tags    = {}
      transition = [
        {
          days          = 90
          storage_class = "STANDARD_IA"
          }, {
          days          = 700
          storage_class = "GLACIER"
        }
      ]
      expiration = {
        days = 730
      }
      noncurrent_version_transition = [
        {
          days          = 90
          storage_class = "STANDARD_IA"
          }, {
          days          = 700
          storage_class = "GLACIER"
        }
      ]
      noncurrent_version_expiration = {
        days = 730
      }
    }
  ]
}

# Allow access to the bucket from the MoJ root account
# Policy extrapolated from:
# https://www.terraform.io/docs/backends/types/s3.html#s3-bucket-permissions
data "aws_iam_policy_document" "allow-state-access-from-root-account" {
  statement {
    sid       = "AllowListBucketFromRootAccount"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [module.state-bucket.bucket.arn]

    principals {
      type        = "AWS"
      identifiers = local.root_role_with_state_access
    }
  }

  statement {
    sid    = "AllowGetandPutObjectFromRootAccount"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${module.state-bucket.bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = local.root_role_with_state_access
    }
  }

  statement {
    sid       = "AllowDeleteLockFromRootAccounts"
    effect    = "Allow"
    actions   = ["s3:DeleteObject"]
    resources = ["${module.state-bucket.bucket.arn}/*.tflock"]

    principals {
      type        = "AWS"
      identifiers = local.root_role_with_state_access
    }
  }

  statement {
    sid       = "ListBucketFromModernisationPlatformOU"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [module.state-bucket.bucket.arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
    }
  }

  statement {
    sid     = "GetObjectFromModernisationPlatformOU"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${module.state-bucket.bucket.arn}/terraform.tfstate",
      "${module.state-bucket.bucket.arn}/environments/members/*",
      "${module.state-bucket.bucket.arn}/environments/accounts/core-network-services/*"
    ]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
    }
  }

  statement {
    sid     = "DeleteLockFromModernisationPlatformOU"
    effect  = "Allow"
    actions = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
    resources = [
      "${module.state-bucket.bucket.arn}/*.tflock",
    ]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
    }
  }

  statement {
    sid     = "AllowTestingCIUser"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    resources = [
      "${module.state-bucket.bucket.arn}/environments/members/testing/testing-test/terraform.tfstate",
      "${module.state-bucket.bucket.arn}/environments/members/testing/testing-test/*.tflock",
    ]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.environment_management.account_ids["testing-test"]}:user/testing-ci"]
    }
  }

  statement {
    sid     = "AllowGithubActionsRole"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    resources = [
      "${module.state-bucket.bucket.arn}/environments/members/*",
    ]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/github-actions", "arn:aws:iam::*:role/github-actions-environments-dev-test"]
    }
  }

  statement {
    sid     = "AllowGithubActionsTerraformReadOnlyPutLock"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    resources = [
      "${module.state-bucket.bucket.arn}/*/*.tflock",
    ]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/github-actions-environments-read-only"]
    }
  }

  statement {
    sid     = "AllowGithubActionsRoleDeleteLock"
    effect  = "Allow"
    actions = ["s3:DeleteObject"]
    resources = [
      "${module.state-bucket.bucket.arn}/*/*.tflock",
    ]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/github-actions", "arn:aws:iam::*:role/github-actions-environments-read-only", "arn:aws:iam::*:role/github-actions-environments-dev-test"]
    }
  }

  statement {
    sid       = "AllowAdministratorAccessRole"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${module.state-bucket.bucket.arn}/environments/members/*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_AdministratorAccess_*"]
    }
  }

  statement {
    sid       = "AllowAdministratorAccessRoleDeleteLock"
    effect    = "Allow"
    actions   = ["s3:DeleteObject"]
    resources = ["${module.state-bucket.bucket.arn}/environments/members/*.tflock"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_AdministratorAccess_*"]
    }
  }

  statement {
    sid       = "AllowMPAdministratorAccessRole"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${module.state-bucket.bucket.arn}/environments/accounts/*", ]

    principals {
      type        = "AWS"
      identifiers = tolist(data.aws_iam_roles.sso-admin-access.arns)
    }
  }

  statement {
    sid       = "AllowMPAdministratorAccessRoleDeleteLock"
    effect    = "Allow"
    actions   = ["s3:DeleteObject"]
    resources = ["${module.state-bucket.bucket.arn}/environments/accounts/*.tflock", ]

    principals {
      type        = "AWS"
      identifiers = tolist(data.aws_iam_roles.sso-admin-access.arns)
    }
  }

  statement {
    sid    = "AllowSprinklerGithubActionRole"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject"
    ]
    resources = [
      "arn:aws:s3:::modernisation-platform-terraform-state/single-sign-on/*",
      "arn:aws:s3:::modernisation-platform-terraform-state/environments/bootstrap/*/sprinkler-development/*"
    ]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.environment_management.account_ids["sprinkler-development"]}:role/github-actions", "arn:aws:iam::${local.environment_management.account_ids["sprinkler-development"]}:role/github-actions-environments-dev-test"]
    }
  }

  statement {
    sid    = "AllowSprinklerGithubActionRoleDeleteLock"
    effect = "Allow"
    actions = [
      "s3:DeleteObject"
    ]
    resources = [
      "arn:aws:s3:::modernisation-platform-terraform-state/single-sign-on/*.tflock",
      "arn:aws:s3:::modernisation-platform-terraform-state/environments/bootstrap/*/sprinkler-development/*.tflock"
    ]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.environment_management.account_ids["sprinkler-development"]}:role/github-actions", "arn:aws:iam::${local.environment_management.account_ids["sprinkler-development"]}:role/github-actions-environments-dev-test"]
    }
  }

  statement {
    sid    = "AllowAnalyticalPlatformEngineersAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${module.state-bucket.bucket.arn}/environments/members/analytical-platform-*/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_platform-engineer-admin_*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values = [
        # Analytical Platform's member account IDs
        local.environment_management.account_ids["analytical-platform-common-production"],
        local.environment_management.account_ids["analytical-platform-compute-development"],
        local.environment_management.account_ids["analytical-platform-compute-test"],
        local.environment_management.account_ids["analytical-platform-compute-production"],
        local.environment_management.account_ids["analytical-platform-ingestion-development"],
        local.environment_management.account_ids["analytical-platform-ingestion-production"],
        local.environment_management.account_ids["analytical-platform-next-poc-hub-development"],
        local.environment_management.account_ids["analytical-platform-next-poc-producer-development"]
      ]
    }
  }

  statement {
    sid       = "AllowAnalyticalPlatformEngineersDeleteLock"
    effect    = "Allow"
    actions   = ["s3:DeleteObject"]
    resources = ["${module.state-bucket.bucket.arn}/environments/members/analytical-platform-*/*.tflock"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_platform-engineer-admin_*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values = [
        # Analytical Platform's member account IDs
        local.environment_management.account_ids["analytical-platform-common-production"],
        local.environment_management.account_ids["analytical-platform-compute-development"],
        local.environment_management.account_ids["analytical-platform-compute-test"],
        local.environment_management.account_ids["analytical-platform-compute-production"],
        local.environment_management.account_ids["analytical-platform-ingestion-development"],
        local.environment_management.account_ids["analytical-platform-ingestion-production"],
        local.environment_management.account_ids["analytical-platform-next-poc-hub-development"],
        local.environment_management.account_ids["analytical-platform-next-poc-producer-development"]
      ]
    }
  }

  statement {
    sid    = "AllowDevTestGithubActionsRole"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${module.state-bucket.bucket.arn}/environments/accounts/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/github-actions-dev-test"]
    }
  }

  statement {
    sid    = "AllowDataPlatformEngineersAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${module.state-bucket.bucket.arn}/environments/members/data-platform*/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_platform-engineer-admin_*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values = [
        # Data Platform's member account IDs
        local.environment_management.account_ids["data-platform-development"],
        local.environment_management.account_ids["data-platform-preproduction"],
        local.environment_management.account_ids["data-platform-production"],
        local.environment_management.account_ids["data-platform-test"],
      ]
    }
  }

  statement {
    sid       = "AllowDataPlatformEngineersDeleteLock"
    effect    = "Allow"
    actions   = ["s3:DeleteObject"]
    resources = ["${module.state-bucket.bucket.arn}/environments/members/data-platform*/*.tflock"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_platform-engineer-admin_*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values = [
        # Data Platform's member account IDs
        local.environment_management.account_ids["data-platform-development"],
        local.environment_management.account_ids["data-platform-preproduction"],
        local.environment_management.account_ids["data-platform-production"],
        local.environment_management.account_ids["data-platform-test"],
      ]
    }
  }
  statement {
    sid    = "AllowCloudPlatformEngineersAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = ["${module.state-bucket.bucket.arn}/environments/members/cloud-platform*/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_platform-engineer-admin_*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values = [
        # Cloud Platform's member account IDs
        local.environment_management.account_ids["cloud-platform-development"],
        local.environment_management.account_ids["cloud-platform-preproduction"],
        local.environment_management.account_ids["cloud-platform-nonlive"],
        local.environment_management.account_ids["cloud-platform-live"]
      ]
    }
  }
  statement {
    sid    = "AllowCloudPlatformDevelopmentClusterAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = ["${module.state-bucket.bucket.arn}/environments/members/cloud-platform*/*"]
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${local.environment_management.account_ids["cloud-platform-development"]}:role/github-actions-development-cluster"
      ]
    }
  }
}

# Allow access to the bucket for SSO admins from the MoJ root account
data "aws_iam_policy_document" "allow-state-access-for-root-account-sso-admins" {
  statement {
    sid       = "AllowListBucketForRootAccountSSOAdmins"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [module.state-bucket.bucket.arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${data.aws_organizations_organization.root_account.master_account_id}:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_AdministratorAccess_*"]
    }
  }

  statement {
    sid    = "AllowGetAndPutObjectForRootAccountSSOAdmins"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${module.state-bucket.bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${data.aws_organizations_organization.root_account.master_account_id}:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_AdministratorAccess_*"]
    }
  }

  statement {
    sid       = "AllowDeleteLockForRootAccountSSOAdmins"
    effect    = "Allow"
    actions   = ["s3:DeleteObject"]
    resources = ["${module.state-bucket.bucket.arn}/*.tflock"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${data.aws_organizations_organization.root_account.master_account_id}:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_AdministratorAccess_*"]
    }
  }
}

module "cost-management-bucket" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399" # v9.0.0
  providers = {
    aws.bucket-replication = aws.modernisation-platform-eu-west-1
  }
  bucket_policy       = [data.aws_iam_policy_document.cost_management_bucket_policy.json]
  bucket_name         = "mp-cost-explorer-reports"
  custom_kms_key      = aws_kms_key.s3_state_bucket_multi_region.arn
  replication_enabled = false
  logging = {
    target_bucket = module.state-bucket.bucket.bucket
    target_prefix = "logs/cost-management/"
  }
  lifecycle_rule = [
    {
      id      = "main"
      enabled = "Disabled"
      prefix  = ""
    }
  ]
  tags = local.tags
}


data "aws_iam_policy_document" "cost_management_bucket_policy" {
  statement {
    sid    = "AllowAdministratorAccessRole"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject"
    ]
    resources = ["${module.cost-management-bucket.bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.environment_management.modernisation_platform_account_id}:role/github-actions"]
    }
  }
}

module "member_information_bucket" {
  source = "github.com/ministryofjustice/modernisation-platform-terraform-s3-bucket?ref=9facf9fc8f8b8e3f93ffbda822028534b9a75399" # v9.0.0
  providers = {
    aws.bucket-replication = aws.modernisation-platform-eu-west-1
  }
  bucket_policy       = [data.aws_iam_policy_document.member_information_bucket_policy.json]
  bucket_name         = "modernisation-member-information"
  custom_kms_key      = aws_kms_key.s3_state_bucket_multi_region.arn
  replication_enabled = false
  logging = {
    target_bucket = module.state-bucket.bucket.bucket
    target_prefix = "logs/member-information/"
  }
  lifecycle_rule = [
    {
      id      = "main"
      enabled = "Disabled"
      prefix  = ""
    }
  ]
  tags = local.tags
}


data "aws_iam_policy_document" "member_information_bucket_policy" {
  statement {
    sid    = "AllowAdministratorAccessRole"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject"
    ]
    resources = ["${module.member_information_bucket.bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.environment_management.modernisation_platform_account_id}:role/github-actions"]
    }
  }
}


# Slack channel modernisation-platform-notifications webhook url for sending notifications to slack
# Not adding a secret version as this url is provided by slack and cannot be added programatically
# Secret should be manually set in the console.
resource "aws_kms_key" "secrets_key_multi_region" {
  description             = "AWS Secretsmanager CMK"
  policy                  = data.aws_iam_policy_document.kms_secrets_key.json
  enable_key_rotation     = true
  deletion_window_in_days = 30
  multi_region            = true
}

resource "aws_kms_alias" "secrets_key_multi_region" {
  name          = "alias/secrets-key-multi-region"
  target_key_id = aws_kms_key.secrets_key_multi_region.id
}

resource "aws_kms_replica_key" "secrets_key_multi_region_replica" {
  description             = "AWS Secretsmanager CMK replica key"
  deletion_window_in_days = 30
  primary_key_arn         = aws_kms_key.secrets_key_multi_region.arn
  provider                = aws.modernisation-platform-eu-west-1
}

resource "aws_kms_alias" "secrets_key_multi_region_replica" {
  name          = "alias/secrets-key-multi-region-replica"
  target_key_id = aws_kms_replica_key.secrets_key_multi_region_replica.id
}

data "aws_iam_policy_document" "kms_secrets_key" {
  #cannot reference secret in resources for statement as this causes cyclic error
  #checkov:skip=CKV_AWS_108: Cannot set resource as not known at time document is created, causing a cyclic error
  #checkov:skip=CKV_AWS_109: "Constraint is via only mp ou condition"
  #checkov:skip=CKV_AWS_111: "Constraint is via only mp ou condition"
  #checkov:skip=CKV_AWS_356: Policy is attached to a resource
  statement {
    sid    = "AllowManagementAccountAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id, data.aws_organizations_organization.root_account.master_account_id]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }
  statement {
    sid    = "AllowModernisationPlatformAccountsToDecrypt"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["kms:Decrypt*"]
    resources = ["*"]
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
    }
  }
}

# CircleCI Organisation ID
resource "aws_secretsmanager_secret" "circleci" {
  # checkov:skip=CKV2_AWS_57:Auto rotation not possible
  name        = "mod-platform-circleci"
  description = "CircleCI organisation ID for ministryofjustice, used for OIDC IAM policies"
  kms_key_id  = aws_kms_key.secrets_key_multi_region.id

  replica {
    region = local.replica_region
  }
}

resource "aws_secretsmanager_secret_version" "circleci" {
  secret_id = aws_secretsmanager_secret.circleci.id
  secret_string = jsonencode({
    organisation_id = "CHANGE_ME_IN_THE_CONSOLE" # change this value manually in the console once the secret is created
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Data call to fetch changed value
data "aws_secretsmanager_secret_version" "circleci" {
  secret_id = aws_secretsmanager_secret.circleci.id
}

# Github CI user PAT
# Not adding a secret version as this url is generated in Github cannot be added programatically
# Secret should be manually set in the console.
resource "aws_secretsmanager_secret" "github_ci_user_pat" {
  # checkov:skip=CKV2_AWS_57:Auto rotation not possible
  name        = "github_ci_user_pat"
  description = "GitHub CI user PAT used for generated resources in GitHub via Terraform"
  kms_key_id  = aws_kms_key.secrets_key_multi_region.id
  tags        = local.tags
  replica {
    region = local.replica_region
  }
}

# Github CI user environments repo PAT
# Not adding a secret version as this url is generated in Github cannot be added programatically
# Secret should be manually set in the console.
resource "aws_secretsmanager_secret" "github_ci_user_environments_repo_pat" {
  # checkov:skip=CKV2_AWS_57:Auto rotation not possible
  name        = "github_ci_user_environments_repo_pat"
  description = "This PAT token is used in reusable pipelines of the modernisation-platform-environments repository. This is so that the CI user can post comments in PRs, e.g. tf plan/apply output. Expires on Tue, Apr 9 2024."
  kms_key_id  = aws_kms_key.secrets_key_multi_region.id
  tags        = local.tags
  replica {
    region = local.replica_region
  }
}

# Github CI user password
# Not adding a secret version as this url is generated in Github cannot be added programatically
# Secret should be manually set in the console.
resource "aws_secretsmanager_secret" "github_ci_user_password" {
  # checkov:skip=CKV2_AWS_57:Auto rotation not possible
  name        = "github_ci_user_password"
  description = "GitHub CI user password"
  kms_key_id  = aws_kms_key.secrets_key_multi_region.id
  tags        = local.tags
  replica {
    region = local.replica_region
  }
}

resource "aws_secretsmanager_secret" "gov_uk_notify_api_key" {
  # checkov:skip=CKV2_AWS_57:Auto rotation not possible
  name        = "gov_uk_notify_api_key"
  description = "API key for accessing the GOV.UK Notify service for sending email notifications"
  kms_key_id  = aws_kms_key.secrets_key_multi_region.id
  tags        = local.tags
  replica {
    region = local.replica_region
  }
}

# Look up environments remote state to get aws nuke lists
data "terraform_remote_state" "environments" {
  backend = "s3"
  config = {
    bucket = "modernisation-platform-terraform-state"
    key    = "environments/terraform.tfstate"
    region = "eu-west-2"
  }
}

# Account IDs to be excluded from auto-nuke
resource "aws_secretsmanager_secret" "nuke_account_blocklist" {
  # checkov:skip=CKV2_AWS_57:Auto rotation not possible
  name        = "nuke_account_blocklist"
  description = "Account IDs to be excluded from auto-nuke. This secret is used by GitHub actions job awsnuke.yml inside the environments repo."
  kms_key_id  = aws_kms_key.secrets_key_multi_region.id
  tags        = local.tags
  replica {
    region = local.replica_region
  }
}

resource "aws_secretsmanager_secret_version" "nuke_account_blocklist" {
  secret_id = aws_secretsmanager_secret.nuke_account_blocklist.id
  secret_string = jsonencode({
    blocklist = data.terraform_remote_state.environments.outputs.environment_nuke_blocklist_accounts
  })
}

# Account IDs to be auto-nuked on weekly basis
resource "aws_secretsmanager_secret" "nuke_account_ids" {
  # checkov:skip=CKV2_AWS_57:Auto rotation not possible
  name        = "nuke_account_ids"
  description = "Account IDs to be auto-nuked on weekly basis. This secret is used by GitHub actions job awsnuke.yml inside the environments repo."
  kms_key_id  = aws_kms_key.secrets_key_multi_region.id
  tags        = local.tags
  replica {
    region = local.replica_region
  }
}

resource "aws_secretsmanager_secret_version" "nuke_account_ids" {
  secret_id = aws_secretsmanager_secret.nuke_account_ids.id
  secret_string = jsonencode({
    nuke_accounts = data.terraform_remote_state.environments.outputs.environment_nuke_accounts
  })
}

# Account IDs to be rebuilt after being nuked
resource "aws_secretsmanager_secret" "nuke_rebuild_account_ids" {
  # checkov:skip=CKV2_AWS_57:Auto rotation not possible
  name        = "nuke_rebuild_account_ids"
  description = "Account IDs to be rebuilt after being nuked. This secret is used by GitHub actions job awsnuke.yml inside the environments repo."
  kms_key_id  = aws_kms_key.secrets_key_multi_region.id
  tags        = local.tags
  replica {
    region = local.replica_region
  }
}
resource "aws_secretsmanager_secret_version" "nuke_rebuild_account_ids" {
  secret_id = aws_secretsmanager_secret.nuke_rebuild_account_ids.id
  secret_string = jsonencode({
    rebuild_accounts = data.terraform_remote_state.environments.outputs.environment_rebuild_after_nuke_accounts
  })
}

resource "aws_secretsmanager_secret" "slack_webhook_url" {
  # checkov:skip=CKV2_AWS_57:Auto rotation not possible
  name        = "slack_webhook_url"
  description = "Slack channel modernisation-platform-notifications webhook url for sending notifications to slack"
  kms_key_id  = aws_kms_key.secrets_key_multi_region.id
  tags        = local.tags
  replica {
    region = local.replica_region
  }
}

resource "aws_secretsmanager_secret" "slack_webhooks" {
  # checkov:skip=CKV2_AWS_57:Auto rotation not possible
  name        = "slack_webhooks"
  description = "Used for sending notifications to specified Slack channels when environment JSON files are modified"
  kms_key_id  = aws_kms_key.secrets_key_multi_region.id
  tags        = local.tags
  replica {
    region = local.replica_region
  }
}

resource "aws_secretsmanager_secret" "securityhub_slack_webhooks" {
  # checkov:skip=CKV2_AWS_57:Auto rotation not possible
  name        = "securityhub_slack_webhooks"
  description = "Stores Slack channel webhook URLs for sending Security Hub findings notifications"
  kms_key_id  = aws_kms_key.secrets_key_multi_region.id
  tags        = local.tags
  replica {
    region = local.replica_region
  }
}

resource "aws_secretsmanager_secret" "secrets-fetch-decrypt-passphrase" {
  # checkov:skip=CKV2_AWS_57:Auto rotation not possible
  name        = "secrets-fetch-decrypt-passphrase"
  description = "Used by the reusable secrets workflows as the passphrase"
  kms_key_id  = aws_kms_key.secrets_key_multi_region.id
  tags        = local.tags
  replica {
    region = local.replica_region
  }
}

# Reflection of what is in member accounts, needed here as well so that the same code works for collaborators
resource "aws_ssm_parameter" "modernisation_platform_account_id" {
  #checkov:skip=CKV_AWS_337: Standard key is fine here
  name  = "modernisation_platform_account_id"
  type  = "SecureString"
  value = data.aws_caller_identity.current.id
  tags  = local.tags
}

data "aws_kms_alias" "environment_management" {
  name = "alias/environment-management-multi-region"
}

resource "aws_secretsmanager_secret" "nonmp_account_ids" {
  # checkov:skip=CKV2_AWS_57:Auto rotation not possible
  name        = "nonmp-account-ids"
  description = "Map of account IDs not present in the environment_management secret (non-MP accounts)"
  kms_key_id  = data.aws_kms_alias.environment_management.target_key_id
  tags        = local.tags
}

# Modernisation Platform Github App Private Key
resource "aws_secretsmanager_secret" "modernisation_platform_github_app_private_key" {
  # checkov:skip=CKV2_AWS_57:Auto rotation not possible
  name        = "modernisation_platform_github_app_private_key"
  description = "The private key associated with the modernisation platform github app."
  kms_key_id  = aws_kms_key.secrets_key_multi_region.id
  tags        = local.tags
  replica {
    region = local.replica_region
  }
}
resource "aws_secretsmanager_secret_version" "modernisation_platform_github_app_private_key" {
  secret_id     = aws_secretsmanager_secret.modernisation_platform_github_app_private_key.id
  secret_string = "Replace after build"
}


terraform {
  required_providers {
    aws = {
      version = "~> 6.0"
      source  = "hashicorp/aws"
    }
    archive = {
      version = "~> 2.0"
      source  = "hashicorp/archive"
    }
  }
  required_version = "~> 1.0"
}