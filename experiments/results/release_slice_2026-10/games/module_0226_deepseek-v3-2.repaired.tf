terraform {
  backend "s3" {
    acl                  = "bucket-owner-full-control"
    bucket               = "modernisation-platform-terraform-state"
    encrypt              = true
    key                  = "terraform.tfstate"
    region               = "eu-west-2"
    use_lockfile         = true
    workspace_key_prefix = "environments/bootstrap/single-sign-on"
  }
}


data "aws_s3_bucket" "mod_platform_artefact" {
  provider = aws.core-shared-services
  bucket   = "mod-platform-image-artefact-bucket20230203091453221500000001"
}

data "aws_ssm_parameter" "modernisation_platform_account_id" {
  name = "modernisation_platform_account_id"
}

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


resource "aws_iam_policy" "common_policy" {
  provider = aws.workspace
  name     = "common_policy"
  path     = "/"
  policy   = data.aws_iam_policy_document.common_statements.json
}

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

resource "aws_iam_policy" "bedrock_policy" {
  provider = aws.workspace
  name     = "bedrock_policy"
  path     = "/"
  policy   = data.aws_iam_policy_document.bedrock_console.json
}

data "aws_iam_policy_document" "bedrock_console" {
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

resource "aws_iam_policy" "developer" {
  provider = aws.workspace
  name     = "developer_policy"
  path     = "/"
  policy   = data.aws_iam_policy_document.developer_additional.json
}

data "aws_iam_policy_document" "developer_additional" {
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

resource "aws_iam_policy" "data_engineering" {
  provider = aws.workspace
  name     = "data_engineering_policy"
  path     = "/"
  policy   = data.aws_iam_policy_document.data_engineering_additional.json
}

data "aws_iam_policy_document" "data_engineering_additional" {
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
      "macie2:ListClassificationJobs",
      "macie2:DescribeClassificationJob",
      "sqs:StartMessageMoveTask",
      "sqs:CancelMessageMoveTask",
      "sqs:ListMessageMoveTasks",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ListDeadLetterSourceQueues",
      "sqs:SendMessage",
      "sqs:PurgeQueue",
      "states:Describe*",
      "states:List*",
      "states:Stop*",
      "states:Start*",
      "states:RedriveExecution",
      "s3:PutBucketNotificationConfiguration",
      "s3:CreateJob",
      "s3:GetBucketOwnershipControls",
      "s3:PutObjectAcl",
      "s3:PutObjectTagging",
      "s3:UpdateJobStatus",
      "s3tables:*"
    ]
    resources = ["*"]
  }
  statement {
    sid       = "AirflowUIAccess"
    effect    = "Allow"
    actions   = ["airflow:CreateWebLoginToken"]
    resources = ["arn:aws:airflow:eu-west-1:${local.environment_management.account_ids["analytical-platform-data-production"]}:role/*/User"]
  }

  statement {
    sid       = "iamPassRoleForDataEngineering"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [
      "arn:aws:iam::${local.environment_management.account_ids["analytical-platform-data-production"]}:role/data-first-data-science",
      "arn:aws:iam::${local.environment_management.account_ids["electronic-monitoring-data-production"]}:role/glue-notebook-role-tf",
      "arn:aws:iam::${local.environment_management.account_ids["electronic-monitoring-data-test"]}:role/AWSS3BucketReplication*",
      "arn:aws:iam::${local.environment_management.account_ids["electronic-monitoring-data-preproduction"]}:role/AWSS3BucketReplication*",
      "arn:aws:iam::${local.environment_management.account_ids["electronic-monitoring-data-production"]}:role/AWSS3BucketReplication*"
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["glue.amazonaws.com", "s3.amazonaws.com"]
    }
  }

  statement {
    sid       = "AllowAssumeAnalyticalPlatformDataEngineeringStateAccessRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::${local.environment_management.account_ids["analytical-platform-management-production"]}:role/data-engineering-state-access"]
  }
}

resource "aws_iam_policy" "quicksight_administrator" {
  provider = aws.workspace
  name     = "quicksight_administrator_policy"
  path     = "/"
  policy   = data.aws_iam_policy_document.quicksight_administrator_additional.json
}

data "aws_iam_policy_document" "quicksight_administrator_additional" {
  statement {
    sid    = "QuickSightConsoleAdmin"
    effect = "Allow"

    actions = [
      "athena:ListDataCatalogs",
      "athena:GetDataCatalog",
      "ds:AuthorizeApplication",
      "ds:UnauthorizeApplication",
      "ds:CheckAlias",
      "ds:CreateAlias",
      "ds:DescribeDirectories",
      "ds:DescribeTrusts",
      "ds:DeleteDirectory",
      "ds:CreateIdentityPoolDirectory",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:GetPolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:DeleteRole",
      "iam:CreateRole",
      "iam:GetRole",
      "iam:ListRoles",
      "iam:CreatePolicy",
      "iam:ListEntitiesForPolicy",
      "iam:ListPolicies",
      "organizations:DescribeOrganization",
      "quicksight:*",
      "s3:ListAllMyBuckets",
      "sso:DescribeApplication",
      "sso:DescribeInstance",
      "sso:CreateApplication",
      "sso:PutApplicationAuthenticationMethod",
      "sso:PutApplicationGrant",
      "sso:DeleteApplication",
      "sso:GetProfile",
      "sso:CreateApplicationAssignment",
      "sso:DeleteApplicationAssignment",
      "sso:ListInstances",
      "sso:DescribeRegisteredRegions"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "platform_engineer_admin" {
  provider = aws.workspace
  name     = "platform_engineer_admin_policy"
  path     = "/"
  policy   = data.aws_iam_policy_document.platform_engineer_additional_additional.json
}

data "aws_iam_policy_document" "platform_engineer_additional_additional" {
  statement {
    sid    = "PlatformEngineerAdmin"
    effect = "Allow"
    actions = [
      "acm:*",
      "acm-pca:*",
      "airflow:*",
      "apigateway:*",
      "application-autoscaling:*",
      "appstream:*",
      "aps:*",
      "athena:*",
      "autoscaling:*",
      "aws-marketplace:ViewSubscriptions",
      "backup:*",
      "bedrock:*",
      "ce:*",
      "cloudformation:*",
      "cloudfront:*",
      "cloudtrail:*",
      "cloudwatch:*",
      "codebuild:*",
      "codedeploy:*",
      "codepipeline:*",
      "cognito-identity:*",
      "cognito-idp:*",
      "cur:DescribeReportDefinitions",
      "datasync:*",
      "dbqms:*",
      "discovery:*",
      "detective:*",
      "dlm:*",
      "dms:*",
      "drs:*",
      "ds:*",
      "ds-data:*",
      "dynamodb:*",
      "ebs:*",
      "ec2:*",
      "ec2-instance-connect:*",
      "ecr-public:*",
      "ecr:*",
      "ecs:*",
      "eks:*",
      "elasticache:*",
      "elasticfilesystem:*",
      "elasticloadbalancing:*",
      "events:*",
      "glacier:*",
      "glue:*",
      "guardduty:*",
      "iam:*",
      "identitystore:*",
      "kinesis:*",
      "kinesisanalytics:*",
      "kms:*",
      "lakeformation:*",
      "lambda:*",
      "logs:*",
      "mgh:*",
      "mgn:*",
      "migrationhub-strategy:*",
      "networkflowmonitor:*",
      "networkmonitor:*",
      "network-firewall:*",
      "oam:*",
      "organizations:DescribeOrganization",
      "quicksight:*",
      "ram:*",
      "rds-data:*",
      "rds-db:*",
      "rds:*",
      "redshift-data:*",
      "redshift-serverless:*",
      "redshift:*",
      "rhelkb:GetRhelURL",
      "route53:*",
      "s3:*",
      "sagemaker:*",
      "scheduler:*",
      "secretsmanager:*",
      "servicequotas:*",
      "ses:*",
      "sns:*",
      "sqs:*",
      "sqlworkbench:*",
      "ssm:*",
      "ssm-guiconnect:*",
      "sso:*",
      "states:*",
      "sts:*",
      "support:*",
      "support-console:*",
      "textract:*",
      "tiros:*",
      "transfer:*",
      "vpce:*",
      "wafv2:*",
      "wellarchitected:*",
      "workspaces-web:*"
    ]
    resources = ["*"]
  }

}

resource "aws_iam_policy" "sandbox" {
  provider = aws.workspace
  name     = "sandbox_policy"
  path     = "/"
  policy   = data.aws_iam_policy_document.sandbox_additional.json
}

data "aws_iam_policy_document" "sandbox_additional" {
  statement {
    sid    = "sandboxAllow"
    effect = "Allow"
    actions = [
      "acm-pca:*",
      "acm:*",
      "airflow:*",
      "apigateway:*",
      "application-autoscaling:*",
      "appstream:*",
      "athena:*",
      "autoscaling:*",
      "aws-marketplace:ViewSubscriptions",
      "backup:*",
      "cloudformation:*",
      "cloudfront:*",
      "cloudwatch:*",
      "codebuild:ImportSourceCredentials",
      "codebuild:PersistOAuthToken",
      "codedeploy:*",
      "cognito-identity:*",
      "cognito-idp:*",
      "cur:DescribeReportDefinitions",
      "datasync:*",
      "dbqms:*",
      "dlm:*",
      "dms:*",
      "drs:*",
      "ds-data:Describe*",
      "ds-data:List*",
      "ds-data:Search*",
      "ds:*Tags*",
      "ds:AccessDSData",
      "ds:CancelSchemaExtension",
      "ds:CheckAlias",
      "ds:CreateAlias",
      "ds:CreateComputer",
      "ds:CreateDirectory",
      "ds:CreateLogSubscription",
      "ds:CreateMicrosoftAD",
      "ds:CreateSnapshot",
      "ds:Delete*",
      "ds:Deregister*",
      "ds:Describe*",
      "ds:Disable*",
      "ds:Enable*",
      "ds:List*",
      "ds:RegisterCertificate",
      "ds:RegisterEventTopic",
      "ds:ResetUserPassword",
      "ds:RestoreFromSnapshot",
      "ds:StartSchemaExtension",
      "ds:Update*",
      "dynamodb:*",
      "ebs:*",
      "ec2-instance-connect:SendSerialConsoleSSHPublicKey",
      "ec2:*Address*",
      "ec2:*CapacityReservation*",
      "ec2:*Ebs*",
      "ec2:*Event*",
      "ec2:*Fleet*",
      "ec2:*IdFormat*",
      "ec2:*Image*",
      "ec2:*Instance*",
      "ec2:*KeyPair*",
      "ec2:*LaunchTemplate*",
      "ec2:*NetworkInterface*",
      "ec2:*PlacementGroup*",
      "ec2:*SecurityGroup*",
      "ec2:*SerialConsole*",
      "ec2:*Snapshot*",
      "ec2:*Spot*",
      "ec2:*Tags*",
      "ec2:*Volume*",
      "ec2:Describe*",
      "ec2:Get*",
      "ec2:SendDiagnosticInterrupt",
      "ecr-public:*",
      "ecr:*",
      "ecs:*",
      "eks:AccessKubernetesApi",
      "eks:Describe*",
      "eks:List*",
      "elasticache:*",
      "elasticfilesystem:*",
      "elasticloadbalancing:*",
      "events:*",
      "execute-api:Invoke",
      "firehose:*",
      "fis:*",
      "glacier:*",
      "glue:*",
      "guardduty:*",
      "iam:*",
      "identitystore:DescribeUser",
      "kinesis:*",
      "kinesisanalytics:*",
      "kms:*",
      "lakeformation:*",
      "lambda:*",
      "logs:*",
      "mgh:*",
      "mgn:*",
      "organizations:Describe*",
      "organizations:List*",
      "quicksight:*",
      "rds-data:*",
      "rds-db:*",
      "rds:*",
      "redshift-data:*",
      "redshift-serverless:*",
      "redshift:*",
      "rhelkb:GetRhelURL",
      "route53:*",
      "s3:*",
      "sagemaker:*",
      "scheduler:*",
      "secretsmanager:*",
      "securityhub:BatchUpdateFindings",
      "ses:*",
      "sns:*",
      "sqlworkbench:*",
      "sqs:*",
      "ssm-guiconnect:*",
      "ssm-quicksetup:*",
      "ssm:*",
      "sso:ListDirectoryAssociations",
      "states:*",
      "support:*",
      "support-console:*",
      "textract:*",
      "transfer:*",
      "wafv2:*",
      "wellarchitected:*",
      "workspaces-web:*"
    ]
    resources = ["*"]
  }
  statement {
    sid = "sandboxSSOAllow"
    actions = [
      "sso:CreateApplicationAssignment"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:sso::${local.environment_management.aws_organizations_root_account_id}:application/ssoins-7535d9af4f41fb26/*"
    ]
  }
}

resource "aws_iam_policy" "migration" {
  provider = aws.workspace
  name     = "migration_policy"
  path     = "/"
  policy   = data.aws_iam_policy_document.migration_additional.json
}

data "aws_iam_policy_document" "migration_additional" {
  statement {
    sid    = "migrationAllow"
    effect = "Allow"
    actions = [
      "datasync:*",
      "discovery:*",
      "dms:*",
      "drs:*",
      "mgh:*",
      "mgn:*",
      "migrationhub-strategy:*",
      "ssm:*",
      "ssm-guiconnect:*",
      "sts:DecodeAuthorizationMessage"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "iamOnUsersAllow"
    effect = "Allow"
    actions = [
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:GetAccessKeyLastUsed",
      "iam:GetUser",
      "iam:ListAccessKeys",
      "iam:UpdateAccessKey"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "migrationPassRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::*:role/service-role/AWSApplicationMigrationConversionServerRole"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["mgn.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "instance-access" {
  provider = aws.workspace
  name     = "instance_access_policy"
  path     = "/"
  policy   = data.aws_iam_policy_document.instance-access-document.json
}

data "aws_iam_policy_document" "instance-access-document" {
  source_policy_documents = [data.aws_iam_policy_document.common_statements.json]
  statement {
    sid    = "InstanceAccess"
    effect = "Allow"
    actions = [
      "athena:StartQueryExecution",
      "athena:StopQueryExecution",
      "ec2:GetPasswordData",
      "kms:Decrypt*",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "rhelkb:GetRhelURL",
      "s3:PutObject",
      "ssm-guiconnect:*",
    ]
    resources = ["*"]
  }
  statement {
    sid    = "SecretsManagerGet"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "secretsmanager:ResourceTag/instance-access-policy"
      values   = ["limited"]
    }
  }
  statement {
    sid    = "SecretsManagerPut"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "secretsmanager:ResourceTag/instance-access-policy"
      values   = ["full"]
    }
  }
  statement {
    sid    = "SSMStartSessionPortForwarding"
    effect = "Allow"
    actions = [
      "ssm:StartSession"
    ]
    resources = [
      "arn:aws:ec2:*:*:instance/*",
      "arn:aws:ssm:*:*:managed-instance/*",
      "arn:aws:ssm:*:*:document/AWS-StartPortForwardingSession",
    ]
    condition {
      test     = "BoolIfExists"
      variable = "ssm:SessionDocumentAccessCheck"
      values   = ["true"]
    }
    condition {
      test     = "StringEqualsIfExists"
      variable = "ssm:resourceTag/instance-access-policy"
      values   = ["limited"]
    }
  }
  statement {
    sid    = "SSMStartSessionSSH"
    effect = "Allow"
    actions = [
      "ssm:StartSession"
    ]
    resources = [
      "arn:aws:ec2:*:*:instance/*",
      "arn:aws:ssm:*:*:managed-instance/*",
      "arn:aws:ssm:*:*:document/AWS-StartSSHSession",
    ]
    condition {
      test     = "BoolIfExists"
      variable = "ssm:SessionDocumentAccessCheck"
      values   = ["true"]
    }
    condition {
      test     = "StringEqualsIfExists"
      variable = "ssm:resourceTag/instance-access-policy"
      values   = ["limited"]
    }
  }
  statement {
    sid    = "SSMStartSession"
    effect = "Allow"
    actions = [
      "ssm:StartSession"
    ]
    resources = [
      "arn:aws:ec2:*:*:instance/*",
      "arn:aws:ssm:*:*:managed-instance/*",
    ]
    condition {
      test     = "StringEqualsIfExists"
      variable = "ssm:resourceTag/instance-access-policy"
      values   = ["full"]
    }
  }

  statement {
    sid    = "SSMSendCommand"
    effect = "Allow"
    actions = [
      "ssm:SendCommand",
    ]
    resources = [
      "arn:aws:ec2:*:*:instance/*",
      "arn:aws:ssm:*:*:managed-instance/*",
      "arn:aws:ssm:*:*:document/AWSSSO-CreateSSOUser"
    ]
    condition {
      test     = "BoolIfExists"
      variable = "ssm:SessionDocumentAccessCheck"
      values   = ["true"]
    }
    condition {
      test     = "StringEqualsIfExists"
      variable = "ssm:resourceTag/instance-access-policy"
      values   = ["full"]
    }
  }
}

resource "aws_iam_policy" "instance-management" {
  provider = aws.workspace
  name     = "instance_management_policy"
  path     = "/"
  policy   = data.aws_iam_policy_document.instance-management-document.json
}

data "aws_iam_policy_document" "instance-management-document" {
  statement {
    sid    = "ABACEc2Deny"
    effect = "Deny"
    actions = [
      "*"
    ]
    resources = ["*"]
    condition {
      test     = "ForAnyValue:StringNotLike"
      variable = "aws:PrincipalTag/github_team"

      values = [
        "*:$${aws:ResourceTag/Owner}:*",
        "$${aws:ResourceTag/Owner}:*",
        "*:$${aws:ResourceTag/Owner}"
      ]
    }
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/Owner"
      values = [
        "False"
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"

      values = [
        local.environment_management.account_ids["core-shared-services-production"]
      ]
    }
  }
  statement {
    sid    = "databaseAllowNull"
    effect = "Allow"
    actions = [
      "application-autoscaling:ListTagsForResource",
      "athena:StartQueryExecution",
      "athena:StopQueryExecution",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:StartInstanceRefresh",
      "autoscaling:UpdateAutoScalingGroup",
      "aws-marketplace:ViewSubscriptions",
      "ds:*Snapshot*",
      "ds:*Tags*",
      "ds:ResetUserPassword",
      "ec2:AttachVolume",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:Connect",
      "ec2:CopyImage",
      "ec2:CopySnapshot",
      "ec2:CreateImage",
      "ec2:CreateSnapshot",
      "ec2:CreateSnapshots",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceAttribute",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DescribeVpcs",
      "ec2:DetachVolume",
      "ec2:GetConsoleOutput",
      "ec2:ModifyImageAttribute",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifySnapshotAttribute",
      "ec2:RebootInstances",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RunInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:TerminateInstances",
      "ecs:DescribeServices",
      "ecs:ListServices",
      "ecs:UpdateService",
      "identitystore:DescribeUser",
      "kms:Decrypt*",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
      "rds:CopyDBClusterSnapshot",
      "rds:CopyDBSnapshot",
      "rds:CreateDBClusterSnapshot",
      "rds:CreateDBSnapshot",
      "rds:RebootDB*",
      "rhelkb:GetRhelURL",
      "s3:Get*",
      "s3:List*",
      "s3:PutObject",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:ListSecret*",
      "ssm:*",
      "ssm-guiconnect:*",
      "sso:ListDirectoryAssociations",
      "support:*",
      "support-console:*"
    ]

    resources = ["*"]

  }
  statement {
    sid    = "SecretsManagerPut"
    effect = "Allow"
    actions = [
      "secretsmanager:PutSecretValue",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "secretsmanager:ResourceTag/instance-management-policy"
      values   = ["full"]
    }
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
}

resource "aws_iam_policy" "reporting-operations" {
  provider = aws.workspace
  name     = "reporting_operations_policy"
  path     = "/"
  policy   = data.aws_iam_policy_document.reporting-operations.json
}

data "aws_iam_policy_document" "reporting-operations" {
  statement {
    sid    = "reportingOperationsAllow"
    effect = "Allow"
    actions = [
      "dms:DescribeReplicationInstances",
      "dms:DescribeReplicationTasks",
      "dms:ModifyReplicationTask",
      "dms:StartReplicationTaskAssessmentRun",
      "dms:StartReplicationTask",
      "dms:StopReplicationTask",
      "dms:TestConnection",
      "dms:ReloadTables",
      "dms:RebootReplicationInstance",
      "sqlworkbench:CreateFolder",
      "sqlworkbench:PutTab",
      "sqlworkbench:BatchDeleteFolder",
      "sqlworkbench:DeleteTab",
      "sqlworkbench:GenerateSession",
      "sqlworkbench:GetAccountInfo",
      "sqlworkbench:GetAccountSettings",
      "sqlworkbench:GetUserInfo",
      "sqlworkbench:GetUserWorkspaceSettings",
      "sqlworkbench:PutUserWorkspaceSettings",
      "sqlworkbench:ListConnections",
      "sqlworkbench:ListFiles",
      "sqlworkbench:ListTabs",
      "sqlworkbench:UpdateFolder",
      "sqlworkbench:ListRedshiftClusters",
      "sqlworkbench:DriverExecute",
      "sqlworkbench:ListTaggedResources",
      "sqlworkbench:ListQueryExecutionHistory",
      "sqlworkbench:GetQueryExecutionHistory",
      "sqlworkbench:ListNotebooks",
      "sqlworkbench:GetSchemaInference",
      "sqlworkbench:CreateAccount",
      "sqlworkbench:TagResource",
      "sqlworkbench:CreateConnection",
      "sqlworkbench:GetConnection",
      "sqlworkbench:UpdateConnection",
      "sqlworkbench:GetAutocompletionMetadata",
      "sqlworkbench:GetAutocompletionResource",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:List*",
      "athena:GetDatabase",
      "athena:GetDataCatalog",
      "athena:GetTableMetadata",
      "athena:ListDatabases",
      "athena:ListDataCatalogs",
      "athena:ListTableMetadata",
      "athena:ListWorkGroups",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:GetWorkGroup",
      "athena:StartQueryExecution",
      "athena:StopQueryExecution",
      "s3:List*",
      "s3:Get*",
      "s3:PutObject",
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "ec2:DescribeInstances",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "glue:GetTables",
      "glue:GetPartitions",
      "glue:BatchGetPartition",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetDatabase",
      "glue:GetPartition",
      "glue:StartJobRun",
      "glue:BatchStopJobRun",
      "glue:ResetJobBookmark",
      "glue:UpdateJob",
      "glue:UseGlueStudio",
      "glue:GetJobs",
      "glue:GetJobRun",
      "glue:GetJobRuns",
      "glue:StartTrigger",
      "glue:StopTrigger",
      "glue:GetConnection",
      "glue:GetConnections",
      "logs:DescribeLogStreams",
      "logs:GetLogEvents",
      "dynamodb:BatchGet*",
      "dynamodb:DescribeStream",
      "dynamodb:DescribeTable",
      "dynamodb:Get*",
      "dynamodb:Query",
      "dynamodb:Scan",
      "redshift:*",
      "redshift-data:*",
      "redshift-serverless:*",
      "kinesis:Get*",
      "kinesis:DescribeStreamSummary",
      "kinesis:ListStreams",
      "kinesis:PutRecord",
      "kinesis:CreateStream",
      "cloudwatch:GetDashboard",
      "cloudwatch:ListDashboards",
      "states:StartExecution",
      "states:StopExecution",
      "states:RedriveExecution",
      "scheduler:UpdateSchedule",
      "kinesisanalytics:StartApplication",
      "kinesisanalytics:StopApplication",
      "kinesisanalytics:CreateApplicationSnapshot",
      "kinesisanalytics:List*",
      "kinesisanalytics:Describe*",
      "kinesisanalytics:DiscoverInputSchema",
      "kinesisanalytics:RollbackApplication",
      "lambda:InvokeFunction"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "iamPassRoleForReportingOperations"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["redshift.amazonaws.com", "dms.amazonaws.com", "glue.amazonaws.com", "kinesisanalytics.amazonaws.com"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DeleteSecret",
      "secretsmanager:TagResource"
    ]
    resources = ["arn:aws:secretsmanager:*:*:sqlworkbench!*"]
  }

}

data "aws_iam_policy_document" "powerbi_user_additional" {
  statement {
    effect = "Allow"
    resources = [
      "arn:aws:s3:::alpha-everyone/*",
      "arn:aws:s3:::alpha-postcodes/database/postcodes/*",
      "arn:aws:s3:::alpha-postcodes/database/names/*",
      "arn:aws:s3:::mojap-derived-tables/prod/models/*",
      "arn:aws:s3:::mojap-derived-tables/dev/models/*",
      "arn:aws:s3:::mojap-derived-tables/seeds/*"
    ]
    actions = [
      "s3:GetObject",
      "s3:GetObjectAcl",
      "s3:GetObjectVersion"
    ]
    sid = "S3ReadOnly"
  }

  statement {
    actions = [
      "s3:ListBucket",
      "s3:ListAllMyBuckets",
      "s3:GetBucketLocation"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:s3:::alpha-everyone",
      "arn:aws:s3:::alpha-postcodes",
      "arn:aws:s3:::dbt-query-dump",
      "arn:aws:s3:::mojap-derived-tables",
      "arn:aws:s3:::alpha-athena-query-dump",
      "arn:aws:s3:::mojap-athena-query-dump",
      "arn:aws:s3:::alpha-everyone/*",
      "arn:aws:s3:::alpha-postcodes/database/postcodes/*",
      "arn:aws:s3:::alpha-postcodes/database/names/*",
      "arn:aws:s3:::mojap-derived-tables/prod/models/*",
      "arn:aws:s3:::mojap-derived-tables/dev/models/*",
      "arn:aws:s3:::mojap-derived-tables/seeds/*"
    ]
    sid = "List"
  }

  statement {
    effect    = "Allow"
    resources = ["arn:aws:s3:::aws-athena-query-results-*"]
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    sid = "ReadWriteQueryResults"
  }

  statement {
    effect = "Allow"
    resources = [
      "arn:aws:s3:::alpha-athena-query-dump/$${aws:userid}/*",
      "arn:aws:s3:::mojap-athena-query-dump/$${aws:userid}/*"
    ]
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    sid = "ReadWriteQueryDump"
  }

  statement {
    sid       = "AllowReadAthenaGlue"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "athena:BatchGetNamedQuery",
      "athena:BatchGetQueryExecution",
      "athena:GetNamedQuery",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:GetQueryResultsStream",
      "athena:GetWorkGroup",
      "athena:ListNamedQueries",
      "athena:ListWorkGroups",
      "athena:StartQueryExecution",
      "athena:StopQueryExecution",
      "athena:CancelQueryExecution",
      "athena:GetCatalogs",
      "athena:GetExecutionEngine",
      "athena:GetExecutionEngines",
      "athena:GetNamespace",
      "athena:GetNamespaces",
      "athena:GetTable",
      "athena:GetTables",
      "athena:RunQuery",
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:BatchGetPartition",
      "glue:GetCatalogImportStatus",
      "glue:GetUserDefinedFunction",
      "glue:GetUserDefinedFunctions"
    ]
  }

  statement {
    sid       = "AllowGetPutObject"
    effect    = "Allow"
    resources = ["arn:aws:s3:::aws-athena-query-results-593291632749-eu