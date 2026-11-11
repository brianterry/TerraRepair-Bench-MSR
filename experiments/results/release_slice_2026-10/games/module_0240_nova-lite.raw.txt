```hcl
# azure.noms.root and azure.hmpp.root AD DS infra migrated from Azure FixNGo
# For more details why this is here, please see: 
# - https://github.com/ministryofjustice/modernisation-platform/issues/5970
# - https://dsdmoj.atlassian.net/wiki/x/3oCKGAE
# Managed by DSO team, slack: #ask-digital-studio-ops 

# NOTE: remember to remove ad-fixngo-ec2-access from
# terraform/environments/bootstrap/single-sign-on/policies.tf when this is no longer required
# and firewall rules from terraform/environments/core-network-services

module "ad_fixngo_ip_addresses" {
  source = "github.com/ministryofjustice/modernisation-platform-environments//terraform/modules/ip_addresses?ref=27807807552fb132593000ea0084500ac5d39376"
}

locals {

  ad_fixngo = {

    aws_key_pairs = {
      # See https://dsdmoj.atlassian.net/wiki/x/3oCKGAE
      ad-fixngo-ec2-live    = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC4XM7YBLA/DY3w4oMS4PEYyfYLcK2OuidwRRUKTFyS3lnzoucuPg4fuv3yMbLJxxoUT8QjfHDWUzQRsQorkj6ig8TB68rAz0/BBx3wuA76dNoDXAXSM/sOP1ZA1gXL3BR21hbe8QIvmqP881BLgKvB5WGN7iSPIepNtxea8g6/Eg91ISLnDvVKkqjej+wJbeBKcnGCdv6LJ082HZRMxIBfAuN9snoNyjymXYU/nMeXgwZhfSzLHU9KYOAzuYxOHgVz0k1NOPYCJflSqcYyqNbuvmLmUJVSb3u/8kpOwcTR9UP0awIzuH7PXZf87g1wyfesyAkNPMa4uUoEMIIah2tp+rAp9AUDnzn5MIv84lSkerqp2+0L/dLf+FCjNpIUePpmJiC8JCqD7oemwvrEuPpsvFalmRuRNlg2s+DKg7FVdhUWH7HiIKoiSB7dBtb02AjeY5Hi8c9urFBas4LmtngEbH8mf65VZTA82S2mLjOw8DdGRGPTc/o4MilYqR7cqDcNIw3+eEw1PqYkJUykJP5saKjLZuUxe6U0dog1iY9pimPdRKiYouF95tt43+b7/7zVTajq096r/BY2XkklVmbQ/a1HBO/Q/cfQWxhaaIaQwwnAwGQdMtEZsXaJ0OR650NJYeqtKh9ZKeMF/M+HLddiC7+1ncu78NFLlB98zD8cTw=="
      ad-fixngo-ec2-nonlive = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDZ7Q515wcJIdw68vUuf2v0BFow0GmqFjapC7qJ+x6eiFqfP3Cq7jT/HYS51nzJgiXUUvyXPhQcKJgQ1O0VlTX/AjctUdm9YUbArI+S74BgNFLLbDd9EsMxhm6SKjYqbhrL9S4YxA6C0hgz4+NiEJk8XKEg5laHrOCt7kmtRE8FDvyzTLZLQ7HomHkd43tDLtvTKzKkeV2iOlnYG+l0XAFLC58ufOS3ujtK9jD2vZwyarfLTiyyE/gXTtFpb+ktUnwvJpgNXDdaGHVOOjAdJh7jEmqtl438aXxfDoroX7BQmn+8nrY0lkSY+eUis58exHDqWWtUsSyHqaSUeKvyJvC0dnCUQEVulsCljFVRWeof+xcCpeHGrS4tfDop5Kckoadpwa0LILiun8NeQTLTt8jnPAU3auZZTb4u+vQeWYsE0DSWMsTMEoAh+pKBSfnAFZNYgIIp0jQKJJwL8ndTC/XPm0Wu3eorwFGnMgyNVZbkOA6yjtaknUqNVDb/9MOINZYi12NJSguLJg0tN04F0W4X6nCm2v5I72Uv5BLX/c0YpgKjHMCZdSzjS+EWD2a/WRtSUqSmg/ObHimOinPGhdM3JoIlXXUTXHCLkPADLYJ+b8e2sdEqhHFuGvLgXe302ZYftTqfZANMngkrd9tTM3uIoCxRCibicB/jJJ1u8YBqJQ=="
    }

    aws_instances = {

      # NOTE: Fixed IPs for IP allow listing and to avoid AD DNS updates
      # NOTE: Naming convention (for tags.Name and EC2 hostname)
      # ad           = active directory
      # azure/hmpp   = netbios domain name
      # dc           = domain controller
      # rdlic        = remote desktop licensing server
      # a/b/c suffix = availability zone

      ad-hmpp-dc-a = {
        ami_name                  = "hmpps_windows_server_2022_release_2024-02-02T00-00-04.569Z"
        availability_zone         = "eu-west-2a"
        iam_instance_profile_role = "ad-fixngo-ec2-live-role"
        instance_type             = "t3.large"
        key_name                  = "ad-fixngo-ec2-live"
        private_ip                = module.ad_fixngo_ip_addresses.mp_ip["ad-hmpp-dc-a"]
        subnet_id                 = aws_subnet.live-data-additional["eu-west-2a"].id
        vpc_security_group_name   = "ad_hmpp_dc_sg"
        tags = {
          server-type   = "DomainController"
          domain-name   = "azure.hmpp.root"
          description   = "domain controller for FixNGo azure.hmpp.root domain"
          os-type       = "Windows"
          patch-manager = "second-thurs"
        }
      }
      ad-hmpp-dc-b = {
        ami_name                  = "hmpps_windows_server_2022_release_2024-02-02T00-00-04.569Z"
        availability_zone         = "eu-west-2b"
        iam_instance_profile_role = "ad-fixngo-ec2-live-role"
        instance_type             = "t3.large"
        key_name                  = "ad-fixngo-ec2-live"
        private_ip                = module.ad_fixngo_ip_addresses.mp_ip["ad-hmpp-dc-b"]
        subnet_id                 = aws_subnet.live-data-additional["eu-west-2b"].id
        vpc_security_group_name   = "ad_hmpp_dc_sg"
        tags = {
          server-type   = "DomainController"
          domain-name   = "azure.hmpp.root"
          description   = "domain controller for FixNGo azure.hmpp.root domain"
          os-type       = "Windows"
          patch-manager = "forth-thurs"
        }
      }
      ad-hmpp-rdlic = {
        ami_name                  = "hmpps_windows_server_2022_release_2024-08-02T00-00-40.717Z"
        availability_zone         = "eu-west-2c"
        iam_instance_profile_role = "ad-fixngo-ec2-live-role"
        instance_type             = "t3.medium"
        key_name                  = "ad-fixngo-ec2-live"
        private_ip                = module.ad_fixngo_ip_addresses.mp_ip["ad-hmpp-rdlic"]
        subnet_id                 = aws_subnet.live-data-additional["eu-west-2c"].id
        vpc_security_group_name   = "ad_hmpp_rdlic_sg"
        tags = {
          server-type   = "RDLicensing"
          domain-name   = "azure.hmpp.root"
          description   = "remote desktop licensing server for FixNGo azure.hmpp.root domain"
          os-type       = "Windows"
          patch-manager = "forth-thurs"
        }
      }

      ad-azure-dc-a = {
        ami_name                  = "hmpps_windows_server_2022_release_2024-02-02T00-00-04.569Z"
        availability_zone         = "eu-west-2a"
        iam_instance_profile_role = "ad-fixngo-ec2-nonlive-role"
        instance_type             = "t3.large"
        key_name                  = "ad-fixngo-ec2-nonlive"
        private_ip                = module.ad_fixngo_ip_addresses.mp_ip["ad-azure-dc-a"]
        subnet_id                 = module.vpc["non_live_data"].non_tgw_subnet_ids_map.private[0]
        vpc_security_group_name   = "ad_azure_dc_sg"
        tags = {
          server-type   = "DomainController"
          domain-name   = "azure.noms.root"
          description   = "domain controller for FixNGo azure.noms.root domain"
          os-type       = "Windows"
          patch-manager = "second-thurs"
        }
      }
      ad-azure-dc-b = {
        ami_name                  = "hmpps_windows_server_2022_release_2024-02-02T00-00-04.569Z"
        availability_zone         = "eu-west-2b"
        iam_instance_profile_role = "ad-fixngo-ec2-nonlive-role"
        instance_type             = "t3.large"
        key_name                  = "ad-fixngo-ec2-nonlive"
        private_ip                = module.ad_fixngo_ip_addresses.mp_ip["ad-azure-dc-b"]
        subnet_id                 = module.vpc["non_live_data"].non_tgw_subnet_ids_map.private[1]
        vpc_security_group_name   = "ad_azure_dc_sg"
        tags = {
          server-type   = "DomainController"
          domain-name   = "azure.noms.root"
          description   = "domain controller for FixNGo azure.noms.root domain"
          os-type       = "Windows"
          patch-manager = "forth-thurs"
        }
      }
      ad-azure-rdlic = {
        ami_name                  = "hmpps_windows_server_2022_release_2024-08-02T00-00-40.717Z"
        availability_zone         = "eu-west-2c"
        iam_instance_profile_role = "ad-fixngo-ec2-nonlive-role"
        instance_type             = "t3.medium"
        key_name                  = "ad-fixngo-ec2-nonlive"
        private_ip                = module.ad_fixngo_ip_addresses.mp_ip["ad-azure-rdlic"]
        subnet_id                 = module.vpc["non_live_data"].non_tgw_subnet_ids_map.private[2]
        vpc_security_group_name   = "ad_azure_rdlic_sg"
        tags = {
          server-type   = "RDLicensing"
          domain-name   = "azure.noms.root"
          description   = "remote desktop licensing server for FixNGo azure.noms.root domain"
          os-type       = "Windows"
          patch-manager = "second-thurs"
        }
      }
    }

    cloudwatch_log_groups = {
      cwagent-windows-system = {
        retention_in_days = 400
      }
      cwagent-windows-application = {
        retention_in_days = 400
      }
      cwagent-windows-security = {
        retention_in_days = 400
      }
    }

    ec2_iam_roles = {
      # NOTE: roles will be granted access to relevant domain secrets in hmpps-domain-services accounts
      ad-fixngo-ec2-nonlive-role = {
        description = "AD FixNGo EC2 instance role for SSM, VSS snapshots and accessing non-live Secrets"
        assume_role_policy = jsonencode({
          "Version" : "2012-10-17",
          "Statement" : [{
            "Effect" : "Allow",
            "Principal" : {
              "Service" : "ec2.amazonaws.com"
            }
            "Action" : "sts:AssumeRole",
            "Condition" : {}
          }]
        })
        managed_policy_arns = [
          "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
          "arn:aws:iam::aws:policy/AWSEC2VssSnapshotPolicy",
          "ad-fixngo-ec2-policy",
          "ad-fixngo-nonlive-secrets-policy",
        ]
      }
      ad-fixngo-ec2-live-role = {
        description = "AD FixNGo EC2 instance role for SSM, VSS snapshots and accessing live Secrets"
        assume_role_policy = jsonencode({
          "Version" : "2012-10-17",
          "Statement" : [{
            "Effect" : "Allow",
            "Principal" : {
              "Service" : "ec2.amazonaws.com"
            }
            "Action" : "sts:AssumeRole",
            "Condition" : {
              "ForAnyValue:StringLike" : {
                "aws:PrincipalOrgPaths" : ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
              }
            }
          }]
        })
        managed_policy_arns = [
          "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
          "arn:aws:iam::aws:policy/AWSEC2VssSnapshotPolicy",
          "ad-fixngo-ec2-policy",
          "ad-fixngo-live-secrets-policy",
        ]
      }
      ad-fixngo-ec2-access = {
        description = "AD FixNGo role for FleetManager EC2 console access"
        assume_role_policy = jsonencode({
          "Version" : "2012-10-17",
          "Statement" : [{
            "Effect" : "Allow",
            "Principal" : {
              "AWS" : "*"
            },
            "Action" : "sts:AssumeRole",
            "Condition" : {
              "ForAnyValue:StringLike" : {
                "aws:PrincipalOrgPaths" : ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"]
              }
            }
          }]
        })
        managed_policy_arns = [
          "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess",
          "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess",
          "ad-fixngo-fleetmanager-access-policy",
        ]
      }
    }
    ec2_iam_policies = {
      ad-fixngo-ec2-policy = {
        description = "Policy used by AD FixNGo EC2 instance roles"
        path        = "/"
        statements = [
          {
            sid    = "BusinessUnitKmsCmk"
            effect = "Allow"
            actions = [
              "kms:Encrypt",
              "kms:Decrypt",
              "kms:ReEncrypt*",
              "kms:GenerateDataKey*",
              "kms:DescribeKey",
              "kms:CreateGrant",
              "kms:ListGrants",
              "kms:RevokeGrant"
            ]
            resources = [
              module.kms["hmpps"].key_arns["ebs"],
              module.kms["hmpps"].key_arns["general"],
            ]
          },
          {
            sid    = "Ec2SelfProvision"
            effect = "Allow"
            actions = [
              "ec2:DescribeVolumes",
              "ec2:DescribeTags",
              "ec2:DescribeInstances",
              "cloudwatch:PutMetricData",
              "logs:DescribeLogGroups"
            ]
            resources = ["*"]
          },
          {
            sid    = "CloudWatchAgentLogGroupAccess"
            effect = "Allow"
            actions = [
              "logs:PutLogEvents",
              "logs:CreateLogStream",
              "logs:DescribeLogStreams"
            ]
            resources = [
              "arn:aws:logs:*:*:log-group:cwagent-windows-*:*"
            ]
          }
        ]
      }
      ad-fixngo-nonlive-secrets-policy = {
        description = "Policy used by AD FixNGo EC2 instance roles to access azure.noms.root secrets"
        path        = "/"
        statements = [
          {
            sid    = "HmppsDomainSecretsDevTest"
            effect = "Allow"
            actions = [
              "secretsmanager:GetSecretValue",
            ]
            resources = [
              "arn:aws:secretsmanager:*:${local.environment_management.account_ids.hmpps-domain-services-test}:secret:/microsoft/AD/*/shared-*",
            ]
          },
        ]
      }
      ad-fixngo-live-secrets-policy = {
        description = "Policy used by AD FixNGo EC2 instance roles to access azure.hmpp.root secrets"
        path        = "/"
        statements = [
          {
            sid    = "HmppsDomainSecretsProd"
            effect = "Allow"
            actions = [
              "secretsmanager:GetSecretValue",
            ]
            resources = [
              "arn:aws:secretsmanager:*:${local.environment_management.account_ids.hmpps-domain-services-production}:secret:/microsoft/AD/*/shared-*",
            ]
          },
        ]
      }
      ad-fixngo-fleetmanager-access-policy = {
        description = "Policy to allow FleetManager access via console",
        path        = "/",
        statements = [
          {
            sid    = "EC2",
            effect = "Allow",
            actions = [
              "ec2:GetPasswordData",
              "ec2:StartInstances",
              "ec2:StopInstances"
            ],
            resources = ["*"]
          },
          {
            sid    = "SSMStartSession",
            effect = "Allow",
            actions = [
              "ssm:StartSession",
              "ssm:DescribeInstanceInformation",
              "ssm:GetConnectionStatus",
              "ssm:DescribeSessions",
              "ssm:TerminateSession"
            ],
            resources = [
              "arn:aws:ec2:*:*:instance/*",
              "arn:aws:ssm:*:*:document/AWS-StartPortForwardingSession",
              "arn:aws:ssm:*:*:document/SSM-SessionManagerRunShell"
            ]
          },
          {
            sid    = "SSMPermissions",
            effect = "Allow",
            actions = [
              "ssm:ListCommands",
              "ssm:ListCommandInvocations",
              "ssm:GetCommandInvocation",
              "ssm:DescribeInstanceInformation",
              "ssm:SendCommand"
            ],
            resources = ["*"]
          },
          {
            sid    = "GuiConnect",
            effect = "Allow",
            actions = [
              "ssm-guiconnect:CancelConnection",
              "ssm-guiconnect:GetConnection",
              "ssm-guiconnect:StartConnection"
            ],
            resources = ["*"]
          },
          {
            sid    = "ComputeOptimizer",
            effect = "Allow",
            actions = [
              "compute-optimizer:GetEnrollmentStatus",
              "compute-optimizer:GetEC2InstanceRecommendations"
            ],
            resources = ["*"]
          },
          {
            sid    = "KMSPermissions",
            effect = "Allow",
            actions = [
              "kms:CreateGrant",
              "kms:Decrypt",
              "kms:GenerateDataKeyWithoutPlainText",
              "kms:DescribeKey",
              "kms:ReEncrypt*"
            ],
            resources = ["*"]
          }
        ]
      }

    }

    fsx_windows_file_systems = {
      ad-azure-fsx = {
        ad_dns_ips = flatten([
          module.ad_fixngo_ip_addresses.mp_ips.ad_fixngo_azure_domain_controllers,
        ])
        ad_domain_name                      = "azure.noms.root"
        ad_file_system_administrators_group = null
        ad_username                         = "svc_join_domain"
        aliases                             = ["fs.azure.noms.root"]
        deployment_type                     = "SINGLE_AZ_1"
        security_group_name                 = "ad_azure_fsx_sg"
        storage_capacity                    = 100
        subnet_ids                          = [module.vpc["non_live_data"].non_tgw_subnet_ids_map.private[0]]
        throughput_capacity                 = 128
        weekly_maintenance_start_time       = "2:04:00" # tue 4am
      }
      ad-hmpp-fsx-additional = {
        ad_dns_ips = flatten([
          module.ad_fixngo_ip_addresses.mp_ips.ad_fixngo_hmpp_domain_controllers,
        ])
        ad_domain_name                      = "azure.hmpp.root"
        ad_file_system_administrators_group = "AWS FSx Admins"
        ad_username                         = "svc_fsx_windows"
        aliases                             = ["fs.azure.hmpp.root", "fslinux.azure.hmpp.root"]
        deployment_type                     = "MULTI_AZ_1"
        security_group_name                 = "ad_hmpp_fsx_sg"
        storage_capacity                    = 1000
        subnet_ids = [
          aws_subnet.live-data-additional["eu-west-2a"].id,
          aws_subnet.live-data-additional["eu-west-2b"].id,
        ]
        throughput_capacity           = 128
        weekly_maintenance_start_time = "4:04:00" # thu 4am
      }
    }

    route53_resolver_endpoints = {
      ad-fixngo-live-data = {
        direction           = "OUTBOUND"
        security_group_name = "ad_hmpp_route53_resolver_sg"
        subnet_ids          = module.vpc["live_data"].non_tgw_subnet_ids_map.private
      }
      ad-fixngo-non-live-data = {
        direction           = "OUTBOUND"
        security_group_name = "ad_azure_route53_resolver_sg"
        subnet_ids          = module.vpc["non_live_data"].non_tgw_subnet_ids_map.private
      }
    }

    route53_resolver_rules = {
      ad-fixngo-azure-noms-root = {
        domain_name = "azure.noms.root"
        target_ips = flatten([
          module.ad_fixngo_ip_addresses.azure_fixngo_ips.devtest.domain_controllers,
          module.ad_fixngo_ip_addresses.mp_ips.ad_fixngo_azure_domain_controllers,
        ])
        resolver_endpoint_name = "ad-fixngo-non-live-data"
        rule_type              = "FORWARD"
        vpc_id                 = module.vpc["non_live_data"].vpc_id
      }
      ad-fixngo-azure-hmpp-root = {
        domain_name = "azure.hmpp.root"
        target_ips = flatten([
          module.ad_fixngo_ip_addresses.azure_fixngo_ips.prod.domain_controllers,
          module.ad_fixngo_ip_addresses.mp_ips.ad_fixngo_hmpp_domain_controllers,
        ])
        resolver_endpoint_name = "ad-fixngo-live-data"
        rule_type              = "FORWARD"
        vpc_id                 = module.vpc["live_data"].vpc_id
      }
      # resolve infra.int hosts via HMPP DCs as they have forest trust
      ad-fixngo-infra-int = {
        domain_name = "infra.int"
        target_ips = flatten([
          module.ad_fixngo_ip_addresses.azure_fixngo_ips.prod.domain_controllers,
          module.ad_fixngo_ip_addresses.mp_ips.ad_fixngo_hmpp_domain_controllers,
        ])
        resolver_endpoint_name = "ad-fixngo-live-data"
        rule_type              = "FORWARD"
        vpc_id                 = module.vpc["live_data"].vpc_id
      }
    }

    security_groups = {
      ad_hmpp_route53_resolver_sg = {
        description = "Security group for azure.hmpp.root Route53 Resolver"
        vpc_id      = module.vpc["live_data"].vpc_id
        ingress     = {}
        egress = {
          dns-tcp = {
            port        = 53
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          dns-udp = {
            port        = 53
            protocol    = "UDP"
            cidr_blocks = ["10.0.0.0/8"]
          }
        }
      }
      ad_hmpp_dc_sg = {
        description = "Security group for azure.hmpp.root DCs"
        vpc_id      = module.vpc["live_data"].vpc_id
        ingress = {
          all-from-self = {
            port     = 0
            protocol = -1
            self     = true
          }
          dns-udp-53 = {
            port        = 53
            protocol    = "UDP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          dns-tcp-53 = {
            port        = 53
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          kerberos-udp-88 = {
            port        = 88
            protocol    = "UDP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          kerberos-tcp-88 = {
            port        = 88
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          ntp-udp-123 = {
            port        = 123
            protocol    = "UDP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          rpc-tcp-135 = {
            port        = 135
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          netbios-tcp-137-139 = {
            from_port   = 137
            to_port     = 139
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          ldap-udp-389 = {
            port        = 389
            protocol    = "UDP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          ldap-tcp-389 = {
            port        = 389
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          smb-tcp-445 = {
            port        = 445
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          kerberos-udp-464 = {
            port        = 464
            protocol    = "UDP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          kerberos-tcp-464 = {
            port        = 464
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          ldaps-tcp-636 = {
            port        = 636
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          ldap-global-catalog-tcp-3268 = {
            from_port   = 3268
            to_port     = 3269
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          ldaps-tcp-3269 = {
            port        = 3269
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          rdp-tcp-3389 = {
            port     = 3389
            protocol = "TCP"
            cidr_blocks = flatten([
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-preproduction,
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-production,
            ])
          }
          winrm-tcp-5985-5986 = {
            from_port = 5985
            to_port   = 5986
            protocol  = "TCP"
            cidr_blocks = flatten([
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-preproduction,
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-production,
            ])
          }
          adws-tcp-9389 = {
            port        = 9389
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          rpc-tcp-dynamic2 = {
            from_port   = 49152
            to_port     = 65535
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
        }
        egress = {
          all = {
            port        = 0
            protocol    = -1
            cidr_blocks = ["0.0.0.0/0"]
          }
        }
      }
      ad_hmpp_fsx_sg = {
        description = "Security group for azure.hmpp.root FSX"
        vpc_id      = module.vpc["live_data"].vpc_id
        ingress = {
          smb-tcp-445 = {
            port        = 445
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          winrm-tcp-5985-5986 = {
            from_port = 5985
            to_port   = 5986
            protocol  = "TCP"
            cidr_blocks = flatten([
              module.ad_fixngo_ip_addresses.azure_fixngo_cidrs.prod,
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-preproduction,
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-production,
            ])
          }
        }
        egress = {
          all = {
            port        = 0
            protocol    = -1
            cidr_blocks = ["0.0.0.0/0"]
          }
        }
      }
      ad_hmpp_rdlic_sg = {
        # requires RPC
        description = "security group for azure.hmpp.root remote desktop licensing server"
        vpc_id      = module.vpc["live_data"].vpc_id
        ingress = {
          all-from-self = {
            port     = 0
            protocol = -1
            self     = true
          }
          rpc-tcp-135 = {
            port     = 135
            protocol = "TCP"
            cidr_blocks = flatten([
              module.ad_fixngo_ip_addresses.azure_fixngo_cidrs.prod,
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-preproduction,
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-production,
            ])
          }
          netbios-tcp-139 = {
            port     = 139
            protocol = "TCP"
            cidr_blocks = flatten([
              module.ad_fixngo_ip_addresses.azure_fixngo_cidrs.prod_domain_controllers,
              module.ad_fixngo_ip_addresses.mp_cidrs.ad_fixngo_hmpp_domain_controllers,
            ])
          }
          netbios-tcp-445 = {
            port     = 445
            protocol = "TCP"
            cidr_blocks = flatten([
              module.ad_fixngo_ip_addresses.azure_fixngo_cidrs.prod_domain_controllers,
              module.ad_fixngo_ip_addresses.mp_cidrs.ad_fixngo_hmpp_domain_controllers,
            ])
          }
          rdp-tcp-3389 = {
            port     = 3389
            protocol = "TCP"
            cidr_blocks = flatten([
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-preproduction,
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-production,
            ])
          }
          winrm-tcp-5985-5986 = {
            from_port = 5985
            to_port   = 5986
            protocol  = "TCP"
            cidr_blocks = flatten([
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-preproduction,
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-production,
            ])
          }
          rpc-tcp-dynamic2 = {
            from_port = 49152
            to_port   = 65535
            protocol  = "TCP"
            cidr_blocks = flatten([
              module.ad_fixngo_ip_addresses.azure_fixngo_cidrs.prod,
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-preproduction,
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-production,
            ])
          }
        }
        egress = {
          all = {
            port        = 0
            protocol    = -1
            cidr_blocks = ["0.0.0.0/0"]
          }
        }
      }

      ad_azure_route53_resolver_sg = {
        description = "Security group for azure.noms.root Route53 Resolver"
        vpc_id      = module.vpc["non_live_data"].vpc_id
        ingress     = {}
        egress = {
          dns-tcp = {
            port        = 53
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          dns-udp = {
            port        = 53
            protocol    = "UDP"
            cidr_blocks = ["10.0.0.0/8"]
          }
        }
      }
      ad_azure_dc_sg = {
        description = "Security group for azure.noms.root DCs"
        vpc_id      = module.vpc["non_live_data"].vpc_id
        ingress = {
          all-from-self = {
            port     = 0
            protocol = -1
            self     = true
          }
          dns-udp-53 = {
            port        = 53
            protocol    = "UDP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          dns-tcp-53 = {
            port        = 53
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          kerberos-udp-88 = {
            port        = 88
            protocol    = "UDP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          kerberos-tcp-88 = {
            port        = 88
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          ntp-udp-123 = {
            port        = 123
            protocol    = "UDP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          rpc-tcp-135 = {
            port        = 135
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          netbios-tcp-139 = {
            port     = 139
            protocol = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          ldap-udp-389 = {
            port        = 389
            protocol    = "UDP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          ldap-tcp-389 = {
            port        = 389
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          smb-tcp-445 = {
            port        = 445
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          kerberos-udp-464 = {
            port        = 464
            protocol    = "UDP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          kerberos-tcp-464 = {
            port        = 464
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          rdp-tcp-3389 = {
            port     = 3389
            protocol = "TCP"
            cidr_blocks = flatten([
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-development,
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-test,
            ])
          }
          winrm-tcp-5985-5986 = {
            from_port = 5985
            to_port   = 5986
            protocol  = "TCP"
            cidr_blocks = flatten([
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-development,
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-test,
            ])
          }
          adws-tcp-9389 = {
            port        = 9389
            protocol    = "TCP"
            cidr_blocks = ["10.0.0.0/8"]
          }
          rpc-tcp-dynamic2 = {
            from_port   = 49152
            to_port     = 65535
            protocol    = "TCP"
            cidr_blocks = flatten([
              module.ad_fixngo_ip_addresses.azure_fixngo_cidrs.devtest,
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-development,
              module.ad_fixngo_ip_addresses.mp_cidr.hmpps-test,
            ])
          }
        }
        egress = {
          all = {
            port        = 0
            protocol    = -1
            cidr_blocks = ["0.0.0.0/0"]
          }
        }
      }
      ad_azure_fsx_sg = {
        description = "Security group for azure.noms.root FSX"
        vpc_id      = module.vpc["non_live_data"].vpc_id
        ingress = {
          smb-tcp-445 = {
            port        = 445
            protocol    = "TCP"
            cidr_blocks = ["1