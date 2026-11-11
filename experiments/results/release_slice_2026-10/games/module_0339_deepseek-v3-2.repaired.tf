# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

data "local_file" "account_request_buildspec" {
  filename = "${path.module}/buildspecs/ct-aft-account-request.yml"
}
data "local_file" "account_provisioning_customizations_buildspec" {
  filename = "${path.module}/buildspecs/ct-aft-account-provisioning-customizations.yml"
}

resource "aws_codebuild_project" "account_request" {
  depends_on     = [aws_cloudwatch_log_group.account_request, time_sleep.iam_eventual_consistency]
  name           = "ct-aft-account-request"
  description    = "Job to apply Terraform for Account Requests"
  build_timeout  = tostring(var.global_codebuild_timeout)
  service_role   = aws_iam_role.account_request_codebuild_role.arn
  encryption_key = var.aft_kms_key_arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    environment_variable {
      name  = "AWS_PARTITION"
      value = data.aws_partition.current.partition
      type  = "PLAINTEXT"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.account_request.name
    }

    s3_logs {
      status   = "ENABLED"
      location = "${var.codepipeline_s3_bucket_name}/ct-aft-account-request-logs"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = data.local_file.account_request_buildspec.content
  }

  dynamic "vpc_config" {
    for_each = var.aft_enable_vpc ? [1] : []
    content {
      vpc_id             = var.vpc_id
      subnets            = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  lifecycle {
    ignore_changes = [project_visibility]
  }

}

resource "aws_codebuild_project" "account_provisioning_customizations_pipeline" {
  depends_on     = [aws_cloudwatch_log_group.account_request, time_sleep.iam_eventual_consistency]
  name           = "ct-aft-account-provisioning-customizations"
  description    = "Deploys the Account Provisioning Customizations terraform project"
  build_timeout  = tostring(var.global_codebuild_timeout)
  service_role   = aws_iam_role.account_provisioning_customizations_codebuild_role.arn
  encryption_key = var.aft_kms_key_arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_PARTITION"
      value = data.aws_partition.current.partition
      type  = "PLAINTEXT"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.account_provisioning_customizations.name
    }

    s3_logs {
      status   = "ENABLED"
      location = "${var.codepipeline_s3_bucket_name}/ct-aft-account-provisioning-customization-logs"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = data.local_file.account_provisioning_customizations_buildspec.content
  }

  dynamic "vpc_config" {
    for_each = var.aft_enable_vpc ? [1] : []
    content {
      vpc_id             = var.vpc_id
      subnets            = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  lifecycle {
    ignore_changes = [project_visibility]
  }

}

resource "aws_cloudwatch_log_group" "account_request" {
  name              = "/aws/codebuild/ct-aft-account-request"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? var.aft_kms_key_arn : null
}

resource "aws_cloudwatch_log_group" "account_provisioning_customizations" {
  name              = "/aws/codebuild/ct-aft-account-provisioning-customizations"
  retention_in_days = var.cloudwatch_log_group_retention
  kms_key_id        = var.cloudwatch_log_group_enable_cmk_encryption ? var.aft_kms_key_arn : null
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
resource "aws_codecommit_repository" "global_customizations" {
  count           = local.vcs.is_codecommit ? 1 : 0
  repository_name = var.global_customizations_repo_name
  description     = "This repo holds the Global Customizations for the CT-AFT solution"
  default_branch  = var.global_customizations_repo_branch
}

resource "aws_codecommit_repository" "account_customizations" {
  count           = local.vcs.is_codecommit ? 1 : 0
  repository_name = var.account_customizations_repo_name
  description     = "This repo holds the Account Customizations for the CT-AFT solution"
  default_branch  = var.account_customizations_repo_branch
}

resource "aws_codecommit_repository" "account_request" {
  count           = local.vcs.is_codecommit ? 1 : 0
  repository_name = var.account_request_repo_name
  description     = "This repo holds the Account Request Terraform for the CT-AFT solution"
  default_branch  = var.account_request_repo_branch
}

resource "aws_codecommit_repository" "account_provisioning_customizations" {
  count           = local.vcs.is_codecommit ? 1 : 0
  repository_name = var.account_provisioning_customizations_repo_name
  description     = "This repo holds the Account Provisioning Customizations Step Function Terraform Project"
  default_branch  = var.account_provisioning_customizations_repo_branch
}

resource "aws_codecommit_approval_rule_template_association" "global_customizations" {
  count                  = local.vcs.is_codecommit ? 1 : 0
  repository_name        = aws_codecommit_repository.global_customizations[0].repository_name
  approval_rule_template_name = "2-approvers-required"
}

resource "aws_codecommit_approval_rule_template_association" "account_customizations" {
  count                  = local.vcs.is_codecommit ? 1 : 0
  repository_name        = aws_codecommit_repository.account_customizations[0].repository_name
  approval_rule_template_name = "2-approvers-required"
}

resource "aws_codecommit_approval_rule_template_association" "account_request" {
  count                  = local.vcs.is_codecommit ? 1 : 0
  repository_name        = aws_codecommit_repository.account_request[0].repository_name
  approval_rule_template_name = "2-approvers-required"
}

resource "aws_codecommit_approval_rule_template_association" "account_provisioning_customizations" {
  count                  = local.vcs.is_codecommit ? 1 : 0
  repository_name        = aws_codecommit_repository.account_provisioning_customizations[0].repository_name
  approval_rule_template_name = "2-approvers-required"
}

resource "aws_codecommit_approval_rule_template" "default" {
  count    = local.vcs.is_codecommit ? 1 : 0
  name     = "2-approvers-required"
  description = "Requires at least 2 approvals for pull requests"
  content  = jsonencode({
    Version = "2018-11-08",
    DestinationReferences = ["refs/heads/*"],
    Statements = [{
      Type = "Approvers",
      NumberOfApprovalsNeeded = 2,
      ApprovalPoolMembers = ["*"]
    }]
  })
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
##############################################################
# CodeCommit - account-request
##############################################################

resource "aws_codepipeline" "codecommit_account_request" {
  count         = local.vcs.is_codecommit ? 1 : 0
  name          = "ct-aft-account-request"
  role_arn      = aws_iam_role.account_request_codepipeline_role.arn
  pipeline_type = "V2"

  artifact_store {
    location = var.codepipeline_s3_bucket_name
    type     = "S3"

    encryption_key {
      id   = var.aft_kms_key_arn
      type = "KMS"
    }
  }

  ##############################################################
  # Source
  ##############################################################
  stage {
    name = "Source"

    action {
      name             = "account-request"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["account-request"]

      configuration = {
        RepositoryName       = var.account_request_repo_name
        BranchName           = var.account_request_repo_branch
        PollForSourceChanges = false
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  ##############################################################
  # Apply Account Request
  ##############################################################
  stage {
    name = "terraform-apply"

    action {
      name             = "Apply-Terraform"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["account-request"]
      output_artifacts = ["account-request-terraform"]
      version          = "1"
      run_order        = "2"
      configuration = {
        ProjectName = aws_codebuild_project.account_request.name
      }
    }
  }
}

# Trigger Pipeline on Commit
resource "aws_cloudwatch_event_rule" "account_request" {
  count       = local.vcs.is_codecommit ? 1 : 0
  name        = "aft-account-request-codepipeline-trigger"
  description = "Trigger CodePipeline upon commit"

  event_pattern = <<EOF
{
  "source": [
    "aws.codecommit"
  ],
  "detail-type": [
    "CodeCommit Repository State Change"
  ],
  "resources": [
    "${aws_codecommit_repository.account_request[0].arn}"
  ],
  "detail": {
    "event": [
      "referenceCreated",
      "referenceUpdated"
    ],
    "referenceType": [
      "branch"
    ],
    "referenceName": [
      "${var.account_request_repo_branch}"
    ]
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "account_request" {
  count     = local.vcs.is_codecommit ? 1 : 0
  target_id = "codepipeline"
  rule      = aws_cloudwatch_event_rule.account_request[0].name
  arn       = aws_codepipeline.codecommit_account_request[0].arn
  role_arn  = aws_iam_role.cloudwatch_events_codepipeline_role[0].arn
}

##############################################################
# CodeConnections - account-request
##############################################################

moved {
  from = aws_codepipeline.codestar_account_request
  to   = aws_codepipeline.codeconnections_account_request
}

resource "aws_codepipeline" "codeconnections_account_request" {
  count         = local.vcs.is_codecommit ? 0 : 1
  name          = "ct-aft-account-request"
  role_arn      = aws_iam_role.account_request_codepipeline_role.arn
  pipeline_type = "V2"

  artifact_store {
    location = var.codepipeline_s3_bucket_name
    type     = "S3"

    encryption_key {
      id   = var.aft_kms_key_arn
      type = "KMS"
    }
  }

  ##############################################################
  # Source
  ##############################################################
  stage {
    name = "Source"

    action {
      name             = "account-request"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["account-request"]

      configuration = {
        ConnectionArn        = lookup({ github = local.connection_arn.github, bitbucket = local.connection_arn.bitbucket, githubenterprise = local.connection_arn.githubenterprise, gitlab = local.connection_arn.gitlab, gitlabselfmanaged = local.connection_arn.gitlabselfmanaged, azuredevops = local.connection_arn.azuredevops }, var.vcs_provider)
        FullRepositoryId     = var.account_request_repo_name
        BranchName           = var.account_request_repo_branch
        DetectChanges        = true
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  ##############################################################
  # Apply Account Request
  ##############################################################
  stage {
    name = "terraform-apply"

    action {
      name             = "Apply-Terraform"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["account-request"]
      output_artifacts = ["account-request-terraform"]
      version          = "1"
      run_order        = "2"
      configuration = {
        ProjectName = aws_codebuild_project.account_request.name
      }
    }
  }
}

##############################################################
# CodeCommit - account-provisioning-customizations
##############################################################

resource "aws_codepipeline" "codecommit_account_provisioning_customizations" {
  count         = local.vcs.is_codecommit ? 1 : 0
  name          = "ct-aft-account-provisioning-customizations"
  role_arn      = aws_iam_role.account_provisioning_customizations_codepipeline_role.arn
  pipeline_type = "V2"

  artifact_store {
    location = var.codepipeline_s3_bucket_name
    type     = "S3"

    encryption_key {
      id   = var.aft_kms_key_arn
      type = "KMS"
    }
  }

  ##############################################################
  # Source
  ##############################################################
  stage {
    name = "Source"

    action {
      name             = "account-provisioning-customizations"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["account-provisioning-customizations"]

      configuration = {
        RepositoryName       = var.account_provisioning_customizations_repo_name
        BranchName           = var.account_provisioning_customizations_repo_branch
        PollForSourceChanges = false
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  ##############################################################
  # Account Provisioning Customizations - Terraform Apply
  ##############################################################
  stage {
    name = "terraform-apply"

    action {
      name             = "Apply-Terraform"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["account-provisioning-customizations"]
      output_artifacts = ["account-provisioning-customizations-output"]
      version          = "1"
      run_order        = "2"
      configuration = {
        ProjectName = aws_codebuild_project.account_provisioning_customizations_pipeline.name
      }
    }
  }
}

##############################################################
# CodeConnections - account-provisioning-customizations
##############################################################

moved {
  from = aws_codepipeline.codestar_account_provisioning_customizations
  to   = aws_codepipeline.codeconnections_account_provisioning_customizations
}
resource "aws_codepipeline" "codeconnections_account_provisioning_customizations" {
  count         = local.vcs.is_codecommit ? 0 : 1
  name          = "ct-aft-account-provisioning-customizations"
  role_arn      = aws_iam_role.account_provisioning_customizations_codepipeline_role.arn
  pipeline_type = "V2"

  artifact_store {
    location = var.codepipeline_s3_bucket_name
    type     = "S3"

    encryption_key {
      id   = var.aft_kms_key_arn
      type = "KMS"
    }
  }

  ##############################################################
  # Source
  ##############################################################
  stage {
    name = "Source"

    action {
      name             = "account-provisioning-customizations"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["account-provisioning-customizations"]

      configuration = {
        ConnectionArn        = lookup({ github = local.connection_arn.github, bitbucket = local.connection_arn.bitbucket, githubenterprise = local.connection_arn.githubenterprise, gitlab = local.connection_arn.gitlab, gitlabselfmanaged = local.connection_arn.gitlabselfmanaged, azuredevops = local.connection_arn.azuredevops }, var.vcs_provider)
        FullRepositoryId     = var.account_provisioning_customizations_repo_name
        BranchName           = var.account_provisioning_customizations_repo_branch
        DetectChanges        = true
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  ##############################################################
  # Account Provisioning Customizations - Terraform Apply
  ##############################################################
  stage {
    name = "terraform-apply"

    action {
      name             = "Apply-Terraform"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["account-provisioning-customizations"]
      output_artifacts = ["account-provisioning-customizations-output"]
      version          = "1"
      run_order        = "2"
      configuration = {
        ProjectName = aws_codebuild_project.account_provisioning_customizations_pipeline.name
      }
    }
  }
}

# Trigger Pipeline on Commit
resource "aws_cloudwatch_event_rule" "account_provisioning_customizations" {
  count       = local.vcs.is_codecommit ? 1 : 0
  name        = "aft-account-provisioning-customizations-trigger"
  description = "Trigger CodePipeline upon commit"

  event_pattern = <<EOF
{
  "source": [
    "aws.codecommit"
  ],
  "detail-type": [
    "CodeCommit Repository State Change"
  ],
  "resources": [
    "${aws_codecommit_repository.account_provisioning_customizations[0].arn}"
  ],
  "detail": {
    "event": [
      "referenceCreated",
      "referenceUpdated"
    ],
    "referenceType": [
      "branch"
    ],
    "referenceName": [
      "${var.account_provisioning_customizations_repo_branch}"
    ]
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "account_provisioning_customizations" {
  count     = local.vcs.is_codecommit ? 1 : 0
  target_id = "codepipeline"
  rule      = aws_cloudwatch_event_rule.account_provisioning_customizations[0].name
  arn       = aws_codepipeline.codecommit_account_provisioning_customizations[0].arn
  role_arn  = aws_iam_role.cloudwatch_events_codepipeline_role[0].arn
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

resource "aws_codeconnections_connection" "bitbucket" {
  count         = local.vcs.is_bitbucket ? 1 : 0
  name          = "ct-aft-bitbucket-connection"
  provider_type = "Bitbucket"
}

resource "aws_codeconnections_connection" "github" {
  count         = local.vcs.is_github ? 1 : 0
  name          = "ct-aft-github-connection"
  provider_type = "GitHub"
}

resource "aws_codeconnections_connection" "githubenterprise" {
  count    = local.vcs.is_github_enterprise ? 1 : 0
  name     = "ct-aft-github-ent-connection"
  host_arn = aws_codeconnections_host.githubenterprise[0].arn
}


resource "aws_codeconnections_host" "githubenterprise" {
  count             = local.vcs.is_github_enterprise ? 1 : 0
  name              = "github-enterprise-host"
  provider_endpoint = var.github_enterprise_url
  provider_type     = "GitHubEnterpriseServer"

  dynamic "vpc_configuration" {
    for_each = var.aft_enable_vpc ? [1] : []
    content {
      security_group_ids = var.security_group_ids
      subnet_ids         = var.subnet_ids
      vpc_id             = var.vpc_id
    }
  }
}

resource "aws_codeconnections_connection" "gitlab" {
  count         = local.vcs.is_gitlab ? 1 : 0
  name          = "ct-aft-gitlab-connection"
  provider_type = "GitLab"
}

resource "aws_codeconnections_connection" "gitlabselfmanaged" {
  count    = local.vcs.is_gitlab_selfmanaged ? 1 : 0
  name     = "ct-aft-gitlab-selfmgd-connection"
  host_arn = aws_codeconnections_host.gitlabselfmanaged[0].arn
}

resource "aws_codeconnections_host" "gitlabselfmanaged" {
  count             = local.vcs.is_gitlab_selfmanaged ? 1 : 0
  name              = "gitlab-selfmanaged-host"
  provider_endpoint = var.gitlab_selfmanaged_url
  provider_type     = "GitLabSelfManaged"

  dynamic "vpc_configuration" {
    for_each = var.aft_enable_vpc ? [1] : []
    content {
      security_group_ids = var.security_group_ids
      subnet_ids         = var.subnet_ids
      vpc_id             = var.vpc_id
    }
  }
}

resource "aws_codeconnections_connection" "azuredevops" {
  count         = local.vcs.is_azuredevops ? 1 : 0
  name          = "ct-aft-azuredevops-connection"
  provider_type = "AzureDevOps"
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# CodePipeline Roles

resource "aws_iam_role" "account_request_codepipeline_role" {
  name               = "ct-aft-codepipeline-account-request-role"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/codepipeline.tpl", { none = "none" })
}

resource "aws_iam_role_policy" "account_request_codepipeline_policy" {
  name = "ct-aft-codepipeline-account-request-policy"
  role = aws_iam_role.account_request_codepipeline_role.id

  policy = templatefile("${path.module}/iam/role-policies/ct_aft_account_request_codepipeline_policy.tpl", {
    aws_s3_bucket_aft_codepipeline_customizations_bucket_arn = var.codepipeline_s3_bucket_arn
    data_aws_partition_current_partition                     = data.aws_partition.current.partition
    data_aws_region_current_name                             = data.aws_region.current.region
    data_aws_caller_identity_current_account_id              = data.aws_caller_identity.current.account_id
    data_aws_kms_alias_aft_key_target_key_arn                = var.aft_kms_key_arn
  })
}

resource "aws_iam_role" "account_provisioning_customizations_codepipeline_role" {
  name               = "ct-aft-codepipeline-account-provisioning-customizations-role"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/codepipeline.tpl", { none = "none" })
}

resource "aws_iam_role_policy" "account_provisioning_customizations_codepipeline_policy" {
  name = "ct-aft-codepipeline-account-provisioning-customizations-policy"
  role = aws_iam_role.account_provisioning_customizations_codepipeline_role.id

  policy = templatefile("${path.module}/iam/role-policies/ct_aft_account_provisioning_customizations_codepipeline_policy.tpl", {
    aws_s3_bucket_aft_codepipeline_customizations_bucket_arn = var.codepipeline_s3_bucket_arn
    data_aws_partition_current_partition                     = data.aws_partition.current.partition
    data_aws_region_current_name                             = data.aws_region.current.region
    data_aws_caller_identity_current_account_id              = data.aws_caller_identity.current.account_id
    data_aws_kms_alias_aft_key_target_key_arn                = var.aft_kms_key_arn
  })
}

# Codebuild Role

resource "aws_iam_role" "account_provisioning_customizations_codebuild_role" {
  name               = "ct-aft-codebuild-account-provisioning-customizations-role"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/codebuild.tpl", { none = "none" })
}

resource "aws_iam_role_policy" "account_provisioning_customizations_codebuild_policy" {
  name = "ct-aft-codebuild-account-provisioning-customizations-policy"
  role = aws_iam_role.account_provisioning_customizations_codebuild_role.id

  policy = templatefile("${path.module}/iam/role-policies/ct_aft_codebuild_policy.tpl", {
    aws_s3_bucket_aft_codepipeline_customizations_bucket_arn = var.codepipeline_s3_bucket_arn
    data_aws_partition_current_partition                     = data.aws_partition.current.partition
    data_aws_region_current_name                             = data.aws_region.current.region
    data_aws_caller_identity_current_account_id              = data.aws_caller_identity.current.account_id
    data_aws_kms_alias_aft_key_target_key_arn                = var.aft_kms_key_arn
    data_aws_dynamo_account_request_table                    = var.account_request_table_name
  })
}

resource "aws_iam_role_policy" "terraform_oss_backend_account_provisioning_customizations_codebuild_policy" {
  count = var.terraform_distribution == "oss" ? 1 : 0
  name  = "ct-aft-codebuild-terraform-oss-backend-policy"
  role  = aws_iam_role.account_provisioning_customizations_codebuild_role.id

  policy = templatefile("${path.module}/iam/role-policies/ct_aft_codebuild_oss_backend_policy.tpl", {
    data_aws_partition_current_partition              = data.aws_partition.current.partition
    data_aws_region_current_name                      = data.aws_region.current.region
    data_aws_caller_identity_current_account_id       = data.aws_caller_identity.current.account_id
    data_aws_dynamo_terraform_oss_backend_table       = var.aft_config_backend_table_id
    aws_s3_bucket_aft_terraform_oss_backend_bucket_id = var.aft_config_backend_bucket_id
    aws_s3_bucket_aft_terraform_oss_kms_key_id        = var.aft_config_backend_kms_key_id
  })
}

resource "aws_iam_role" "account_request_codebuild_role" {
  name               = "ct-aft-codebuild-account-request-role"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/codebuild.tpl", { none = "none" })
}

resource "aws_iam_role_policy" "account_request_codebuild_policy" {
  name = "ct-aft-codebuild-account-request-policy"
  role = aws_iam_role.account_request_codebuild_role.id

  policy = templatefile("${path.module}/iam/role-policies/ct_aft_codebuild_policy.tpl", {
    aws_s3_bucket_aft_codepipeline_customizations_bucket_arn = var.codepipeline_s3_bucket_arn
    data_aws_partition_current_partition                     = data.aws_partition.current.partition
    data_aws_region_current_name                             = data.aws_region.current.region
    data_aws_caller_identity_current_account_id              = data.aws_caller_identity.current.account_id
    data_aws_kms_alias_aft_key_target_key_arn                = var.aft_kms_key_arn
    data_aws_dynamo_account_request_table                    = var.account_request_table_name
  })
}

resource "aws_iam_role_policy" "terraform_oss_backend_account_request_codebuild_policy" {
  count = var.terraform_distribution == "oss" ? 1 : 0
  name  = "ct-aft-codebuild-terraform-oss-backend-policy"
  role  = aws_iam_role.account_request_codebuild_role.id

  policy = templatefile("${path.module}/iam/role-policies/ct_aft_codebuild_oss_backend_policy.tpl", {
    data_aws_partition_current_partition              = data.aws_partition.current.partition
    data_aws_region_current_name                      = data.aws_region.current.region
    data_aws_caller_identity_current_account_id       = data.aws_caller_identity.current.account_id
    data_aws_dynamo_terraform_oss_backend_table       = var.aft_config_backend_table_id
    aws_s3_bucket_aft_terraform_oss_backend_bucket_id = var.aft_config_backend_bucket_id
    aws_s3_bucket_aft_terraform_oss_kms_key_id        = var.aft_config_backend_kms_key_id
  })
}

resource "time_sleep" "iam_eventual_consistency" {
  depends_on      = [aws_iam_role.account_request_codebuild_role]
  create_duration = "60s"
}

# CloudWatch Events Role

resource "aws_iam_role" "cloudwatch_events_codepipeline_role" {
  count              = local.vcs.is_codecommit ? 1 : 0
  name               = "ct-aft-cwe-codepipeline-role"
  assume_role_policy = templatefile("${path.module}/iam/trust-policies/events.tpl", { none = "none" })
}

resource "aws_iam_role_policy" "cloudwatch_events_codepipeline_role" {
  count = local.vcs.is_codecommit ? 1 : 0
  name  = "ct-aft-cwe-codepipeline-role-policy"
  role  = aws_iam_role.cloudwatch_events_codepipeline_role[0].id

  policy = templatefile("${path.module}/iam/role-policies/ct_aft_cwe_policy.tpl", {
    data_aws_partition_current_partition      = data.aws_partition.current.partition
    region                                    = data.aws_region.current.region
    account_id                                = data.aws_caller_identity.current.account_id
    account_request_pipeline_name             = aws_codepipeline.codecommit_account_request[0].name
    provisioning_customizations_pipeline_name = aws_codepipeline.codecommit_account_provisioning_customizations[0].name
  })
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
locals {
  vcs = {
    is_codecommit         = lower(var.vcs_provider) == "codecommit" ? true : false
    is_bitbucket          = lower(var.vcs_provider) == "bitbucket" ? true : false
    is_github             = lower(var.vcs_provider) == "github" ? true : false
    is_github_enterprise  = lower(var.vcs_provider) == "githubenterprise" ? true : false
    is_gitlab             = lower(var.vcs_provider) == "gitlab" ? true : false
    is_gitlab_selfmanaged = lower(var.vcs_provider) == "gitlabselfmanaged" ? true : false
    is_azuredevops        = lower(var.vcs_provider) == "azuredevops" ? true : false
  }
  connection_arn = {
    bitbucket         = lower(var.vcs_provider) == "bitbucket" ? aws_codeconnections_connection.bitbucket[0].arn : ""
    github            = lower(var.vcs_provider) == "github" ? aws_codeconnections_connection.github[0].arn : ""
    githubenterprise  = lower(var.vcs_provider) == "githubenterprise" ? aws_codeconnections_connection.githubenterprise[0].arn : ""
    gitlab            = lower(var.vcs_provider) == "gitlab" ? aws_codeconnections_connection.gitlab[0].arn : ""
    gitlabselfmanaged = lower(var.vcs_provider) == "gitlabselfmanaged" ? aws_codeconnections_connection.gitlabselfmanaged[0].arn : ""
    azuredevops       = lower(var.vcs_provider) == "azuredevops" ? aws_codeconnections_connection.azuredevops[0].arn : ""
    codecommit        = "null"
  }
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
output "codeconnections_connection_arn" {
  value = lookup(local.connection_arn, var.vcs_provider)
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type    = list(string)
  default = null
}

variable "security_group_ids" {
  type = list(string)
}

variable "cloudwatch_log_group_retention" {
  type = string
}

variable "cloudwatch_log_group_enable_cmk_encryption" {
  type = bool
}

variable "vcs_provider" {
  type = string
}

variable "terraform_distribution" {
  type = string
}

variable "github_enterprise_url" {
  type = string
}

variable "gitlab_selfmanaged_url" {
  type = string
}

variable "account_request_table_name" {
  type = string
}

variable "aft_config_backend_table_id" {
  type = string
}

variable "aft_config_backend_bucket_id" {
  type = string
}

variable "aft_config_backend_kms_key_id" {
  type = string
}

variable "codepipeline_s3_bucket_name" {
  type = string
}

variable "codepipeline_s3_bucket_arn" {
  type = string
}

variable "aft_kms_key_arn" {
  type = string
}

variable "account_request_repo_name" {
  type = string
}

variable "account_request_repo_branch" {
  type = string
}

variable "global_customizations_repo_name" {
  type = string
}

variable "global_customizations_repo_branch" {
  type = string
}

variable "account_customizations_repo_name" {
  type = string
}

variable "account_customizations_repo_branch" {
  type = string
}

variable "account_provisioning_customizations_repo_name" {
  type = string
}

variable "account_provisioning_customizations_repo_branch" {
  type = string
}

variable "global_codebuild_timeout" {
  type = number
}

variable "aft_enable_vpc" {
  type = bool
}

variable "codebuild_compute_type" {
  type = string
}


# Copyright Amazon.com, Inc. or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
terraform {
  required_version = ">= 1.2.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}