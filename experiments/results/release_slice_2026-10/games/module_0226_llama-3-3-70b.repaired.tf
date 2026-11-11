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
    workspace_key_prefix = "environments/bootstrap/single-sign-on" # This will store the object as environments/bootstrap/single-sign-on/${workspace}/terraform.tfstate
  }
}


data "aws_s3_bucket" "mod_platform_artefact" {
  provider = aws.core-shared-services
  bucket   = "mod-platform-image-artefact-bucket20230203091453221500000001"
}

# To Get Modernisation Platform Account Number
data "aws_ssm_parameter" "modernisation_platform_account_id" {
  name = "modernisation_platform_account_id"
}


# This data sources allows us to get the Modernisation Platform account information for use elsewhere
data "aws_caller_identity" "modernisation-platform" {
}

locals {

  app_name = try(regex("^bichard*.|^remote-supervisio*.", terraform.workspace), replace(terraform.workspace, "/-([[:alnum:]]+)$/", ""))

  env_name = replace(terraform.workspace, "${local.app_name}-", "")

  modernisation_platform_account = data.aws_caller_identity.modernisation-platform
  environment_management         = jsondecode(data.aws_secretsmanager_secret_version.environment_management.secret_string)

  defname = jsondecode(file("../../../../environments/${local.app_name}.json"))

  sso_data = { for data in local.defname.environments :

    data.name => data.access

    if(data.name == local.env_name)
  }
}


locals {
  sso_instance_arn      = coalesce(data.terraform_remote_state.mp-sso-permissions-sets.outputs.ssoadmin_instances.arns...)
  sso_identity_store_id = coalesce(data.terraform_remote_state.mp-sso-permissions-sets.outputs.ssoadmin_instances.identity_store_ids...)

}

# Get MP-specific AWS SSO permission sets
data "terraform_remote_state" "mp-sso-permissions-sets" {
  backend = "s3"
  config = {
    acl     = "bucket-owner-full-control"
    bucket  = "modernisation-platform-terraform-state"
    key     = "single-sign-on/terraform.tfstate"
    region  = "eu-west-2"
    encrypt = "true"
  }
}

# Get Identity Store groups
data "aws_identitystore_group" "platform_admin" {
  provider = aws.sso-management

  identity_store_id = local.sso_identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = "modernisation-platform-engineers"
    }
  }
}
data "aws_identitystore_group" "mp_azure_aws_group" {
  provider = aws.sso-management

  identity_store_id = local.sso_identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = "azure-aws-sso-modernisation-platform"
    }
  }
}

# Get Identity Store groups
data "aws_identitystore_group" "member" {

  for_each = toset(local.sso_data[local.env_name][*].sso_group_name)

  provider = aws.sso-management

  identity_store_id = local.sso_identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = try(each.value, null)
    }
  }
}

# Create account assignments
resource "aws_ssoadmin_account_assignment" "platform_admin" {

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.administrator

  principal_id   = data.aws_identitystore_group.platform_admin.group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}
resource "aws_ssoadmin_account_assignment" "platform_admin_azure" {
  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.administrator

  principal_id   = data.aws_identitystore_group.mp_azure_aws_group.group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "platform_engineer" {

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.platform_engineer

  principal_id   = data.aws_identitystore_group.platform_admin.group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}
resource "aws_ssoadmin_account_assignment" "platform_engineer_azure" {

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.platform_engineer

  principal_id   = data.aws_identitystore_group.mp_azure_aws_group.group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}
resource "aws_ssoadmin_account_assignment" "view_only" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "view-only")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.view-only

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "developer" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "developer")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.developer

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "sandbox" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "sandbox")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.sandbox

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "migration" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "migration")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.migration

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

# This is only used for legacy bichard
resource "aws_ssoadmin_account_assignment" "administator" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "administrator")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.administrator

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "instance-access" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "instance-access")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.instance_access

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "instance-management" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "instance-management")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.instance_management

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "security_audit" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "security-audit")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.security_audit

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "read_only" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "read-only")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.read_only

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "data_engineer" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "data-engineer")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.data_engineer

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "reporting-operations" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "reporting-operations")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.reporting_operations

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "mwaa_user" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "mwaa-user")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.mwaa_user

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "powerbi_user" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "powerbi-user")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.powerbi_user

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "fleet_manager" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "fleet-manager")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.fleet_manager

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "quicksight_admin" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "quicksight-admin")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.quicksight_admin

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "platform_engineer_admin" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "platform-engineer-admin")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.platform_engineer_admin

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "ssm_session_access" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "ssm-session-access")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.ssm_session_access

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_account_assignment" "data_scientist" {

  for_each = {

    for sso_assignment in local.sso_data[local.env_name][*] :

    "${sso_assignment.sso_group_name}-${sso_assignment.level}" => sso_assignment

    if(sso_assignment.level == "data-scientist")
  }

  provider = aws.sso-management

  instance_arn       = local.sso_instance_arn
  permission_set_arn = data.terraform_remote_state.mp-sso-permissions-sets.outputs.data_scientist

  principal_id   = data.aws_identitystore_group.member[each.value.sso_group_name].group_id
  principal_type = "GROUP"

  target_id   = local.environment_management.account_ids[terraform.workspace]
  target_type = "AWS_ACCOUNT"
}


# IAM policies used for SSO and collaborator roles

# common policy and statements
resource "aws_iam_policy" "common_policy" {
  provider = aws.workspace
  name     = "common_policy"
  path     = "/"
  policy   = data.aws_iam_policy_document.common_statements.json
}

#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "common_statements" {
  statement {
    sid    = "denyPermissions"
    effect = "Deny"
    actions = [
      "ec2:CreateVpc",
      "ec2:CreateSubnet",
      "ec2:CreateVpcPeeringConnection",
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
    sid    = "denyOnCicdMemberUser"
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
    sid = "assumeRolesInSharedAccounts"
    actions = [
      "sts:AssumeRole"
    ]
    resources = [
      "arn:aws:iam::*:role/ModernisationPlatformSSOReadOnly",
      "arn:aws:iam::*:role/read-log-records",
      "arn:aws:iam::*:role/member-delegation-read-only",
      "arn:aws:iam::${local.environment_management.account_ids["core-shared-services-production"]}:role/member-shared-services",
      "arn:aws:iam::${local.environment_management.account_ids["core-shared-services-production"]}:role/ad-fixngo-ec2-access",
      "arn:aws:iam::${data.aws_ssm_parameter.modernisation_platform_account_id.value}:role/modernisation-account-limited-read-member-access"
    ]
  }
}

# bedrock console policy -- to be retired when terraform support is introduced
# bedrock policy - member SSO and collaborators
resource "aws_iam_policy" "bedrock_policy" {
  provider = aws.workspace
  name     = "bedrock_policy"
  path     = "/"
  policy   = data.aws_iam_policy_document.bedrock_console.json
}

# source: https://docs.aws.amazon.com/bedrock/latest/userguide/security_iam_id-based-policy-examples.html#security_iam_id-based-policy-examples-console
#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "bedrock_console" {
  #checkov:skip=CKV_AWS_111: This is a service policy
  #checkov:skip=CKV_AWS_356: Needs to access multiple resources
  statement {
    sid    = "BedrockConsole"
    effect = "Allow"

    actions = [
      "bedrock:ListFoundationModels",
      "bedrock:GetFoundationModel",
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:CreateModelCustomizationJob",
      "bedrock:GetModelCustomizationJob",
      "bedrock:GetFoundationModelAvailability",
      "bedrock:ListModelCustomizationJobs",
      "bedrock:StopModelCustomizationJob",
      "bedrock:GetCustomModel",
      "bedrock:ListCustomModels",
      "bedrock:DeleteCustomModel",
      "bedrock:CreateProvisionedModelThroughput",
      "bedrock:UpdateProvisionedModelThroughput",
      "bedrock:GetProvisionedModelThroughput",
      "bedrock:DeleteProvisionedModelThroughput",
      "bedrock:ListProvisionedModelThroughputs",
      "bedrock:ListTagsForResource",
      "bedrock:UntagResource",
      "bedrock:TagResource",
      "bedrock:CreateAgent",
      "bedrock:UpdateAgent",
      "bedrock:GetAgent",
      "bedrock:ListAgents",
      "bedrock:CreateActionGroup",
      "bedrock:UpdateActionGroup",
      "bedrock:GetActionGroup",
      "bedrock:ListActionGroups",
      "bedrock:CreateAgentDraftSnapshot",
      "bedrock:GetAgentVersion",
      "bedrock:ListAgentVersions",
      "bedrock:CreateAgentAlias",
      "bedrock:UpdateAgentAlias",
      "bedrock:GetAgentAlias",
      "bedrock:ListAgentAliases",
      "bedrock:InvokeAgent",
      "bedrock:PutFoundationModelEntitlement",
      "bedrock:GetModelInvocationLoggingConfiguration",
      "bedrock:PutModelInvocationLoggingConfiguration",
      "bedrock:CreateFoundationModelAgreement",
      "bedrock:DeleteFoundationModelAgreement",
      "bedrock:ListFoundationModelAgreementOffers",
      "bedrock:GetUseCaseForModelAccess",
      "bedrock:PutUseCaseForModelAccess"
    ]

    resources = ["*"]
  }
}

# developer policy - member SSO and collaborators
resource "aws_iam_policy" "developer" {
  provider = aws.workspace
  name     = "developer_policy"
  path     = "/"
  policy   = data.aws_iam_policy_document.developer_additional.json
}

#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "developer_additional" {
  #checkov:skip=CKV_AWS_108
  #checkov:skip=CKV_AWS_109
  #checkov:skip=CKV_AWS_111
  #checkov:skip=CKV_AWS_110
  #checkov:skip=CKV_AWS_356: Needs to access multiple resources
  statement {
    sid    = "developerAllow"
    effect = "Allow"
    actions = [
      "acm:ImportCertificate",
      "acm:AddTagsToCertificate",
      "acm:RemoveTagsFromCertificate",
      "application-autoscaling:ListTagsForResource",
      "autoscaling:StartInstanceRefresh",
      "autoscaling:UpdateAutoScalingGroup",
      "autoscaling:SetDesiredCapacity",
      "athena:Get*",
      "athena:List*",
      "athena:St*",
      "aws-marketplace:ViewSubscriptions",
      "backup:StartBackupJob",
      "cloudwatch:DisableAlarmActions",
      "cloudwatch:EnableAlarmActions",
      "cloudwatch:PutDashboard",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:List*",
      "cloudwatch:DeleteDashboards",
      "codebuild:ImportSourceCredentials",
      "codebuild:PersistOAuthToken",
      "compute-optimizer:*",
      "cur:DescribeReportDefinitions",
      "datasync:DescribeTask",
      "datasync:ListTasks",
      "datasync:StartTaskExecution",
      "datasync:TagResource",
      "ds:AccessDSData",
      "ds:*Tags*",
      "ds:*Snapshot*",
      "ds:ResetUserPassword",
      "ds-data:Describe*",
      "ds-data:List*",
      "ds-data:Search*",
      "ec2:AttachVolume",
      "ec2:St*",
      "ec2:RebootInstances",
      "ec2:Modify*",
      "ec2:CopyImage",
      "ec2:CreateImage",
      "ec2:CreateImageUsageReport",
      "ec2:CreateVolume",
      "ec2:CopySnapshot",
      "ec2:CreateSnapshot*",
      "ec2:CreateTags",
      "ec2:DeleteSnapshot",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeSnapshots",
      "ec2:DescribeVolumes",
      "ec2:ImportImage",
      "ec2:ImportSnapshot",
      "ec2:RegisterImage",
      "ec2:*SerialConsole*",
      "ec2:ModifyInstanceAttribute",
      "ec2-instance-connect:SendSerialConsoleSSHPublicKey",
      "ecr:BatchDeleteImage",
      "ecs:StartTask",
      "ecs:StopTask",
      "ecs:ListTagsForResource",
      "ecs:ListServices",
      "ecs:DescribeServices",
      "ecs:UpdateService",
      "ecs:ExecuteCommand",
      "eks:AccessKubernetesApi",
      "eks:Describe*",
      "eks:List*",
      "elasticloadbalancing:modifyListener",
      "elasticloadbalancing:AddListenerCertificates",
      "events:DisableRule",
      "events:EnableRule",
      "fis:*",
      "glue:GetConnection",
      "glue:GetConnections",
      "guardduty:*",
      "iam:CreateServiceLinkedRole",
      "identitystore:DescribeUser",
      "kinesisanalytics:List*",
      "kinesisanalytics:Describe*",
      "kinesisanalytics:DiscoverInputSchema",
      "kms:Decrypt*",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
      "lambda:InvokeFunction",
      "lambda:UpdateFunctionCode",
      "oam:ListTagsForResource",
      "rds:AddTagsToResource",
      "rds:CopyDB*",
      "rds:Create*",
      "rds:ModifyDBSnapshotAttribute",
      "rds:RestoreDBInstanceToPointInTime",
      "rds:RebootDB*",
      "rhelkb:GetRhelURL",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetObjectAcl",
      "s3:PutObjectAcl",
      "s3:RestoreObject",
      "s3:*StorageLens*",
      "sagemaker:Describe*",
      "sagemaker:List*",
      "sagemaker:Query*",
      "secretsmanager:Get*",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecret",
      "secretsmanager:RestoreSecret",
      "secretsmanager:RotateSecret",
      "securityhub:BatchUpdateFindings",
      "servicequotas:*",
      "ses:DeleteSuppressedDestination",
      "ses:PutAccountDetails",
      "ssm:*",
      "ssm-guiconnect:*",
      "sso:ListDirectoryAssociations",
      "support:*",
      "support-console:*",
      "states:Describe*",
      "states:List*",
      "states:Stop*",
      "states:Start*",
      "wellarchitected:Get*",
      "wellarchitected:List*",
      "wellarchitected:ExportLens",
      "workspaces-web:ListSessions"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "snsAllow"
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = ["arn:aws:sns:*:*:Automation*"]
  }

  statement {
    sid    = "lambdaAllow"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = ["arn:aws:lambda:*:*:function:Automation*"]
  }

  statement {
    sid    = "iamOnCicdMemberAllow"
    effect = "Allow"
    actions = [
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:GetAccessKeyLastUsed",
      "iam:GetUser",
      "iam:ListAccessKeys",
      "iam:UpdateAccessKey"
    ]
    resources = ["arn:aws:iam::*:user/cicd-member-user"]
  }

  statement {
    sid       = "iamForECSAllow"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs.amazonaws.com"]
    }
  }

  statement {
    sid    = "cloudWatchCrossAccountAllow"
    effect = "Allow"
    actions = [
      "iam:CreateServiceLinkedRole"
    ]
    resources = ["arn:aws:iam::*:role/aws-service-role/cloudwatch-crossaccount.amazonaws.com/AWSServiceRoleForCloudWatchCrossAccount"]
  }

  statement {
    sid    = "coreSharedServicesCreateGrantAllow"
    effect = "Allow"
    actions = [
      "kms:CreateGrant"
    ]
    resources = ["arn:aws:kms:*:${local.environment_management.account_ids["core-shared-services-production"]}:key/*"]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  # Additional statement that allows for the creation of on-demand AWS Backups.
  statement {
    sid       = "AllowPassRoleForBackup"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.environment_management.account_ids[terraform.workspace]}:role/AWSBackup"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["backup.amazonaws.com"]
    }
  }

}

# data engineering policy (developer + glue + some athena)
resource "aws_iam_policy" "data_engineering" {
  provider = aws.workspace
  name     = "data_engineering_policy"
  path     = "/"
  policy   = data.aws_iam_policy_document.data_engineering_additional.json
}

#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "data_engineering_additional" {
  #checkov:skip=CKV_AWS_108
  #checkov:skip=CKV_AWS_109
  #checkov:skip=CKV_AWS_111
  #checkov:skip=CKV_AWS_110
  #checkov:skip=CKV_AWS_356: Needs to access multiple resources
  statement {
    sid    = "DataEngineeringAllow"
    effect = "Allow"
    actions = [
      "airflow:ListEnvironments",
      "airflow:GetEnvironment",
      "airflow:ListTagsForResource",
      "athena:DeleteNamedQuery",
      "athena:StartQueryExecution",
      "athena:StopQueryExecution",
      "apigateway:POST",
      "ce:CreateReport",
      "dms:StartReplicationTask",
      "dms:StopReplicationTask",
      "dms:ModifyReplicationTask",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "glue:Batch*Partition",
      "glue:BatchDeleteTable",
      "glue:CreateDatabase",
      "glue:CreatePartition",
      "glue:StartCrawler",
      "glue:CreateSession",
      "glue:CreateTable",
      "glue:DeleteDatabase",
      "glue:DeletePartition",
      "glue:DeleteTable",
      "glue:Describe*",
      "glue:*JobRun",
      "glue:RunStatement",
      "glue:UpdateDatabase",
      "glue:UpdatePartition",
      "glue:UpdateTable",
      "glue:*DefinedFunction",
      "glue:*Job",
      "glue:Get*",
      "glue:List*",
      "glue:BatchGetJobs",
      "glue:*Trigger",
      "glue:TagResource",
      "glue:UntagResource",
      "lakeformation:GetDataLakeSettings",
      "lakeformation:PutDataLakeSettings",
      "lakeformation:GrantPermissions",
      "lakeformation:BatchGrantPermissions",
      "lakeformation:RevokePermissions",
      "lakeformation:BatchRevokePermissions",
      "lakeformation:ListLakeFormationOptIns",
      "lakeformation:CreateLakeFormationOptIn",
      "lakeformation:DeleteLakeFormationOptIn",
      "lakeformation:ListLFTagExpressions",
      "lakeformation:GetLFTagExpression",
      "lakeformation:AddLFTagsToResource",
      "lakeformation:RemoveLFTagsFromResource",
      "lakeformation:GetDataAccess",
      "lambda:PutRuntimeManagementConfig",
      "macie2:ListManagedDataIdentifiers",
      "macie2:ListCustomDataIdentifiers",
      "macie2:GetFindings",
      "macie2:ListFindings",
      "macie2:GetFindingStatistics",
      "macie2:GetMacieSession",
      "macie2