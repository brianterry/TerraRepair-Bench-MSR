/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

locals {
  eks_resource_pb_name = "EKSResourcesPermissionBoundary"
}

// Bondary imposed on all IAM roles provisioned by EKSInfraAdmin role.
resource "aws_iam_policy" "eks_resources_permission_boundary" {
  name        = local.eks_resource_pb_name
  path        = "/boundary/"
  description = "Permission boundary for roles created by EKSInfraAdmin."
  policy      = data.aws_iam_policy_document.eks_resources_permission_boundary_doc.json
  tags        = var.tags
}

data "aws_iam_policy_document" "eks_resources_permission_boundary_doc" {
  statement {
    sid    = "AllowAutoScaling"
    effect = "Allow"

    actions = [
      "autoscaling:*",
    ]

    resources = ["arn:aws:autoscaling:*:${local.account_id}:*"]
  }

  statement {
    sid    = "AllowEC2"
    effect = "Allow"

    actions = [
      "ec2:*",
    ]

    resources = ["arn:aws:ec2:*:${local.account_id}:*"]
  }

  statement {
    sid    = "AllowECR"
    effect = "Allow"

    actions = [
      "ecr:*",
    ]

    resources = ["arn:aws:ecr:*:${local.account_id}:*"]
  }

  statement {
    sid    = "AllowECRPublic"
    effect = "Allow"

    actions = [
      # TODO(xmudrii-ubuntu): remove after removing ECR repo
      "ecr-public:*"
    ]

    resources = ["arn:aws:ecr-public::${local.account_id}:*"]
  }

  statement {
    sid    = "AllowEKS"
    effect = "Allow"

    actions = [
      "eks:*",
      "eks-auth:AssumeRoleForPodIdentity",
    ]

    resources = ["arn:aws:eks:*:${local.account_id}:*"]
  }

  statement {
    sid    = "AllowELB"
    effect = "Allow"

    actions = [
      "elasticloadbalancing:*",
    ]

    resources = ["arn:aws:elasticloadbalancing:*:${local.account_id}:*"]
  }

  statement {
    sid    = "AllowIAM"
    effect = "Allow"

    actions = [
      "iam:AttachRolePolicy",
      "iam:AttachUserPolicy",
      "iam:CreateOpenIDConnectProvider",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:CreateRole",
      "iam:CreateUser",
      "iam:DeleteOpenIDConnectProvider",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:DeleteRole",
      "iam:DeleteRolePermissionsBoundary",
      "iam:DeleteRolePolicy",
      "iam:DeleteUserPolicy",
      "iam:DetachRolePolicy",
      "iam:DetachUserPolicy",
      "iam:GetOpenIDConnectProvider",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:GetUser",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListPolicies",
      "iam:ListPolicyVersions",
      "iam:ListRolePolicies",
      "iam:ListRoles",
      "iam:PassRole",
      "iam:PutRolePermissionsBoundary",
      "iam:PutRolePolicy",
      "iam:PutUserPermissionsBoundary",
      "iam:PutUserPolicy",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagOpenIDConnectProvider",
      "iam:TagPolicy",
      "iam:TagRole",
      "iam:UntagPolicy",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateOpenIDConnectProviderThumbprint",
    ]

    resources = ["arn:aws:iam::${local.account_id}:*"]
  }

  statement {
    sid    = "AllowKMS"
    effect = "Allow"

    actions = [
      "kms:*",
    ]

    resources = ["arn:aws:kms:*:${local.account_id}:*"]
  }

  statement {
    sid    = "AllowLogs"
    effect = "Allow"

    actions = [
      "logs:*",
    ]

    resources = ["arn:aws:logs:*:${local.account_id}:*"]
  }

  statement {
    sid    = "AllowS3"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = ["arn:aws:s3:::*"]
  }

  statement {
    sid    = "AllowSecretsManager"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = ["arn:aws:secretsmanager:*:${local.account_id}:*"]
  }

  statement {
    sid    = "AllowSTS"
    effect = "Allow"

    actions = [
      "sts:AssumeRole",
      "sts:AssumeRoleWithWebIdentity",
      "sts:TagSession",
      "sts:GetCallerIdentity",
    ]

    resources = ["arn:aws:iam::${local.account_id}:*"]
  }

  statement {
    sid = "DenyCreateWithoutBoundary"

    effect = "Deny"

    actions = [
      "iam:CreateRole",
      "iam:CreateUser",
    ]

    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values = [
        "arn:aws:iam::${local.account_id}:policy/boundary/${local.eks_resource_pb_name}"
      ]
    }
  }

  statement {
    sid       = "DenyChangeWithoutBoundary"
    effect    = "Deny"
    resources = ["*"]

    actions = [
      "iam:AttachRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:PutRolePolicy",
      "iam:PutRolePermissionsBoundary",
      "iam:AttachUserPolicy",
      "iam:DeleteUserPolicy",
      "iam:DetachUserPolicy",
      "iam:PutUserPolicy",
      "iam:PutUserPermissionsBoundary",
    ]

    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values = [
        "arn:aws:iam::${local.account_id}:policy/boundary/${local.eks_resource_pb_name}"
      ]
    }
  }

  statement {
    sid = "DenyEditBoundaries"

    effect = "Deny"

    actions = [
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion"
    ]

    resources = [
      "arn:aws:iam::${local.account_id}:policy/boundary/*"
    ]
  }

  statement {
    sid = "DenyLeaveOrganisation"

    effect = "Deny"

    actions = [
      "organizations:LeaveOrganization"
    ]

    resources = ["*"]
  }
}


/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

data "aws_caller_identity" "current" {}

data "aws_iam_user" "eks_infra_admins" {
  count     = length(var.eks_infra_admins)
  user_name = var.eks_infra_admins[count.index]
}

data "aws_iam_user" "eks_infra_viewers" {
  count     = length(var.eks_infra_viewers)
  user_name = var.eks_infra_viewers[count.index]
}

locals {
  account_id = data.aws_caller_identity.current.account_id
}


/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

output "eks_infra_admin_role_arn" {
  description = "ARN of the EKS admin role."
  value       = aws_iam_role.eks_infra_admin.arn
}

output "eks_infra_viewer_role_arn" {
  description = "ARN of the EKS viewer role."
  value       = aws_iam_role.eks_viewer.arn
}

output "eks_infra_admin_permission_boundary" {
  description = "ARN of the permission boundary enforcing EKSResourcePermissionBounday on EKS IAM resources."
  value       = aws_iam_role.eks_infra_admin.arn
}

output "eks_resources_permission_boundary" {
  description = "ARN of the permission boundary enfored on EKS IAM resources."
  value       = aws_iam_policy.eks_resources_permission_boundary.arn
}


/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

resource "aws_iam_policy" "eks_apply" {
  name_prefix = "EKSClusterApplier"
  path        = "/terraform/eks/"
  policy      = data.aws_iam_policy_document.eks_apply.json
  tags        = var.tags
}

# WARNING/TODO: This policy can allow escalating priviliges and removing deny rules!!!
# See the following comments for more details:
# - https://github.com/kubernetes/k8s.io/pull/5113#discussion_r1164205616
# - https://github.com/kubernetes/k8s.io/pull/5113#discussion_r1164206798
data "aws_iam_policy_document" "eks_apply" {
  statement {
    sid       = "AllowACM"
    effect    = "Allow"
    resources = ["arn:aws:acm:*:${local.account_id}:*"]

    actions = [
      "acm:AddTagsToCertificate",
      "acm:RequestCertificate",
    ]
  }

  statement {
    sid       = "AllowAutoScaling"
    effect    = "Allow"
    resources = ["arn:aws:autoscaling:*:${local.account_id}:*"]

    actions = [
      "autoscaling:CreateOrUpdateTags",
    ]
  }

  statement {
    sid       = "AllowEC2"
    effect    = "Allow"
    resources = ["arn:aws:ec2:*:${local.account_id}:*"]

    actions = [
      "ec2:AllocateAddress",
      "ec2:AssociateRouteTable",
      "ec2:AssociateVpcCidrBlock",
      "ec2:AttachInternetGateway",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateEgressOnlyInternetGateway",
      "ec2:CreateInternetGateway",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateLaunchTemplateVersion",
      "ec2:ModifyLaunchTemplate",
      "ec2:CreateNatGateway",
      "ec2:CreateRoute",
      "ec2:CreateRouteTable",
      "ec2:CreateSecurityGroup",
      "ec2:CreateSubnet",
      "ec2:CreateTags",
      "ec2:CreateVpc",
      "ec2:ModifySubnetAttribute",
      "ec2:ModifyVpcAttribute",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RunInstances",
      "ec2:ModifyInstanceAttribute",
      "ec2:TerminateInstances",
      "ec2:ImportKeyPair",
    ]
  }

  statement {
    sid       = "AllowEKS"
    effect    = "Allow"
    resources = ["arn:aws:eks:*:${local.account_id}:*"]

    actions = [
      "eks:CreateAccessEntry",
      "eks:CreateAddon",
      "eks:CreateCluster",
      "eks:CreateNodegroup",
      "eks:CreatePodIdentityAssociation",
      "eks:TagResource",
      "eks:UpdateAccessEntry",
      "eks:UpdateAddon",
      "eks:UpdateClusterConfig",
      "eks:UpdateClusterVersion",
      "eks:UpdateNodegroupConfig",
      "eks:UpdateNodegroupVersion",
    ]
  }

  statement {
    sid       = "AllowEvents"
    effect    = "Allow"
    resources = ["arn:aws:events:*:${local.account_id}:*"]

    actions = [
      "events:DeleteRule",
      "events:PutRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:TagResource",
    ]
  }

  statement {
    sid       = "AllowIAM"
    effect    = "Allow"
    resources = ["arn:aws:iam::${local.account_id}:*"]

    actions = [
      "iam:AttachRolePolicy",
      "iam:CreateOpenIDConnectProvider",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:CreateRole",
      "iam:TagOpenIDConnectProvider",
      "iam:TagPolicy",
      "iam:TagRole",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:UpdateAssumeRolePolicy",
    ]
  }

  statement {
    sid       = "AllowPassRoleForEKS"
    effect    = "Allow"
    resources = ["arn:aws:iam::${local.account_id}:role/*"]

    actions = [
      "iam:PassRole",
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values = [
        "eks.amazonaws.com",
        "ec2.amazonaws.com",
        "eks-fargate-pods.amazonaws.com",
        "eks-nodegroup.amazonaws.com",
      ]
    }
  }

  statement {
    sid       = "AllowKMS"
    effect    = "Allow"
    resources = ["arn:aws:kms:*:${local.account_id}:*"]

    actions = [
      "kms:CreateAlias",
      "kms:CreateGrant",
      "kms:CreateKey",
      "kms:EnableKeyRotation",
      "kms:PutKeyPolicy",
      "kms:TagResource",
    ]
  }

  statement {
    sid       = "AllowLogs"
    effect    = "Allow"
    resources = ["arn:aws:logs:*:${local.account_id}:*"]

    actions = [
      "logs:CreateLogGroup",
      "logs:PutRetentionPolicy",
      "logs:TagLogGroup",
    ]
  }

  statement {
    sid       = "AllowS3"
    effect    = "Allow"
    resources = ["arn:aws:s3:::*"]

    actions = [
      "s3:PutObject",
    ]
  }

  statement {
    sid       = "AllowSQS"
    effect    = "Allow"
    resources = ["arn:aws:sqs:*:${local.account_id}:*"]

    actions = [
      "sqs:CreateQueue",
      "sqs:DeleteQueue",
      "sqs:SetQueueAttributes",
      "sqs:TagQueue",
    ]
  }

  statement {
    sid       = "AllowECRPublic"
    effect    = "Allow"
    resources = ["arn:aws:ecr-public::${local.account_id}:*"]

    actions = [
      # TODO(xmudrii-ubuntu): remove after removing ECR repo
      "ecr-public:*"
    ]
  }

  // This statement effectively enforces EKSResourcesPermissionBoundary on IAM resources
  // created with this policy.
  statement {
    sid = "AllowCreateOnlyWithBoundary"

    effect = "Allow"

    actions = [
      "iam:CreateRole",
      "iam:CreateUser",
    ]

    resources = [
      "arn:aws:iam::${local.account_id}:role/*",
      "arn:aws:iam::${local.account_id}:user/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values = [
        aws_iam_policy.eks_resources_permission_boundary.arn
      ]
    }
  }

  statement {
    sid    = "AllowChangeOnlyWithEKSResourceBoundary"
    effect = "Allow"

    resources = [
      "arn:aws:iam::${local.account_id}:role/*",
      "arn:aws:iam::${local.account_id}:user/*",
    ]

    actions = [
      "iam:AttachRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:PutRolePolicy",
      "iam:PutRolePermissionsBoundary",
      "iam:AttachUserPolicy",
      "iam:DeleteUserPolicy",
      "iam:DetachUserPolicy",
      "iam:PutUserPolicy",
      "iam:PutUserPermissionsBoundary",
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values = [
        aws_iam_policy.eks_resources_permission_boundary.arn
      ]
    }
  }

  statement {
    sid = "DenyEditBoundaries"

    effect = "Deny"

    actions = [
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion"
    ]

    resources = [
      "arn:aws:iam::${local.account_id}:policy/boundary/*"
    ]
  }

  statement {
    sid = "DenyLeaveOrganisation"

    effect = "Deny"

    actions = [
      "organizations:LeaveOrganization"
    ]

    resources = ["*"]
  }
}


/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

resource "aws_iam_policy" "eks_destroy" {
  name_prefix = "EKSClusterDestroyer"
  path        = "/terraform/eks/"
  policy      = data.aws_iam_policy_document.eks_destroy.json
  tags        = var.tags
}

data "aws_iam_policy_document" "eks_destroy" {
  statement {
    sid       = "AllowACMDelete"
    effect    = "Allow"
    resources = ["arn:aws:acm:*:${local.account_id}:*"]

    actions = [
      "acm:DeleteCertificate",
    ]
  }

  statement {
    sid       = "AllowAutoScalingDelete"
    effect    = "Allow"
    resources = ["arn:aws:autoscaling:*:${local.account_id}:*"]

    actions = [
      "autoscaling:DeleteTags",
    ]
  }

  statement {
    sid       = "AllowEC2Delete"
    effect    = "Allow"
    resources = ["arn:aws:ec2:*:${local.account_id}:*"]

    actions = [
      "ec2:DeleteEgressOnlyInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:DeleteLaunchTemplate",
      "ec2:DeleteLaunchTemplateVersion",
      "ec2:DeleteNatGateway",
      "ec2:DeleteRoute",
      "ec2:DeleteRouteTable",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteSubnet",
      "ec2:DeleteVpc",
      "ec2:DeleteTags",
      "ec2:DetachInternetGateway",
      "ec2:DisassociateAddress",
      "ec2:DisassociateRouteTable",
      "ec2:DisassociateVpcCidrBlock",
      "ec2:ReleaseAddress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DeleteKeyPair",
      "ec2:TerminateInstances",
    ]
  }

  statement {
    sid       = "AllowEKSDelete"
    effect    = "Allow"
    resources = ["arn:aws:eks:*:${local.account_id}:*"]

    actions = [
      "eks:DeleteAddon",
      "eks:DeleteAccessEntry",
      "eks:DeleteCluster",
      "eks:DeleteNodegroup",
      "eks:DeletePodIdentityAssociation",
      "eks:UntagResource",
    ]
  }

  statement {
    sid       = "AllowEventsDelete"
    effect    = "Allow"
    resources = ["arn:aws:events:*:${local.account_id}:*"]

    actions = [
      "events:UntagResource",
    ]
  }

  statement {
    sid       = "AllowIAMDelete"
    effect    = "Allow"
    resources = ["arn:aws:iam::${local.account_id}:*"]

    actions = [
      "iam:DeleteOpenIDConnectProvider",
      "iam:DeletePolicy",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DeleteRolePermissionsBoundary",
      "iam:DetachRolePolicy",
      "iam:DeletePolicyVersion",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:UntagPolicy",
      "iam:UntagRole",
    ]
  }

  statement {
    sid       = "AllowKMSDelete"
    effect    = "Allow"
    resources = ["arn:aws:kms:*:${local.account_id}:*"]

    actions = [
      "kms:DeleteAlias",
      "kms:ScheduleKeyDeletion",
    ]
  }

  statement {
    sid       = "AllowLogsDelete"
    effect    = "Allow"
    resources = ["arn:aws:logs:*:${local.account_id}:*"]

    actions = [
      "logs:DeleteLogGroup",
    ]
  }

  statement {
    sid       = "AllowSQSDelete"
    effect    = "Allow"
    resources = ["arn:aws:sqs:*:${local.account_id}:*"]

    actions = [
      "sqs:UntagQueue"
    ]
  }

  statement {
    sid = "DenyDeleteBoundary"

    effect = "Deny"

    actions = [
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:DeleteRolePermissionsBoundary",
      "iam:DetachRolePolicy",
    ]

    resources = [
      aws_iam_policy.eks_resources_permission_boundary.arn
    ]
  }
}


/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

resource "aws_iam_policy" "eks_plan" {
  name_prefix = "EKSClusterPlanner"
  path        = "/terraform/eks/"
  policy      = data.aws_iam_policy_document.eks_plan.json
  tags        = var.tags
}

data "aws_iam_policy_document" "eks_plan" {
  statement {
    sid       = "AllowACMRead"
    effect    = "Allow"
    resources = ["arn:aws:acm:*:${local.account_id}:*"]

    actions = [
      "acm:DescribeCertificate",
      "acm:ListTagsForCertificate",
    ]
  }

  statement {
    sid       = "AllowEC2Read"
    effect    = "Allow"
    resources = ["arn:aws:ec2:*:${local.account_id}:*"]

    actions = [
      "ec2:DescribeAddresses",
      "ec2:DescribeAddressesAttribute",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeEgressOnlyInternetGateways",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceAttribute",
      "ec2:DescribeInstanceCreditSpecifications",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstances",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeNatGateways",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeNetworkAcls",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroupRules",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupReferences",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcAttribute",
      "ec2:DescribeVpcClassicLink",
      "ec2:DescribeVpcClassicLinkDnsSupport",
      "ec2:DescribeVpcs",
      "ec2:DescribeVolumes",
      "ec2:DescribeKeyPairs",
      "ec2:DescribeTags",
    ]
  }

  statement {
    sid       = "AllowEKSRead"
    effect    = "Allow"
    resources = ["arn:aws:eks:*:${local.account_id}:*"]

    actions = [
      "eks:DescribeAccessEntry",
      "eks:DescribeAddon",
      "eks:DescribeAddonVersions",
      "eks:DescribeCluster",
      "eks:DescribeNodegroup",
      "eks:DescribePodIdentityAssociation",
      "eks:DescribeUpdate",
      "eks:ListAddons",
      "eks:ListClusters",
      "eks:ListIdentityProviderConfigs",
      "eks:ListNodegroups",
      "eks:ListUpdates",
      "eks:ListTagsForResource",
    ]
  }

  statement {
    sid       = "AllowEventsRead"
    effect    = "Allow"
    resources = ["arn:aws:events:*:${local.account_id}:*"]

    actions = [
      "events:DescribeRule",
      "events:ListTagsForResource",
      "events:ListTargetsByRule",
    ]
  }

  statement {
    sid       = "AllowIAMRead"
    effect    = "Allow"
    resources = ["arn:aws:iam::${local.account_id}:*"]

    actions = [
      "iam:GetOpenIDConnectProvider",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:GetUser",
      "iam:ListAttachedRolePolicies",
      "iam:ListRoles",
      "iam:ListRolePolicies",
      "iam:ListPolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListPolicyVersions",
    ]
  }

  statement {
    sid       = "AllowKMSRead"
    effect    = "Allow"
    resources = ["arn:aws:kms:*:${local.account_id}:*"]

    actions = [
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListAliases",
      "kms:ListResourceTags",
    ]
  }

  statement {
    sid       = "AllowLogsRead"
    effect    = "Allow"
    resources = ["arn:aws:logs:*:${local.account_id}:*"]

    actions = [
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:ListTagsLogGroup",
    ]
  }

  statement {
    sid       = "AllowS3Read"
    effect    = "Allow"
    resources = ["arn:aws:s3:::*"]

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
  }

  statement {
    sid       = "AllowSQSRead"
    effect    = "Allow"
    resources = ["arn:aws:sqs:*:${local.account_id}:*"]

    actions = [
      "sqs:GetQueueAttributes",
      "sqs:ListQueueTags",
    ]
  }

  statement {
    sid       = "AllowSSMRead"
    effect    = "Allow"
    resources = ["arn:aws:ssm:*:${local.account_id}:*"]

    actions = [
      "ssm:GetParameter"
    ]
  }
}


/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

resource "aws_iam_role" "eks_infra_admin" {
  name        = "EKSInfraAdmin"
  description = "IAM role used for planning/applying/destroying infrastructure."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : data.aws_iam_user.eks_infra_admins[*].arn
        },
        "Action" : "sts:AssumeRole",
        "Condition" : {}
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "admin_eks_plan" {
  role       = aws_iam_role.eks_infra_admin.name
  policy_arn = aws_iam_policy.eks_plan.arn
}

resource "aws_iam_role_policy_attachment" "admin_eks_apply" {
  role       = aws_iam_role.eks_infra_admin.name
  policy_arn = aws_iam_policy.eks_apply.arn
}

resource "aws_iam_role_policy_attachment" "admin_eks_destroy" {
  role       = aws_iam_role.eks_infra_admin.name
  policy_arn = aws_iam_policy.eks_destroy.arn
}


/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

resource "aws_iam_role" "eks_viewer" {
  name        = "EKSInfraViewer"
  description = "IAM read role."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : data.aws_iam_user.eks_infra_viewers[*].arn
        },
        "Action" : "sts:AssumeRole",
        "Condition" : {}
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "viewer_eks_plan" {
  role       = aws_iam_role.eks_viewer.name
  policy_arn = aws_iam_policy.eks_plan.arn
}


/*
Copyright 2023 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

variable "eks_infra_admins" {
  type        = list(string)
  description = "List of maintainers that have permissions to run apply/destory."
  default     = []
}

variable "eks_infra_viewers" {
  type        = list(string)
  description = "List of maintainers that have permissions to run plan."
  default     = []
}

variable "tags" {
  type = map(string)
  default = {
    Terraform = true
  }
}