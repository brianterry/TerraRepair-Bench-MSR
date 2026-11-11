data "aws_acm_certificate" "main" {
  count = var.create_acm_certificate ? 0 : 1

  domain = var.domain_name
  statuses = [
    "ISSUED",
  "PENDING_VALIDATION"]
  most_recent = true
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws?ref=ff6d3716d1c24d5b5b39765b089e686e95d9a2d9"
  version = "4.3.2"

  create_certificate = var.create_acm_certificate

  domain_name = local.domain_name
  zone_id     = local.zone_id
  subject_alternative_names = [
  "*.${local.domain_name}"]

  tags = local.tags
}

module "eventbridge" {
  count   = var.aws_cis_benchmark_alerts.enabled ? 1 : 0
  source  = "terraform-aws-modules/eventbridge/aws?ref=0d8e725d0a9a3a8a0a0e4e3e3b6d3c6a3e8d7b1a"
  version = "1.17.3"

  create_bus = false

  rules = {
    secrets_manager_actions = {
      enabled     = var.aws_cis_benchmark_alerts.rules.secrets_manager_actions_enabled
      description = "Capture all Secret Manager events"
      event_pattern = jsonencode(
        {
          "source" : ["aws.secretsmanager"],
          "detail" : {
            "eventSource" : ["secretsmanager.amazonaws.com"],
            "eventName" : ["CreateSecret", "UpdateSecret", "DeleteSecret", "PutSecretValue"]
          }
        }
      )
    },
    parameter_store_actions = {
      enabled     = var.aws_cis_benchmark_alerts.rules.parameter_store_actions_enabled
      description = "Capture all Parameter Store events"
      event_pattern = jsonencode(
        {
          "source" : ["aws.ssm"],
          "detail-type" : ["Parameter Store Change"],
          "detail" : {
            "operation" : ["Create", "Update", "Delete", "LabelParameterVersion"]
          }
        }
      )
    },
    console_login_failed = {
      enabled     = var.aws_cis_benchmark_alerts.rules.console_login_failed_enabled
      description = "Alert on ConsoleLogin failed authentication"
      event_pattern = jsonencode(
        {
          "detail" : {
            "eventName" : ["ConsoleLogin"],
            "errorMessage" : ["Failed authentication"]
          }
        }
      )
    },
    kms_cmk_delete_or_disable = {
      enabled     = var.aws_cis_benchmark_alerts.rules.kms_cmk_delete_or_disable_enabled
      description = "Alert on KMS disable or delete CMK"
      event_pattern = jsonencode(
        {
          "source" : ["aws.kms"],
          "detail-type" : ["AWS API Call via CloudTrail"],
          "detail" : {
            "eventSource" : ["kms.amazonaws.com"],
            "eventName" : [
              "DisableKey",
              "ScheduleKeyDeletion"
            ]
          }
        }
      )
    },
    consolelogin_without_mfa = {
      enabled     = var.aws_cis_benchmark_alerts.rules.console_login_failed_enabled
      description = "Alert on ConsoleLogin without MFA"
      event_pattern = jsonencode(
        {
          "detail-type" : ["AWS Console Sign In via CloudTrail"],
          "detail" : {
            "eventName" : ["ConsoleLogin"],
            "userIdentity" : {
              "type" : ["IAMUser"]
            },
            "additionalEventData" : {
              "MFAUsed" : [{ "anything-but" : "Yes" }]
            },
            "responseElements" : {
              "ConsoleLogin" : ["Success"]
            }
          }
        }
      )
    },
    unauthorized_api_calls = {
      enabled     = var.aws_cis_benchmark_alerts.rules.unauthorized_api_calls_enabled
      description = "Alert on Unauthorized-API-Calls"
      event_pattern = jsonencode(
        {
          "detail-type" : ["AWS API Call via CloudTrail"],
          "errorCode" : ["AccessDenied", "*UnauthorizedOperation"]
        }
      )
    },
    usage_of_root_account = {
      enabled     = var.aws_cis_benchmark_alerts.rules.usage_of_root_account_enabled
      description = "Alert on usage of Root account"
      event_pattern = jsonencode(
        {
          "detail-type" : ["AWS Console Sign In via CloudTrail"],
          "detail" : {
            "userIdentity" : {
              "type" : ["Root"],
              "invokedBy" : [{ "exists" : false }]
            },
            "eventType" : [{ "anything-but" : "AwsServiceEvent" }]
          }
        }
      )
    },
    iam_policy_changes = {
      enabled     = var.aws_cis_benchmark_alerts.rules.iam_policy_changes_enabled
      description = "Alert on changing IAM policy"
      event_pattern = jsonencode(
        {
          "source" : ["aws.iam"],
          "detail-type" : ["AWS API Call via CloudTrail"],
          "detail" : {
            "eventSource" : ["iam.amazonaws.com"],
            "eventName" : [
              "DeleteGroupPolicy",
              "DeleteRolePolicy",
              "DeleteUserPolicy",
              "PutGroupPolicy",
              "PutRolePolicy",
              "PutUserPolicy",
              "CreatePolicy",
              "DeletePolicy",
              "CreatePolicyVersion",
              "DeletePolicyVersion",
              "AttachRolePolicy",
              "DetachRolePolicy",
              "AttachUserPolicy",
              "DetachUserPolicy",
              "AttachGroupPolicy",
              "DetachGroupPolicy"
            ]
          }
        }
      )
    },
    cloudtrail_configuration_changes = {
      enabled     = var.aws_cis_benchmark_alerts.rules.cloudtrail_configuration_changes_enabled
      description = "Alert on changing Cloudtrail configuration"
      event_pattern = jsonencode(
        {
          "source" : ["aws.cloudtrail"],
          "detail-type" : ["AWS API Call via CloudTrail"],
          "detail" : {
            "eventSource" : ["cloudtrail.amazonaws.com"],
            "eventName" : [
              "CreateTrail",
              "UpdateTrail",
              "DeleteTrail",
              "StartLogging",
              "StopLogging"
            ]
          }
        }
      )
    },
    s3_bucket_policy_changes = {
      enabled     = var.aws_cis_benchmark_alerts.rules.s3_bucket_policy_changes_enabled
      description = "Alert on changing s3 bucket policy"
      event_pattern = jsonencode(
        {
          "source" : ["aws.s3"],
          "detail-type" : ["AWS API Call via CloudTrail"],
          "detail" : {
            "eventSource" : ["s3.amazonaws.com"],
            "eventName" : [
              "PutBucketAcl",
              "PutBucketPolicy",
              "PutBucketCors",
              "PutBucketLifecycle",
              "PutBucketReplication",
              "DeleteBucketPolicy",
              "DeleteBucketCors",
              "DeleteBucketLifecycle",
              "DeleteBucketReplication"
            ]
          }
        }
      )
    },
    aws_config_changes = {
      enabled     = var.aws_cis_benchmark_alerts.rules.aws_config_changes_enabled
      description = "Alert on changing AWS Config configuration"
      event_pattern = jsonencode(
        {
          "source" : ["aws.config"],
          "detail-type" : ["AWS API Call via CloudTrail"],
          "detail" : {
            "eventSource" : ["config.amazonaws.com"],
            "eventName" : [
              "StopConfigurationRecorder",
              "DeleteDeliveryChannel",
              "PutDeliveryChannel",
              "PutConfigurationRecorder"
            ]
          }
        }
      )
    },
    security_group_changes = {
      enabled     = var.aws_cis_benchmark_alerts.rules.security_group_changes_enabled
      description = "Alert on changing Security groups"
      event_pattern = jsonencode(
        {
          "source" : ["aws.ec2"],
          "detail-type" : ["AWS API Call via CloudTrail"],
          "detail" : {
            "eventSource" : ["ec2.amazonaws.com"],
            "eventName" : [
              "AuthorizeSecurityGroupIngress",
              "AuthorizeSecurityGroupEgress",
              "RevokeSecurityGroupIngress",
              "RevokeSecurityGroupEgress",
              "CreateSecurityGroup",
              "DeleteSecurityGroup"
            ]
          }
        }
      )
    },
    nacl_changes = {
      enabled     = var.aws_cis_benchmark_alerts.rules.nacl_changes_enabled
      description = "Alert on changing NACL"
      event_pattern = jsonencode(
        {
          "source" : ["aws.ec2"],
          "detail-type" : ["AWS API Call via CloudTrail"],
          "detail" : {
            "eventSource" : ["ec2.amazonaws.com"],
            "eventName" : [
              "CreateNetworkAcl",
              "CreateNetworkAclEntry",
              "DeleteNetworkAcl",
              "DeleteNetworkAclEntry",
              "ReplaceNetworkAclEntry",
              "ReplaceNetworkAclAssociation"
            ]
          }
        }
      )
    },
    network_gateway_changes = {
      enabled     = var.aws_cis_benchmark_alerts.rules.network_gateway_changes_enabled
      description = "Alert on changing Network Gateways"
      event_pattern = jsonencode(
        {
          "source" : ["aws.ec2"],
          "detail-type" : ["AWS API Call via CloudTrail"],
          "detail" : {
            "eventSource" : ["ec2.amazonaws.com"],
            "eventName" : [
              "CreateCustomerGateway",
              "DeleteCustomerGateway",
              "AttachInternetGateway",
              "CreateInternetGateway",
              "DeleteInternetGateway",
              "DetachInternetGateway"
            ]
          }
        }
      )
    },
    route_table_changes = {
      enabled     = var.aws_cis_benchmark_alerts.rules.route_table_changes_enabled
      description = "Alert on changing Route tables"
      event_pattern = jsonencode(
        {
          "source" : ["aws.ec2"],
          "detail-type" : ["AWS API Call via CloudTrail"],
          "detail" : {
            "eventSource" : ["ec2.amazonaws.com"],
            "eventName" : [
              "CreateRoute",
              "CreateRouteTable",
              "ReplaceRoute",
              "ReplaceRouteTableAssociation",
              "DeleteRouteTable",
              "DeleteRoute",
              "DisassociateRouteTable"
            ]
          }
        }
      )
    },
    vpc_changes = {
      enabled     = var.aws_cis_benchmark_alerts.rules.vpc_changes_enabled
      description = "Alert on changing VPC configuration"
      event_pattern = jsonencode(
        {
          "source" : ["aws.ec2"],
          "detail-type" : ["AWS API Call via CloudTrail"],
          "detail" : {
            "eventSource" : ["ec2.amazonaws.com"],
            "eventName" : [
              "CreateVpc",
              "DeleteVpc",
              "ModifyVpcAttribute",
              "AcceptVpcPeeringConnection",
              "CreateVpcPeeringConnection",
              "DeleteVpcPeeringConnection",
              "RejectVpcPeeringConnection",
              "AttachClassicLinkVpc",
              "DetachClassicLinkVpc",
              "DisableVpcClassicLink",
              "EnableVpcClassicLink"
            ]
          }
        }
      )
    },
    organization_changes = {
      enabled     = var.aws_cis_benchmark_alerts.rules.organization_changes_enabled
      description = "Alert on Organization changes"
      event_pattern = jsonencode(
        {
          "source" : ["aws.organizations"],
          "detail-type" : ["AWS API Call via CloudTrail"],
          "detail" : {
            "eventSource" : ["organizations.amazonaws.com"],
            "eventName" : [
              "AcceptHandshake",
              "AttachPolicy",
              "CreateAccount",
              "CreateOrganizationalUnit",
              "CreatePolicy",
              "DeclineHandshake",
              "DeleteOrganization",
              "DeleteOrganizationalUnit",
              "DeletePolicy",
              "DetachPolicy",
              "DisablePolicyType",
              "EnablePolicyType",
              "InviteAccountToOrganization",
              "LeaveOrganization",
              "MoveAccount",
              "RemoveAccountFromOrganization",
              "UpdatePolicy",
              "UpdateOrganizationalUnit"
            ]
          }
        }
      )
    },
  }

  targets = {
    secrets_manager_actions = [
      {
        name = "secrets-manager-actions-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ],
    parameter_store_actions = [
      {
        name = "parameter-store-actions-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ],
    console_login_failed = [
      {
        name = "console-login-failed-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ],
    kms_cmk_delete_or_disable = [
      {
        name = "kms-cmk-delete-or-disable-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ]
    consolelogin_without_mfa = [
      {
        name = "consolelogin-without-mfa-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ],
    unauthorized_api_calls = [
      {
        name = "unauthorized-api-calls-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ],
    usage_of_root_account = [
      {
        name = "usage-of-root-account-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ],
    iam_policy_changes = [
      {
        name = "iam-policy-changes-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ],
    cloudtrail_configuration_changes = [
      {
        name = "cloudtrail-configuration-changes-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ],
    s3_bucket_policy_changes = [
      {
        name = "s3-bucket-policy-changes-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ],
    aws_config_changes = [
      {
        name = "aws-config-changes-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ],
    security_group_changes = [
      {
        name = "security-group-changes-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ],
    nacl_changes = [
      {
        name = "nacl-changes-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ],
    network_gateway_changes = [
      {
        name = "network-gateway-changes-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ],
    route_table_changes = [
      {
        name = "route-table-changes-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ],
    vpc_changes = [
      {
        name = "vpc-changes-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ],
    organization_changes = [
      {
        name = "organization-changes-notify-via-sns"
        arn  = aws_sns_topic.security_alerts[count.index].arn
      }
    ]
  }

  tags = local.tags
}

resource "aws_sns_topic" "security_alerts" {
  count = var.aws_cis_benchmark_alerts.enabled ? 1 : 0

  name = "${local.name}-security-alerts"

  tags = local.tags
}

resource "aws_sns_topic_subscription" "security_alerts" {
  count = var.aws_cis_benchmark_alerts.enabled ? 1 : 0

  topic_arn = aws_sns_topic.security_alerts[count.index].arn
  protocol  = "email"
  endpoint  = var.aws_cis_benchmark_alerts.email
}

resource "aws_sns_topic_policy" "security_alerts" {
  count = var.aws_cis_benchmark_alerts.enabled ? 1 : 0

  arn = aws_sns_topic.security_alerts[count.index].arn
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "Allow_Publish_Events",
        "Effect" : "Allow",
        "Principal" : { "Service" : "events.amazonaws.com" },
        "Action" : "sns:Publish",
        "Resource" : [
          aws_sns_topic.security_alerts[count.index].arn
        ]
      },
      {
        "Sid" : "__default_statement_ID",
        "Effect" : "Allow",
        "Principal" : { "AWS" : "*" },
        "Action" : [
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:AddPermission",
          "sns:RemovePermission",
          "sns:DeleteTopic",
          "sns:Subscribe",
          "sns:ListSubscriptionsByTopic",
          "sns:Publish",
          "sns:Receive"
        ]
        "Resource" : [
          aws_sns_topic.security_alerts[count.index].arn
        ]
        "Condition" : {
          "StringEquals" : {
            "AWS:SourceOwner" : data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = local.name
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  enable_log_file_validation    = true
  enable_logging                = true
  is_multi_region_trail         = true
  kms_key_id                    = aws_kms_key.cloudtrail.arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_cloudwatch.arn
  sns_topic_name                = aws_sns_topic.security_alerts[0].name

  tags = local.tags

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "${local.name}-aws-cloudtrail-logs"

  tags = local.tags
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "remove_old_files"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 2
    }
    expiration {
      days = var.cloudtrail_logs_s3_expiration_days
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  restrict_public_buckets = true
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Sid" : "AWSCloudTrailAclCheck",
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "cloudtrail.amazonaws.com"
          },
          "Action" : "s3:GetBucketAcl",
          "Resource" : aws_s3_bucket.cloudtrail.arn
        },
        {
          "Sid" : "AWSCloudTrailWrite",
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "cloudtrail.amazonaws.com"
          },
          "Action" : "s3:PutObject",
          "Resource" : "${aws_s3_bucket.cloudtrail.arn}/*",
          "Condition" : {
            "StringEquals" : {
              "s3:x-amz-acl" : "bucket-owner-full-control"
            }
          }
        }
      ]
  })
}

locals {
  eks_map_roles = [
    {
      rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/administrator"
      username = "administrator"
      groups   = ["system:masters"]
    }
  ]
}

data "aws_ami" "eks_default_arm64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-arm64-node-${var.eks_cluster_version}-v*"]

  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws?ref=5b9a5b1e9c4a4a3a3a3a3a3a3a3a3a3a3a3a3a3"
  version = "19.12.0"

  cluster_name              = local.name
  cluster_version           = var.eks_cluster_version
  subnet_ids                = module.vpc.private_subnets
  control_plane_subnet_ids  = module.vpc.intra_subnets
  enable_irsa               = true
  manage_aws_auth_configmap = true
  create_aws_auth_configmap = false
  aws_auth_roles            = local.eks_map_roles
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent              = true
      service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.aws_ebs_csi_driver.iam_role_arn
    }
  }

  cluster_enabled_log_types              = var.eks_cluster_enabled_log_types
  cloudwatch_log_group_retention_in_days = var.eks_cloudwatch_log_group_retention_in_days

  vpc_id = module.vpc.vpc_id

  cluster_endpoint_public_access       = var.eks_cluster_endpoint_public_access
  cluster_endpoint_private_access      = var.eks_cluster_endpoint_private_access
  cluster_endpoint_public_access_cidrs = var.eks_cluster_endpoint_only_pritunl ? ["${module.pritunl[0].pritunl_endpoint}/32"] : ["0.0.0.0/0"]

  node_security_group_tags = { "karpenter.sh/discovery" = local.name }

  self_managed_node_group_defaults = {
    ami_id = data.aws_ami.eks_default_arm64.id
    block_device_mappings = {
      xvda = {
        device_name = "/dev/xvda"
        ebs = {
          delete_on_termination = true
          encrypted             = false
          volume_size           = 100
          volume_type           = "gp3"
        }

      }
    }
    metadata_options = {
      http_endpoint               = "enabled"
      http_tokens                 = "required"
      http_put_response_hop_limit = 1
      instance_metadata_tags      = "disabled"
    }
    iam_role_attach_cni_policy = false
  }
  self_managed_node_groups = {
    default = {
      name          = "${local.name}-default"
      iam_role_name = "${local.name}-default"
      desired_size  = var.node_group_default.desired_capacity
      max_size      = var.node_group_default.max_capacity
      min_size      = var.node_group_default.min_capacity
      subnet_ids    = module.vpc.private_subnets

      bootstrap_extra_args       = "--kubelet-extra-args '--node-labels=nodegroup=default --register-with-taints=CriticalAddonsOnly=true:NoSchedule'"
      capacity_rebalance         = var.node_group_default.capacity_rebalance
      use_mixed_instances_policy = var.node_group_default.use_mixed_instances_policy
      mixed_instances_policy     = var.node_group_default.mixed_instances_policy
    }
  }
  fargate_profiles = {
    default = {
      name = "fargate"

      selectors = [
        {
          namespace = "fargate"
        }
      ]

      subnets = module.vpc.private_subnets

      tags = merge(local.tags, {
        Namespace = "fargate"
      })
    }
  }

  tags = { "ClusterName" = local.name }
}

module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks?ref=5b9a5b1e9c4a4a3a3a3a3a3a3a3a3a3a3a3a3a"
  version = "5.17.0"

  role_name             = "${local.name}-vpc-cni"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = local.tags
}

module "aws_ebs_csi_driver" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks?ref=5b9a5b1e9c4a4a3a3a3a3a3a3a3a3a3a3a3a3a"
  version = "5.17.0"

  role_name             = "${local.name}-aws-ebs-csi-driver"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

module "pritunl" {
  count = var.pritunl_vpn_server_enable ? 1 : 0

  source          = "../modules/aws-pritunl"
  environment     = local.env
  vpc_id          = module.vpc.vpc_id
  public_subnets  = module.vpc.public_subnets
  private_subnets = module.vpc.private_subnets
  ingress_with_cidr_blocks = [
    {
      protocol    = "6"
      from_port   = 443
      to_port     = 443
      cidr_blocks = var.pritunl_vpn_access_cidr_blocks
    },
    {
      protocol    = "17"
      from_port   = 19739
      to_port     = 19739
      cidr_blocks = "0.0.0.0/0"
    },
    {
      protocol    = "6"
      from_port   = 80
      to_port     = 80
      cidr_blocks = var.pritunl_vpn_access_cidr_blocks
    },
  ]
}

data "aws_route53_zone" "main" {
  count = var.create_r53_zone && var.zone_id == null ? 0 : 1

  name         = "${var.domain_name}."
  private_zone = false
}

module "r53_zone" {
  source  = "terraform-aws-modules/route53/aws//modules/zones?ref=5b9a5b1e9c4a4a3a3a3a3a3a3a3a3a3a3a3a3a"
  version = "2.10.2"

  create = var.create_r53_zone

  zones = {
    (var.domain_name) = {
      comment = var.domain_name
      tags    = local.tags
    }
  }
}

locals {
  cidr_subnets     = [for cidr_block in cidrsubnets(var.cidr, 2, 2, 2, 2) : cidrsubnets(cidr_block, 4, 4, 4, 4)]
  private_subnets  = chunklist(local.cidr_subnets[0], var.az_count)[0]
  public_subnets   = chunklist(local.cidr_subnets[1], var.az_count)[0]
  database_subnets = chunklist(local.cidr_subnets[2], var.az_count)[0]
  intra_subnets    = chunklist(local.cidr_subnets[3], var.az_count)[0]
  azs              = data.aws_availability_zones.available.names
}

data "aws_security_group" "default" {
  name   = "default"
  vpc_id = module.vpc.vpc_id
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws?ref=5b9a5b1e9c4a4a3a3a3a3a3a3a3a3a3a3a3a3a"
  version = "4.0.1"

  name = local.name
  cidr = var.cidr

  azs              = local.azs
  private_subnets  = local.private_subnets
  public_subnets   = local.public_subnets
  database_subnets = local.database_subnets
  intra_subnets    = local.intra_subnets

  single_nat_gateway      = var.single_nat_gateway
  enable_nat_gateway      = true
  enable_vpn_gateway      = false
  enable_dns_hostnames    = true
  enable_dns_support      = true
  map_public_ip_on_launch = true

  create_database_subnet_group = false

  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  tags = merge(local.tags, {
    "kubernetes.io/cluster/${local.name}" = "shared"
  })

  private_subnet_tags = {
    Name                              = "${local.name}-private"
    destination                       = "private"
    "karpenter.sh/discovery"          = "private"
    "kubernetes.io/role/internal-elb" = "1"
  }

  private_route_table_tags = {
    Name        = "${local.name}-private"
    destination = "private"
  }

  public_subnet_tags = {
    Name                     = "${local.name}-public"
    destination              = "public"
    "karpenter.sh/discovery" = "public"
    "kubernetes.io/role/elb" = "1"
  }

  public_route_table_tags = {
    Name        = "${local.name}-public"
    destination = "public"
  }

  database_subnet_tags = {
    Name        = "${local.name}-database"
    destination = "database"
  }

  database_route_table_tags = {
    Name        = "${local.name}-database"
    destination = "database"
  }

  intra_subnet_tags = {
    Name        = "${local.name}-intra"
    destination = "intra"
  }

  intra_route_table_tags = {
    Name        = "${local.name}-intra"
    destination = "intra"
  }
}

module "vpc_gateway_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints?ref=5b9a5b1e9c4a4a3a3a3a3a3a3a3a3a3a3a3a3a"
  version = "4.0.1"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service      = "s3"
      service_type = "Gateway"
      route_table_ids = flatten([
        module.vpc.intra_route_table_ids,
        module.vpc.private_route_table_ids,
        module.vpc.public_route_table_ids
      ])
      tags = {
        Name = "${local.name}-s3"
      }
    }
  }

  tags = local.tags
}

locals {
  env            = terraform.workspace == "default" ? var.environment : terraform.workspace
  short_region   = var.short_region[var.region]
  name           = "${var.name}-${local.env}-${local.short_region}"
  name_wo_region = "${var.name}-${local.env}"
  domain_name    = var.domain_name
  account_id     = data.aws_caller_identity.current.account_id

  tags = {
    Name        = local.name
    Environment = local.env
  }

  ssl_certificate_arn = var.create_acm_certificate ? module.acm.acm_certificate_arn : data.aws_acm_certificate.main[0].arn

  zone_id = var.create_r53_zone ? values(module.r53_zone.route53_zone_zone_id)[0] : (var.zone_id != null ? var.zone_id : data.aws_route53_zone.main[0].zone_id)
}

terraform {
  required_version = "1.4.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.19.0"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

resource "aws_ebs_encryption_by_default" "default" {
  enabled = true
}

resource "aws_iam_account_password_policy" "default" {
  count = var.aws_account_password_policy.create ? 1 : 0

  minimum_password_length        = var.aws_account_password_policy.minimum_password_length
  password_reuse_prevention      = 24
  require_lowercase_characters   = var.aws_account_password_policy.require_lowercase_characters
  require_numbers                = var.aws_account_password_policy.require_numbers
  require_uppercase_characters   = var.aws_account_password_policy.require_uppercase_characters
  require_symbols                = var.aws_account_password_policy.require_symbols
  allow_users_to_change_password = var.aws_account_password_policy.allow_users_to_change_password
  max_password_age               = var.aws_account_password_policy.max_password_age
}

module "aws_cost_allocation_tags" {
  count = var.is_this_payment_account ? 1 : 0

  source = "../modules/aws-cost-allocation-tags"
  tags = [
    {
      tag_key = "Environment"
      status  = "Active"
    },
    {
      tag_key = "Terraform"
      status  = "Active"
    },
    {
      tag_key = "aws:autoscaling:groupName"
      status  = "Active"
    }
  ]
}

output "name" {
  value       = local.name
}

output "name_wo_region" {
  value       = local.name_wo_region
}

output "domain_name" {
  value       = var.domain_name
}

output "env" {
  value       = local.env
}

output "route53_zone_id" {
  value       = local.zone_id
}

output "region" {
  value       = var.region
}

output "short_region" {
  value       = local.short_region
}

output "az_count" {
  value       = var.az_count
}

output "allowed_ips" {
  value       = var.allowed_ips
}

output "vpc_name" {
  value       = module.vpc.name
}

output "vpc_id" {
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  value       = var.cidr
}

output "vpc_public_subnets" {
  value       = module.vpc.public_subnets
}

output "vpc_private_subnets" {
  value       = module.vpc.private_subnets
}

output "vpc_database_subnets" {
  value       = module.vpc.database_subnets
}

output "vpc_intra_subnets" {
  value       = module.vpc.intra_subnets
}

output "eks_cluster_endpoint" {
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_security_group_id" {
  value       = module.eks.cluster_security_group_id
}

output "eks_kubectl_console_config" {
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
  depends_on  = []
}

output "eks_cluster_id" {
  value = module.eks.cluster_name
}

output "eks_oidc_provider_arn" {
  value       = module.eks.oidc_provider_arn
}

output "ssl_certificate_arn" {
  value       = local.ssl_certificate_arn
}

output "node_group_default_iam_role_arn" {
  value = module.eks.self_managed_node_groups["default"].iam_role_arn
}

output "node_group_default_iam_role_name" {
  value = module.eks.self_managed_node_groups["default"].iam_role_name
}

provider "aws" {
  region              = var.region
  allowed_account_ids = var.allowed_account_ids
  default_tags {
    tags = {
      Name        = local.name
      Environment = local.env
      Terraform   = "true"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.main.token
}

data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_name
}

variable "allowed_account_ids" {
  default     = []
}

variable "aws_account_password_policy" {
  type = any
  default = {
    create                         = true
    minimum_password_length        = 14
    password_reuse_prevention      = 24
    require_lowercase_characters   = true
    require_numbers                = true
    require_uppercase_characters   = true
    require_symbols                = true
    allow_users_to_change_password = true
    max_password_age               = 90
  }
}

variable "is_this_payment_account" {
  default     = true
}

variable "name" {
}

variable "environment" {
  default     = "demo"
}

variable "short_region" {
  default = {
    us-east-1      = "use1"
    us-east-2      = "use2"
    us-west-1      = "usw1"
    us-west-2      = "usw2"
    ap-east-1      = "ape1"
    ap-south-1     = "aps1"
    ap-northeast-2 = "apn2"
    ap-northeast-1 = "apn1"
    ap-southeast-1 = "apse1"
    ap-southeast-2 = "apse2"
    ca-central-1   = "cac1"
    cn-north-1     = "cnn1"
    cn-northwest-1 = "cnnw1"
    eu-central-1   = "euc1"
    eu-west-1      = "euw1"
    eu-west-2      = "euw2"
    eu-west-3      = "euw3"
    eu-north-1     = "eun1"
    sa-east-1      = "sae1"
    us-gov-east-1  = "usge1"
    us-gov-west-1  = "usgw1"
  }
}

variable "domain_name" {
}

variable "zone_id" {
  default     = null
}

variable "create_r53_zone" {
  default     = false
}

variable "create_acm_certificate" {
  default     = false
}

variable "region" {
  default     = "us-east-1"
}

variable "az_count" {
  default     = 3
}

variable "cidr" {
  default     = "10.0.0.0/16"
}

variable "allowed_ips" {
  default     = []
}

variable "single_nat_gateway" {
  default     = true
}

variable "eks_cluster_version" {
  default     = "1.25"
}

variable "node_group_default" {
  type = object({
    instance_type              = string
    max_capacity               = number
    min_capacity               = number
    desired_capacity           = number
    capacity_rebalance         = bool
    use_mixed_instances_policy = bool
    mixed_instances_policy     = any
  })

  default = {
    instance_type              = "t4g.medium"
    max_capacity               = 3
    min_capacity               = 2
    desired_capacity           = 2
    capacity_rebalance         = true
    use_mixed_instances_policy = true
    mixed_instances_policy = {
      instances_distribution = {
        on_demand_base_capacity                  = 0
        on_demand_percentage_above_base_capacity = 0
      }

      override = [
        { instance_type = "t4g.small" },
        { instance_type = "t4g.medium" }
      ]
    }
  }
}

variable "eks_map_roles" {
  default = []
}

variable "eks_cluster_enabled_log_types" {
  default     = ["audit"]
}

variable "eks_cloudwatch_log_group_retention_in_days" {
  default     = 90
}

variable "eks_cluster_encryption_config_enable" {
  default     = false
}

variable "eks_cluster_endpoint_public_access" {
  default     = true
}

variable "eks_cluster_endpoint_private_access" {
  default     = false
}

variable "pritunl_vpn_server_enable" {
  default     = false
}

variable "eks_cluster_endpoint_only_pritunl" {
  default     = false
}

variable "pritunl_vpn_access_cidr_blocks" {
  default     = "127.0.0.1/32"
}

variable "aws_cis_benchmark_alerts" {
  type = any
  default = {
    "enabled" = "false"
    "email"   = "demo@example.com"
    "rules" = {
      "secrets_manager_actions_enabled"          = true
      "parameter_store_actions_enabled"          = true
      "console_login_failed_enabled"             = true
      "kms_cmk_delete_or_disable_enabled"        = true
      "consolelogin_without_mfa_enabled"         = true
      "unauthorized_api_calls_enabled"           = true
      "usage_of_root_account_enabled"            = true
      "iam_policy_changes_enabled"               = true
      "cloudtrail_configuration_changes_enabled" = true
      "s3_bucket_policy_changes_enabled"         = true
      "aws_config_changes_enabled"               = true
      "security_group_changes_enabled"           = true
      "nacl_changes_enabled"                     = true
      "network_gateway_changes_enabled"          = true
      "route_table_changes_enabled"              = true
      "vpc_changes_enabled"                      = true
      "organization_changes_enabled"             = true
    }
  }
}

variable "cloudtrail_logs_s3_expiration_days" {
  default     = 180
}

resource "aws_kms_key" "cloudtrail" {
  description             = "KMS key for CloudTrail encryption"
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.cloudtrail_kms_policy.json
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name = "cloudtrail-log-group"
}

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "cloudtrail-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudtrail_cloudwatch" {
  role       = aws_iam_role.cloudtrail_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 encryption"
  enable_key_rotation     = true
}

resource "aws_s3_bucket_logging" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  target_bucket = aws_s3_bucket.cloudtrail.id
  target_prefix = "logs/"
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_replication_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  role   = aws_iam_role.replication.arn

  rule {
    status = "Enabled"
    destination {
      bucket        = "arn:aws:s3:::destination-bucket"
      storage_class = "STANDARD"
    }
  }
}

resource "aws_iam_role" "replication" {
  name = "s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "replication" {
  role       = aws_iam_role.replication.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}