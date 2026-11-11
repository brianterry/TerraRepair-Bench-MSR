```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

provider "aws" {
  alias  = "eu-west-2"
  region = "eu-west-2"
}

resource "aws_s3_bucket" "acm-pca" {
  bucket_prefix = "acm"

  logging {
    target_bucket = aws_s3_bucket.acm-pca.id
    target_prefix = "logs/"
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = merge(
    local.tags,
    {
      Name = "acm-pca"
    },
  )
}

resource "aws_s3_bucket_lifecycle_configuration" "acm-pca" {
  bucket = aws_s3_bucket.acm-pca.bucket

  rule {
    id     = "default"
    status = "Enabled"

    filter {
      prefix = ""
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = "3"
    }

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "acm-pca" {
  bucket                  = aws_s3_bucket.acm-pca.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "acm-pca" {
  bucket                = aws_s3_bucket.acm-pca.id
  expected_bucket_owner = local.environment_management.account_ids["core-network-services-production"]

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.acm.arn
    }
    bucket_key_enabled = false
  }
}

resource "aws_s3_bucket_versioning" "acm-pca" {
  bucket                = aws_s3_bucket.acm-pca.id
  expected_bucket_owner = local.environment_management.account_ids["core-network-services-production"]
  versioning_configuration {
    mfa_delete = "Disabled"
    status     = "Enabled"
  }
}

data "aws_iam_policy_document" "acmpca_bucket_access" {

  statement {
    actions = [
      "s3:GetBucketAcl",
      "s3:GetBucketLocation",
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]

    resources = [
      aws_s3_bucket.acm-pca.arn,
      "${aws_s3_bucket.acm-pca.arn}/*"
    ]
    principals {
      identifiers = ["acm-pca.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_s3_bucket_policy" "root" {

  bucket = aws_s3_bucket.acm-pca.id
  policy = data.aws_iam_policy_document.acmpca_bucket_access.json
}

resource "aws_acmpca_certificate_authority_certificate" "root" {
  certificate_authority_arn = aws_acmpca_certificate_authority.root.arn

  certificate       = aws_acmpca_certificate.root.certificate
  certificate_chain = aws_acmpca_certificate.root.certificate_chain
}

resource "aws_acmpca_certificate" "root" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.root.arn
  certificate_signing_request = aws_acmpca_certificate_authority.root.certificate_signing_request
  signing_algorithm           = "SHA512WITHRSA"

  template_arn = "arn:${data.aws_partition.current.partition}:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = 25
  }
}

resource "aws_acmpca_certificate_authority" "root" {

  type = "ROOT"
  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name         = "moj-modernisation-platform-root-CA"
      organization        = "ministry-of-justice"
      organizational_unit = "modernisation-platform"
      country             = "UK"
      state               = "UK"
      locality            = "UK"
    }
  }
  revocation_configuration {

    crl_configuration {
      custom_cname       = "moj-modernisation-platform-crl-root-CA"
      enabled            = true
      expiration_in_days = 7
      s3_bucket_name     = aws_s3_bucket.acm-pca.id
    }
  }

  permanent_deletion_time_in_days = 7

  tags = merge(
    local.tags,
    {
      Name = "acm-pca-root-ca"
    },
  )
  depends_on = [aws_s3_bucket_policy.root]
}

resource "aws_acmpca_certificate_authority_certificate" "live_subordinate" {

  depends_on = [aws_acmpca_certificate_authority.root]

  certificate_authority_arn = aws_acmpca_certificate_authority.live_subordinate.arn

  certificate       = aws_acmpca_certificate.live_subordinate.certificate
  certificate_chain = aws_acmpca_certificate.live_subordinate.certificate_chain
}

resource "aws_acmpca_certificate" "live_subordinate" {

  depends_on = [aws_acmpca_certificate_authority.root]

  certificate_authority_arn   = aws_acmpca_certificate_authority.root.arn
  certificate_signing_request = aws_acmpca_certificate_authority.live_subordinate.certificate_signing_request
  signing_algorithm           = "SHA512WITHRSA"

  template_arn = "arn:${data.aws_partition.current.partition}:acm-pca:::template/SubordinateCACertificate_PathLen0/V1"

  validity {
    type  = "YEARS"
    value = 24
  }
}

resource "aws_acmpca_certificate_authority" "live_subordinate" {
  type = "SUBORDINATE"

  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name         = "moj-modernisation-platform-sub-ca-live-data"
      organization        = "ministry-of-justice"
      organizational_unit = "modernisation-platform"
      country             = "UK"
      state               = "UK"
      locality            = "UK"
    }

  }
}

resource "aws_acmpca_certificate_authority_certificate" "non-live_subordinate" {

  depends_on = [aws_acmpca_certificate_authority.root]

  certificate_authority_arn = aws_acmpca_certificate_authority.non-live_subordinate.arn

  certificate       = aws_acmpca_certificate.non-live_subordinate.certificate
  certificate_chain = aws_acmpca_certificate.non-live_subordinate.certificate_chain
}

resource "aws_acmpca_certificate" "non-live_subordinate" {

  depends_on = [aws_acmpca_certificate_authority.root]

  certificate_authority_arn   = aws_acmpca_certificate_authority.root.arn
  certificate_signing_request = aws_acmpca_certificate_authority.non-live_subordinate.certificate_signing_request
  signing_algorithm           = "SHA512WITHRSA"

  template_arn = "arn:${data.aws_partition.current.partition}:acm-pca:::template/SubordinateCACertificate_PathLen0/V1"

  validity {
    type  = "YEARS"
    value = 24
  }
}

resource "aws_acmpca_certificate_authority" "non-live_subordinate" {
  type = "SUBORDINATE"

  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name         = "moj-modernisation-platform-sub-ca-non-live-data"
      organization        = "ministry-of-justice"
      organizational_unit = "modernisation-platform"
      country             = "UK"
      state               = "UK"
      locality            = "UK"
    }
  }
}

resource "aws_kms_key" "acm" {
  description         = "ACM PCA (private certificate authority) encryption key"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.kms-acm.json

  tags = merge(
    local.tags,
    {
      Name = "acm-pca"
    },
  )
}

resource "aws_kms_alias" "acm-alias" {
  name          = "alias/acm-pca-root"
  target_key_id = aws_kms_key.acm.arn
}

resource "aws_cloudwatch_log_group" "external_inspection" {
  name              = "external-inspection-flow-logs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.general_shared.arn
  tags              = local.tags
}

resource "aws_flow_log" "external_inspection" {
  iam_role_arn             = aws_iam_role.vpc_flow_log.arn
  log_destination          = aws_cloudwatch_log_group.external_inspection.arn
  log_format               = local.custom_vpc_flow_log_format
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  max_aggregation_interval = "60"
  vpc_id                   = aws_vpc.external_inspection.id

  tags = merge(
    local.tags,
    {
      Name = "external-inspection-flow-logs"
    }
  )
}

resource "aws_flow_log" "external_inspection_s3" {
  log_destination          = local.core_logging_bucket_arns["vpc-flow-logs"]
  log_destination_type     = "s3"
  log_format               = local.custom_vpc_flow_log_format
  max_aggregation_interval = "60"
  traffic_type             = "ALL"
  vpc_id                   = aws_vpc.external_inspection.id

  tags = merge(
    local.tags,
    {
      Name = "external-inspection-vpc-flow-logs-s3"
    }
  )
}

resource "aws_subnet" "external_inspection_in" {
  for_each = local.external_inspection_in_subnets_map

  vpc_id            = aws_vpc.external_inspection.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(
    local.tags,
    {
      Name = "external-inspection-in-${each.key}"
    }
  )
}

resource "aws_subnet" "external_inspection_out" {
  for_each = local.external_inspection_out_subnets_map

  vpc_id            = aws_vpc.external_inspection.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(
    local.tags,
    {
      Name = "external-inspection-out-${each.key}"
    }
  )
}

resource "aws_route_table" "external_inspection_in" {
  for_each = local.external_inspection_in_subnets_map

  vpc_id = aws_vpc.external_inspection.id

  route {
    cidr_block      = "0.0.0.0/0"
    vpc_endpoint_id = element([for ss in tolist(aws_networkfirewall_firewall.external_inspection.firewall_status[0].sync_states) : ss.attachment[0].endpoint_id if ss.attachment[0].subnet_id == aws_subnet.external_inspection_out[each.key].id], 0)
  }

  tags = merge(
    local.tags,
    {
      Name = "external-inspection_in_${each.key}"
    }
  )
}

resource "aws_route_table_association" "external_inspection_in" {
  for_each = local.external_inspection_in_subnets_map

  route_table_id = aws_route_table.external_inspection_in[each.key].id
  subnet_id      = aws_subnet.external_inspection_in[each.key].id
}

resource "aws_route_table" "external_inspection_out" {
  vpc_id = aws_vpc.external_inspection.id

  route {
    cidr_block         = "0.0.0.0/0"
    transit_gateway_id = aws_ec2_transit_gateway.transit-gateway.id
  }

  tags = merge(
    local.tags,
    {
      Name = "external-inspection_out"
    }
  )
}

resource "aws_route_table_association" "external_inspection_out" {
  for_each = local.external_inspection_in_subnets_map

  route_table_id = aws_route_table.external_inspection_out.id
  subnet_id      = aws_subnet.external_inspection_out[each.key].id
}

module "firewall_policy" {
  source                 = "../../modules/firewall-policy"
  fw_rulegroup_capacity  = "10000"
  fw_kms_arn             = data.aws_kms_key.general_shared.arn
  fw_policy_name         = format("%s-fw-policy", local.application_name)
  fw_rulegroup_name      = format("%s-fw-rulegroup", local.application_name)
  fw_fqdn_rulegroup_name = format("%s-fw-fqdn-rulegroup", local.application_name)
  fw_allowed_domains     = local.fqdn_firewall_rules.fw_allowed_domains
  fw_home_net_ips        = local.fqdn_firewall_rules.fw_home_net_ips
  ip_sets                = local.firewall_sets["IP_SETS"]
  port_sets              = local.firewall_sets["PORT_SETS"]
  rules                  = local.firewall_rules
  tags                   = local.tags
}

module "firewall_logging" {
  source                    = "../../modules/firewall-logging"
  cloudwatch_log_group_name = format("fw-%s-logs", aws_networkfirewall_firewall.external_inspection.name)
  fw_arn                    = aws_networkfirewall_firewall.external_inspection.arn
  tags                      = local.tags
}

resource "aws_networkfirewall_firewall" "external_inspection" {
  depends_on          = [aws_subnet.external_inspection_out]
  name                = "external-inspection"
  firewall_policy_arn = module.firewall_policy.fw_policy_arn
  vpc_id              = aws_vpc.external_inspection.id
  delete_protection   = true
  encryption_configuration {
    type   = "CUSTOMER_KMS"
    key_id = data.aws_kms_key.general_shared.arn
  }
  subnet_mapping { subnet_id = aws_subnet.external_inspection_out["eu-west-2a"].id }
  subnet_mapping { subnet_id = aws_subnet.external_inspection_out["eu-west-2b"].id }
  subnet_mapping { subnet_id = aws_subnet.external_inspection_out["eu-west-2c"].id }
  tags = merge(
    local.tags,
    { Name = "external-inspection" }
  )
}

resource "aws_ec2_transit_gateway_vpc_attachment" "external_inspection_in" {

  transit_gateway_id = aws_ec2_transit_gateway.transit-gateway.id

  vpc_id = aws_vpc.external_inspection.id
  subnet_ids = [
    for subnet in aws_subnet.external_inspection_in :
    subnet.id
  ]

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  dns_support = "disable"

  ipv6_support = "disable"

  appliance_mode_support = "enable"

  tags = merge(
    local.tags,
    {
      Name = "inspection-attachment"
    }
  )

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role" "vpc_flow_log" {
  name               = "AWSVPCFlowLog"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_log_assume_role_policy.json
}

data "aws_iam_policy_document" "vpc_flow_log_assume_role_policy" {
  version = "2012-10-17"
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "vpc_flow_log_publish_policy" {
  name   = "AWSVPCFlowLogPublishPolicy"
  policy = data.aws_iam_policy_document.vpc_flow_log_publish_policy.json
}

data "aws_iam_policy_document" "vpc_flow_log_publish_policy" {

  version = "2012-10-17"

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy_attachment" "vpc_flow_log_publish_policy" {
  role       = aws_iam_role.vpc_flow_log.id
  policy_arn = aws_iam_policy.vpc_flow_log_publish_policy.arn
}

resource "aws_iam_role" "dns" {
  name = "modify-dns-records"
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Principal" : {
            "AWS" : data.aws_caller_identity.modernisation-platform.account_id
          },
          "Action" : "sts:AssumeRole",
          "Condition" : {}
        },
        {
          "Effect" : "Allow",
          "Principal" : {
            "AWS" : "arn:aws:iam::${local.environment_management.account_ids["testing-test"]}:user/testing-ci"
          },
          "Action" : "sts:AssumeRole",
          "Condition" : {}
        },
        {
          "Effect" : "Allow",
          "Principal" : {
            "AWS" : "*"
          },
          "Action" : "sts:AssumeRole",
          "Condition" : {
            "ForAnyValue:StringLike" : {
              "aws:PrincipalOrgPaths" : ["${data.aws_organizations_organization.root_account.id}/*/${local.environment_management.modernisation_platform_organisation_unit_id}/*"],
              "aws:PrincipalArn" : ["arn:aws:iam::*:role/github-actions", "arn:aws:iam::*:role/github-actions-environments-read-only", "arn:aws:iam::*:role/github-actions-environments-dev-test", "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_AdministratorAccess_*"]
            }
          }
        }
      ]
  })

  tags = merge(
    local.tags,
    {
      Name = "modify-dns-records"
    },
  )
}

resource "aws_iam_role_policy" "dns" {
  name = "modify-dns-records"
  role = aws_iam_role.dns.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Effect" : "Allow",
        "Action" : [
          "route53:Get*",
          "route53:List*"
        ],
        "Resource" : "*"
      },
      {
        Effect = "Allow",
        Action = ["route53:ChangeResourceRecordSets"],
        Resource = concat(
          [for zone in aws_route53_zone.application_zones : format("arn:aws:route53:::hostedzone/%s", zone.id)],
          [for zone in aws_route53_zone.private_application_zones : format("arn:aws:route53:::hostedzone/%s", zone.id)],
          [
            "arn:aws:route53:::hostedzone/${aws_route53_zone.modernisation-platform.id}",
            "arn:aws:route53:::hostedzone/${aws_route53_zone.modernisation-platform-internal.id}"

          ]
        )
      }
    ]
  })
}

resource "aws_iam_role" "read_logs" {
  name = "read-log-records"
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
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
        }
      ]
  })

  tags = merge(
    local.tags,
    {
      Name = "read-log-records"
    },
  )
}

resource "aws_iam_role_policy" "read_dns" {
  name = "ReadDNSRecords"
  role = aws_iam_role.read_logs.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        "Effect" : "Allow",
        "Action" : [
          "route53:Get*",
          "route53:List*"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeRouteTables",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeNatGateways",
          "ec2:DescribeVpnConnections",
          "ec2:DescribeVpnGateways",
          "ec2:DescribeCustomerGateways",
          "ec2:DescribeTransitGateways",
          "ec2:DescribeTransitGatewayAttachments",
          "ec2:DescribeTransitGatewayRouteTables",
          "ec2:DescribeNetworkAcls",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeAddresses", # Elastic IPs
          "ec2:DescribeNetworkInterfaces",
          "ec2:GetTransitGatewayRouteTablePropagations",
          "ec2:GetTransitGatewayRouteTableAssociations",
          "ec2:GetTransitGatewayPrefixListReferences",
          "ec2:SearchTransitGatewayRoutes"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "read_firewall" {
  name = "ReadFirewallRecords"
  role = aws_iam_role.read_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:DescribeQueries",
          "logs:FilterLogEvents",
          "logs:GetLogEvents",
          "logs:GetLogGroupFields",
          "logs:GetLogRecord",
          "logs:GetQueryResults",
          "logs:StartQuery",
          "logs:StopQuery"
        ],
        "Resource" : [
          "arn:aws:logs:*:*:log-group::log-stream:",
          "arn:aws:logs:*:*:log-group:fw-*:log-stream:*",
          "arn:aws:logs:*:*:log-group:*-vpc-flow-logs-*:log-stream:*",
          "arn:aws:logs:*:*:log-group:external-inspection-flow-logs:log-stream:*",
          "arn:aws:logs:*:*:log-group:tgw-*:log-stream:*",
          "arn:aws:logs:*:*:log-group:NEC*:log-stream:*"
        ],
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "network-firewall:Describe*",
          "network-firewall:List*"
        ],
        "Resource" : "arn:aws:network-firewall:*:*:*/*"
      }
    ]
  })
}

module "vpn_environment_check_oidc" {
  source                      = "github.com/ministryofjustice/modernisation-platform-github-oidc-provider?ref=6dd6f177091fb1664998aa37a1d0d5cf5894c10a" # v4.2.0
  role_name                   = "github-actions-vpn-environment-check"
  create_github_oidc_provider = false
  github_repositories         = ["ministryofjustice/modernisation-platform-environments:*"]
  additional_permissions      = data.aws_iam_policy_document.vpn_environment_check_permissions.json
  tags_common                 = { "Name" = format("%s-oidc", terraform.workspace) }
  tags_prefix                 = ""
}

data "aws_iam_policy_document" "vpn_environment_check_permissions" {
  version = "2012-10-17"
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeVpnConnections"
    ]
    resources = local.vpn_lifecycle_control_arns
  }
}

module "vpn_maintenance_oidc" {
  source                      = "github.com/ministryofjustice/modernisation-platform-github-oidc-provider?ref=6dd6f177091fb1664998aa37a1d0d5cf5894c10a" # v4.2.0
  role_name                   = "github-actions-vpn-maintenance"
  create_github_oidc_provider = false
  github_repositories         = local.github_repository_environments_from_vpns
  additional_permissions      = data.aws_iam_policy_document.vpn_maintenance_permissions.json
  tags_common                 = { "Name" = format("%s-oidc", terraform.workspace) }
  tags_prefix                 = ""
}

data "aws_iam_policy_document" "vpn_maintenance_permissions" {
  version = "2012-10-17"
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeVpnConnections",
      "ec2:ReplaceVpnTunnel"
    ]
    resources = local.vpn_lifecycle_control_arns
  }
}

data "aws_caller_identity" "modernisation-platform" {
  provider = aws.modernisation-platform
}

data "aws_organizations_organization" "root_account" {}

locals {
  application_name = "core-network-services"
  custom_tgw_flow_log_format = "$${version} $${resource-type} $${account-id} $${tgw-id} $${tgw-attachment-id} $${tgw-src-vpc-account-id} $${tgw-dst-vpc-account-id} $${tgw-src-vpc-id} $${tgw-dst-vpc-id} $${tgw-src-subnet-id} $${tgw-dst-subnet-id} $${tgw-src-eni} $${tgw-dst-eni} $${tgw-src-az-id} $${tgw-dst-az-id} $${tgw-pair-attachment-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${log-status} $${type} $${packets-lost-no-route} $${packets-lost-blackhole} $${packets-lost-mtu-exceeded} $${packets-lost-ttl-expired} $${tcp-flags} $${region} $${flow-direction} $${pkt-src-aws-service} $${pkt-dst-aws-service}"
  custom_vpc_flow_log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr} $${region} $${az-id} $${sublocation-type} $${sublocation-id} $${pkt-src-aws-service} $${pkt-dst-aws-service} $${flow-direction} $${traffic-path}"
  environment_management     = jsondecode(data.aws_secretsmanager_secret_version.environment_management.secret_string)
  pagerduty_integration_keys = jsondecode(data.aws_secretsmanager_secret_version.pagerduty_integration_keys.secret_string)

  is-production = substr(terraform.workspace, length(local.application_name), length(terraform.workspace)) == "-production"

  core_logging_bucket_arns      = jsondecode(data.aws_ssm_parameter.core_logging_bucket_arns.insecure_value)
  cloudwatch_generic_log_groups = concat([module.firewall_logging.cloudwatch_log_group_name], [for key, value in module.vpc_inspection : value.fw_cloudwatch_name])

  tags = {
    business-unit = "Platforms"
    service-area  = "Hosting"
    application   = "Modernisation Platform: core-network-services"
    is-production = local.is-production
    owner         = "Modernisation Platform: modernisation-platform@digital.justice.gov.uk"
  }

  active_tgw_peering_attachments = [
    "MOJ-TGW-attachment-accepter"
  ]

  active_tgw_vpc_attachments = [
    "hmcts-production-attachment",
    "hmpps-production-attachment",
    "core-network-services-live_data-attachment",
  ]

  sandbox_rules         = fileexists("./firewall-rules/sandbox_rules.json")? { for k in sort(keys(jsondecode(templatefile("./firewall-rules/sandbox_rules.json", local.all_cidr_ranges)))) : k => jsondecode(templatefile("./firewall-rules/sandbox_rules.json", local.all_cidr_ranges))[k] } : {}
  development_rules     = fileexists("./firewall-rules/development_rules.json")? { for k in sort(keys(jsondecode(templatefile("./firewall-rules/development_rules.json", local.all_cidr_ranges)))) : k => jsondecode(templatefile("./firewall-rules/development_rules.json", local.all_cidr_ranges))[k] } : {}
  test_rules            = fileexists("./firewall-rules/test_rules.json")? { for k in sort(keys(jsondecode(templatefile("./firewall-rules/test_rules.json", local.all_cidr_ranges)))) : k => jsondecode(templatefile("./firewall-rules/test_rules.json", local.all_cidr_ranges))[k] } : {}
  preproduction_rules   = fileexists("./firewall-rules/preproduction_rules.json")? { for k in sort(keys(jsondecode(templatefile("./firewall-rules/preproduction_rules.json", local.all_cidr_ranges)))) : k => jsondecode(templatefile("./firewall-rules/preproduction_rules.json", local.all_cidr_ranges))[k] } : {}
  production_rules      = fileexists("./firewall-rules/production_rules.json")? { for k in sort(keys(jsondecode(templatefile("./firewall-rules/production_rules.json", local.all_cidr_ranges)))) : k => jsondecode(templatefile("./firewall-rules/production_rules.json", local.all_cidr_ranges))[k] } : {}
  live_data_rules       = fileexists("./firewall-rules/live_data_rules.json")? { for k in sort(keys(jsondecode(templatefile("./firewall-rules/live_data_rules.json", local.all_cidr_ranges)))) : k => jsondecode(templatefile("./firewall-rules/live_data_rules.json", local.all_cidr_ranges))[k] } : {}
  non_live_data_rules   = fileexists("./firewall-rules/non_live_data_rules.json")? { for k in sort(keys(jsondecode(templatefile("./firewall-rules/non_live_data_rules.json", local.all_cidr_ranges)))) : k => jsondecode(templatefile("./firewall-rules/non_live_data_rules.json", local.all_cidr_ranges))[k] } : {}
  fqdn_firewall_rules   = fileexists("./firewall-rules/fqdn_rules.json")? jsondecode(file("./firewall-rules/fqdn_rules.json")) : {}
  inline_firewall_rules = fileexists("./firewall-rules/inline_rules.json")? jsondecode(templatefile("./firewall-rules/inline_rules.json", local.all_cidr_ranges)) : {}

  firewall_rules = merge(
    local.sandbox_rules,
    local.development_rules,
    local.test_rules,
    local.preproduction_rules,
    local.production_rules,
    local.live_data_rules,
    local.non_live_data_rules
  )
  firewall_sets = fileexists("./firewall-rules/sets.json")? jsondecode(templatefile("./firewall-rules/sets.json", local.all_cidr_ranges)) : {}

  vpn_attachments = fileexists("./vpn_attachments.json")? jsondecode(file("./vpn_attachments.json")) : tomap({})

  vpn_lifecycle_control_ids = [
    for name, cfg in local.vpn_attachments :
    name
    if(
      (try(cfg.tunnel1_enable_tunnel_lifecycle_control, "false") == "true") ||
      (try(cfg.tunnel2_enable_tunnel_lifecycle_control, "false") == "true")
    )
  ]

  vpn_lifecycle_control_arns = [
    for k, v in aws_vpn_connection.this :
    v.arn
    if contains(local.vpn_lifecycle_control_ids, k)
  ]

  github_repository_environments_from_vpns = distinct([
    for vpn_id, vpn in local.vpn_attachments :
    "ministryofjustice/modernisation-platform-environments:environment:${vpn.github_environment}"
    if contains(keys(vpn), "github_environment") && vpn.github_environment!= ""
  ])

  noms_vpn_attachment_ids = toset([for k in aws_vpn_connection.this : k.transit_gateway_attachment_id if(length(regexall("(?:NOMS)", k.tags.Name)) > 0)])

  nec_vpn_attachment_ids = toset([for k in aws_vpn_connection.this : k.transit_gateway_attachment_id if(length(regexall("(?:NEC)", k.tags.Name)) > 0)])

  azure_static_routes = [
    "10.0.0.0/11",
    "10.64.0.0/11",
    "10.100.0.0/15",
    "10.104.0.0/16",
    "10.108.0.0/18",
    "10.108.64.0/23",
    "10.128.0.0/16",
    "10.132.0.0/16",
    "10.136.0.0/13",
    "10.147.0.0/16",
    "10.148.0.0/14",
    "10.154.0.0/23",
    "10.154.16.0/23",
    "10.154.32.0/23",
    "10.154.48.0/23",
    "10.154.64.0/23",
    "10.154.80.0/23",
    "10.154.96.0/23",
    "10.154.112.0/23",
    "10.154.128.0/23",
    "10.154.144.0/23",
    "10.154.160.0/23",
    "10.154.176.0/23",
    "10.154.192.0/23",
    "10.154.208.0/23",
    "10.154.240.0/21",
    "10.154.224.0/21",
    "10.180.0.0/16",
    "10.184.128.0/18",
    "10.184.192.0/18",
    "10.184.32.0/19",
    "10.184.64.0/19",
    "10.184.96.0/19",
    "10.185.0.0/16",
    "10.155.0.0/23",
    "10.159.240.0/20",
    "10.163.0.0/20",
    "10.171.0.0/16",
    "10.172.0.0/16",
    "10.175.0.0/16",
    "10.176.0.0/16",
    "10.178.0.0/16",
    "10.179.0.0/16",
    "10.188.0.160/27",
    "10.205.0.0/24",
    "10.208.0.0/12",
    "10.211.0.0/22",
    "10.228.224.0/19",
    "10.231.252.0/23",
    "10.232.0.0/16",
    "10.233.64.0/18",
    "10.233.128.0/18",
    "10.233.192.0/20",
    "10.233.208.0/22",
    "10.233.212.0/23",
    "10.233.214.0/23",
    "10.233.216.0/21",
    "10.233.224.0/19",
    "10.234.0.0/15",
    "10.236.0.0/14",
    "10.240.0.0/16",
    "10.243.224.0/20",
    "10.245.252.0/22",
    "172.16.0.0/12",
    "172.16.9.0/24",
    "1