```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

provider "aws" {
  alias  = "eu-west-2"
  region = "eu-west-2"
}

#Create S3 bucket for ACM
# TFSec ignores:
# - AWS002: Ignore warnings regarding lack of s3 bucket server access logging - considered overkill given bucket purpose and restricted access to bucket
#tfsec:ignore:AWS098 tfsec:ignore:AWS002 tfsec:ignore:aws-s3-block-public-acls tfsec:ignore:aws-s3-enable-bucket-encryption tfsec:ignore:aws-s3-enable-bucket-encryption tfsec:ignore:aws-s3-enable-versioning tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket" "acm-pca" {
  #checkov:skip=CKV_AWS_144:Ignore lack of cross-regional replication - not required here - represents an overkill
  #checkov:skip=CKV2_AWS_62:As noted above, event notifications not required
  bucket_prefix = "acm"

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

resource "aws_s3_bucket_logging" "acm-pca" {
  bucket = aws_s3_bucket.acm-pca.id

  target_bucket = aws_s3_bucket.acm-pca.id
  target_prefix = "logs/"
}

#S3 bucket access policy
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

#Associates a certificate with an AWS Certificate Manager Private Certificate Authority
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

#Create Private root ACM
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

#Create Private subordinate live data certificate
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

#Create Private subordinate non-live data certificate
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

# Setup KMS key
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

# Static code analysis ignores:
# - CKV_AWS_109 and CKV_AWS_111: Ignore warnings regarding resource = ["*"]. See https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html
#   Specifically: "In a key policy, the value of the Resource element is "*", which means "this KMS key." The asterisk ("*") identifies the KMS key to which the key policy is attached."
data "aws_iam_policy_document" "kms-acm" {
  # checkov:skip=CKV_AWS_109: "Key policy requires asterisk resource - see note above"
  # checkov:skip=CKV_AWS_111: "Key policy requires asterisk resource - see note above"
  # checkov:skip=CKV_AWS_356: "Key policy requires asterisk resource - see note above"

  statement {
    effect  = "Allow"
    actions = ["kms:*"]

    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["acm-pca.amazonaws.com"]
    }

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

#Create RAM share for subordinate certificates


output "acmpca_subordinate_non_live" {
  value = aws_acmpca_certificate_authority.non-live_subordinate.arn
}

output "acmpca_subordinate_live" {
  value = aws_acmpca_certificate_authority.live_subordinate.arn
}


# Backend
terraform {
  # `backend` blocks do not support variables, so the following are hard-coded here:
  # - S3 bucket name, which is created in modernisation-platform-account/s3.tf
  backend "s3" {
    acl                  = "bucket-owner-full-control"
    bucket               = "modernisation-platform-terraform-state"
    encrypt              = true
    key                  = "terraform.tfstate"
    region               = "eu-west-2"
    use_lockfile         = true
    workspace_key_prefix = "environments/accounts/core-network-services" # This will store the object as environments/core-network-services/${workspace}/terraform.tfstate
  }
}


variable "networking" {
  type = list(any)
  default = [
    {
      "business-unit" : "",
      "set" : "",
      "application" : "core-network-services"
    }
  ]
}


locals {
  mp_core_cidr_ranges = {
    mp-core                            = "10.20.0.0/16"
    mp-core-shared-services-additional = "10.27.136.0/21"
    mp-development-test                = "10.26.0.0/16"
    mp-preproduction-production        = "10.27.0.0/16"
    mp-sandbox                         = "10.231.0.0/20"
    mp-sandbox-garden                  = "10.231.0.0/21"
    mp-sandbox-house                   = "10.231.8.0/21"
  }

  # This will take the vpc CIDR ranges for each business/env general subnet set, from the environments-networks files
  # e.g. `hmpps-development = "10.26.24.0/21"
  platform_general_set_cidr_ranges = {
    for key, value in local.core-vpcs : key => value.cidr.subnet_sets.general.cidr
  }

  other_cidr_ranges = {
    analytical-platform-airflow-dev     = "10.200.0.0/16"
    analytical-platform-airflow-prod    = "10.201.0.0/16"
    analytical-platform-ingest-dev      = "10.26.128.0/23"
    analytical-platform-ingest-prod     = "10.27.128.0/23"
    data-engineering-dev                = "172.24.0.0/16"
    data-engineering-prod               = "172.25.0.0/16"
    data-engineering-stage              = "172.26.0.0/16"
    atos_arkc_ras                       = "10.175.0.0/16" # for DOM1 devices connected to Cisco RAS VPN
    atos_arkf_ras                       = "10.176.0.0/16" # for DOM1 devices connected to Cisco RAS VPN
    cloud-platform                      = "172.20.0.0/16"
    dom1-domain-controllers             = "10.172.68.144/29"
    global-protect                      = "10.184.0.0/14"
    i2n                                 = "10.110.0.0/16"
    moj-core-azure-1                    = "10.50.25.0/27"
    moj-core-azure-2                    = "10.50.26.0/24"
    mojo-azure-landing-zone             = "10.192.0.0/16"
    moj-wifi                            = "10.148.0.0/14"
    parole-board                        = "10.50.0.0/16"
    psn                                 = "51.0.0.0/8"
    psn-ppud                            = "51.247.2.115/32"
    vodafone_wan_nicts_aggregate        = "10.80.0.0/12" # for devices connected to Prison Networks
    youth-justice-networking-production = "10.20.224.0/21"
    xsiam-prod-vpc                      = "10.180.96.0/22"

    # hmpps azure cidr ranges
    noms-live-vnet         = "10.40.0.0/18"
    noms-mgmt-live-vnet    = "10.40.128.0/20"
    noms-transit-live-vnet = "10.40.160.0/20"
    noms-test-vnet         = "10.101.0.0/16"
    noms-mgmt-vnet         = "10.102.0.0/16"
    moj-smtp-relay1        = "10.180.104.100/32"
    moj-smtp-relay2        = "10.180.105.100/32"

    # hmpps aws cidr ranges
    delius-eng-dev                    = "10.161.98.0/25"
    delius-eng-prod                   = "10.160.98.0/25"
    delius-mis-dev                    = "10.162.32.0/20"
    delius-mis-dev-private-eu-west-2a = "10.162.32.0/22"
    delius-mis-dev-private-eu-west-2b = "10.162.36.0/22"
    delius-mis-dev-private-eu-west-2c = "10.162.40.0/22"
    delius-test                       = "10.162.0.0/20"
    delius-stage                      = "10.160.32.0/20"
    delius-pre-prod                   = "10.160.0.0/20"
    delius-training                   = "10.162.96.0/20"
    delius-prod                       = "10.160.16.0/20"

    # laa landing zone cidr ranges
    laa-lz-development             = "10.202.0.0/20"
    laa-lz-test                    = "10.203.0.0/20"
    laa-lz-uat                     = "10.206.0.0/20"
    laa-lz-staging                 = "10.204.0.0/20"
    laa-lz-production              = "10.205.0.0/20"
    laa-lz-shared-services-nonprod = "10.200.0.0/20"
    laa-lz-shared-services-prod    = "10.200.16.0/20"
    laa-appstream-vpc              = "10.200.32.0/19"
    laa-appstream-vpc_additional   = "10.200.68.0/22"
    laa-ecp-db-lb                  = "10.205.10.0/24"
    laa-ecp-safedb-1               = "10.205.14.0/24"
    laa-ecp-safedb-2               = "10.205.15.0/24"
    laa-ecp-safedb-3               = "10.205.11.0/24"

    # NEC cidr ranges
    nec-nonprod = "10.120.0.0/24"
    nec-prod    = "10.110.0.0/24"

    # laa modernisation-platform ranges
    laa-mp-development-general-private-subnets-a = "10.26.56.0/24"
    laa-mp-development-general-private-subnets-b = "10.26.57.0/24"
    laa-mp-development-general-private-subnets-c = "10.26.58.0/24"

    laa-mp-development-general-data-subnets-a = "10.26.60.128/25"
    laa-mp-development-general-data-subnets-b = "10.26.61.0/25"
    laa-mp-development-general-data-subnets-c = "10.26.61.128/25"

    laa-mp-test-general-private-subnets-a = "10.26.96.0/24"
    laa-mp-test-general-private-subnets-b = "10.26.97.0/24"
    laa-mp-test-general-private-subnets-c = "10.26.98.0/24"

    laa-mp-test-general-data-subnets-a = "10.26.100.128/25"
    laa-mp-test-general-data-subnets-b = "10.26.101.0/25"
    laa-mp-test-general-data-subnets-c = "10.26.101.128/25"

    laa-mp-preproduction-general-private-subnets-a = "10.27.72.0/24"
    laa-mp-preproduction-general-private-subnets-b = "10.27.73.0/24"
    laa-mp-preproduction-general-private-subnets-c = "10.27.74.0/24"

    laa-mp-preproduction-general-data-subnets-a = "10.27.76.128/25"
    laa-mp-preproduction-general-data-subnets-b = "10.27.77.0/25"
    laa-mp-preproduction-general-data-subnets-c = "10.27.77.128/25"

    laa-mp-production-general-private-subnets-a = "10.27.64.0/24"
    laa-mp-production-general-private-subnets-b = "10.27.65.0/24"
    laa-mp-production-general-private-subnets-c = "10.27.66.0/24"

    laa-mp-production-general-data-subnets-a = "10.27.68.128/25"
    laa-mp-production-general-data-subnets-b = "10.27.69.0/25"
    laa-mp-production-general-data-subnets-c = "10.27.69.128/25"

    hmpps-preproduction-general-private-subnets = "10.27.0.0/22"
    hmpps-production-general-private-subnets    = "10.27.8.0/22"

    # cica cidr ranges
    cica-aws-ss-a         = "10.10.10.0/24"
    cica-aws-ss-b         = "10.10.110.0/24"
    cica-aws-dev-a        = "10.11.10.0/24"
    cica-aws-dev-b        = "10.11.110.0/24"
    cica-aws-dev-data-a   = "10.11.20.0/24"
    cica-aws-dev-data-b   = "10.11.120.0/24"
    cica-aws-uat-a        = "10.12.10.0/24"
    cica-aws-uat-b        = "10.12.110.0/24"
    cica-aws-uat-data-a   = "10.12.20.0/24"
    cica-aws-uat-data-b   = "10.12.120.0/24"
    cica-onprem-uat       = "192.168.4.0/24"
    cica-onprem-prod      = "10.2.30.0/24"
    cica-end-user-devices = "10.9.14.0/23"
    cica-ras-nat          = "10.7.14.224/28"
    cica-aws-prod-a       = "10.13.10.0/24"
    cica-aws-prod-b       = "10.13.110.0/24"
    cica-aws-prod-c       = "10.13.20.0/24"
    cica-aws-prod-d       = "10.13.120.0/24"
    cica-onprem-lan       = "10.7.11.0/24"



    mojo-end-user-devices = "10.0.0.0/8"
    dom1-dcs              = "10.0.0.0/8"
    ad-hmpp-dc-azure-1    = "10.40.128.196/32"
    ad-hmpp-dc-azure-2    = "10.40.0.133/32"
    ad-hmpp-dc-a          = "10.27.136.5/32" # see https://github.com/ministryofjustice/modernisation-platform/issues/5970
    ad-hmpp-dc-b          = "10.27.137.5/32" # and https://dsdmoj.atlassian.net/wiki/x/3oCKGAE
    ad-hmpp-rdlic         = "10.27.138.6/32" # ditto
    ad-azure-dc-azure-1   = "10.102.0.196/32"
    ad-azure-dc-a         = "10.20.104.5/32" # ditto
    ad-azure-dc-b         = "10.20.106.5/32" # ditto
    ad-azure-rdlic        = "10.20.108.6/32" # ditto
  }

  all_cidr_ranges = merge(
    local.mp_core_cidr_ranges,
    local.platform_general_set_cidr_ranges,
    local.other_cidr_ranges
  )
}


data "aws_route" "non_live_data" {
  for_each = merge(
    module.vpc_inspection["non_live_data"].route_table_ids.transit_gateway,
    module.vpc_inspection["non_live_data"].route_table_ids.inspection,
    module.vpc_inspection["non_live_data"].route_table_ids.public
  )
  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
}

data "aws_route" "live_data" {
  for_each = merge(
    module.vpc_inspection["live_data"].route_table_ids.transit_gateway,
    module.vpc_inspection["live_data"].route_table_ids.inspection,
    module.vpc_inspection["live_data"].route_table_ids.public
  )
  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
}

data "aws_kms_key" "general_shared" {
  key_id = "arn:aws:kms:eu-west-2:${local.environment_management.account_ids["core-shared-services-production"]}:alias/general-platforms"
}

# Data source to fetch information about the live VPC
data "aws_vpc" "live" {
  filter {
    name   = "tag:Name"
    values = ["live_data"]
  }
}

# Data source to fetch information about the non-live VPC
data "aws_vpc" "non_live" {
  filter {
    name   = "tag:Name"
    values = ["non_live_data"]
  }
}

# Data source to fetch existing NAT gateways in the live VPC
data "aws_nat_gateways" "live" {
  vpc_id = data.aws_vpc.live.id

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Data source to fetch existing NAT gateways in the non-live VPC
data "aws_nat_gateways" "non_live" {
  vpc_id = data.aws_vpc.non_live.id

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_sns_topic" "security_hub_arn" {
  name = "securityhub-alarms"
}


locals {
  external_inspection_vpc             = "10.56.0.0/24"
  external_inspection_subnet_in       = cidrsubnet(local.external_inspection_vpc, 2, 1)
  external_inspection_subnet_out      = cidrsubnet(local.external_inspection_vpc, 2, 0)
  external_inspection_in_subnets_map  = { for key, cidr in cidrsubnets(local.external_inspection_subnet_in, 2, 2, 2) : local.availability_zones[key] => cidr }
  external_inspection_out_subnets_map = { for key, cidr in cidrsubnets(local.external_inspection_subnet_out, 2, 2, 2) : local.availability_zones[key] => cidr }

}

#################
# VPC creation #
#################
# Ingress inspection VPC
resource "aws_vpc" "external_inspection" {

  cidr_block = local.external_inspection_vpc

  # Instance Tenancy
  instance_tenancy = "default"
  # DNS
  enable_dns_support   = false
  enable_dns_hostnames = false

  # Turn off IPv6
  assign_generated_ipv6_cidr_block = false

  tags = merge(
    local.tags,
    {
      Name = "external_inspection"
    }
  )
}

resource "aws_default_security_group" "external_inspection" {
  vpc_id = aws_vpc.external_inspection.id

  tags = merge(
    local.tags,
    {
      Name = "external_inspection"
    }
  )
}

#################
# VPC Flow Logs #
#################
# TF sec exclusions
# - Ignore warnings regarding log groups not encrypted using customer-managed KMS keys - following cost/benefit discussion and longer term plans for logging solution
#tfsec:ignore:AWS089
resource "aws_cloudwatch_log_group" "external_inspection" {
  name              = "external-inspection-flow-logs"
  retention_in_days = 365 # 0 = never expire
  kms_key_id        = aws_kms_key.environment_logging.arn
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

########################
# Inspection VPC Subnets
########################
# Ingress Inspection in subnets
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
# Ingress Inspection out subnets
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

#################################
# Ingress Inspection VPC Routing
#################################

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
  # checkov:skip=CKV2_AWS_63: Firewall logging is defined in module see call above
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

#################################
# TGW attach inspection vpc
#################################

# Attach external_inspection_in subnets to the Modernisation Platform Transit Gateway
resource "aws_ec2_transit_gateway_vpc_attachment" "external_inspection_in" {

  transit_gateway_id = aws_ec2_transit_gateway.transit-gateway.id

  # Attach subnets to the Transit Gateway
  vpc_id = aws_vpc.external_inspection.id
  subnet_ids = [
    for subnet in aws_subnet.external_inspection_in :
    subnet.id
  ]

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  # Enable DNS support
  dns_support = "disable"

  # Turn off IPv6 support
  ipv6_support = "disable"

  # Enable appliance mode support
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


# VPC Flow Log: configure an IAM role
resource "aws_iam_role" "vpc_flow_log" {
  name               = "AWSVPCFlowLog"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_log_assume_role_policy.json
}

# VPC Flow Log: assume role policy
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

# VPC Flow Log: publish to CloudWatch
resource "aws_iam_policy" "vpc_flow_log_publish_policy" {
  name   = "AWSVPCFlowLogPublishPolicy"
  policy = data.aws_iam_policy_document.vpc_flow_log_publish_policy.json
}

# Extrapolated from:
# https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-cwl.html
# tfsec ignore appropriate as wildcard in line with AWS published guidance
# tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "vpc_flow_log_publish_policy" {

  #checkov:skip=CKV_AWS_111: "Ensure IAM policies does not allow write access without constraints - This is limited to the log actions only"
  #checkov:skip=CKV_AWS_356: "Ensure no IAM policies documents allow "*" as a statement's resource for restrictable actions - This is limited to the log actions only"
  #checkov:skip=CKV_AWS_111: "Ensure IAM policies does not allow write access without constraints"

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

# Role to allow ci/cd to update DNS records for ACM certificate validation
resource "aws_iam_role" "dns" {
  #checkov:skip=CKV_AWS_60:Wildcard constrained by condition checks
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

#tfsec:ignore:aws-iam-no-policy-wildcards
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

# Role to allow developer SSO user to read DNS records for ACM certificate validation for local plan
resource "aws_iam_role" "read_logs" {
  name = "read-log-records"
  assume_role_policy = jsonencode(
    # checkov:skip=CKV_AWS_60: "the policy is secured with the condition"
    # checkov:skip=CKV_AWS_355: "the policy is secured with the condition"
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

#tfsec:ignore:aws-iam-no-policy-wildcards
resource "aws_iam_role_policy" "read_dns" {
  # checkov:skip=CKV_AWS_355: "the policy is secured with the condition"
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


#tfsec:ignore:aws-iam-no-policy-wildcards
resource "aws_iam_role_policy" "read_firewall" {
  # checkov:skip=CKV_AWS_355: "the policy is secured with the condition"
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

# GitHub OIDC Role assumed by GitHub Actions workflows to perform VPN maintenance tasks

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
  # Custom VPC flow log statement
  custom_tgw_flow_log_format = "$${version} $${resource-type} $${account-id} $${tgw-id} $${tgw-attachment-id} $${tgw-src-vpc-account-id} $${tgw-dst-vpc-account-id} $${tgw-src-vpc-id} $${tgw-dst-vpc-id} $${tgw-src-subnet-id} $${tgw-dst-subnet-id} $${tgw-src-eni} $${tgw-dst-eni} $${tgw-src-az-id} $${tgw-dst-az-id} $${tgw-pair-attachment-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${log-status} $${type} $${packets-lost-no-route} $${packets-lost-blackhole} $${packets-lost-mtu-exceeded} $${packets-lost-ttl-expired} $${tcp-flags} $${region} $${flow-direction} $${pkt-src-aws-service} $${pkt-dst-aws-service}"
  custom_vpc_flow_log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr} $${region} $${az-id} $${sublocation-type} $${sublocation-id} $${pkt-src-aws-service} $${pkt-dst-aws-service} $${flow-direction} $${traffic-path}"
  environment_management     = jsondecode(data.aws_secretsmanager_secret_version.environment_management.secret_string)
  pagerduty_integration_keys = jsondecode(data.aws_secretsmanager_secret_version.pagerduty_integration_keys.secret_string)

  # This takes the name of the Terraform workspace (e.g. core-vpc-production), strips out the application name (e.g. core-vpc), and checks if
  # the string leftover is `-production`, if it isn't (e.g. core-vpc-non-production => -non-production) then it sets the var to false.
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

  sandbox_rules         = fileexists("./firewall-rules/sandbox_rules.json") ? { for k in sort(keys(jsondecode(templatefile("./firewall-rules/sandbox_rules.json", local.all_cidr_ranges)))) : k => jsondecode(templatefile("./firewall-rules/sandbox_rules.json", local.all_cidr_ranges))[k] } : {}
  development_rules     = fileexists("./firewall-rules/development_rules.json") ? { for k in sort(keys(jsondecode(templatefile("./firewall-rules/development_rules.json", local.all_cidr_ranges)))) : k => jsondecode(templatefile("./firewall-rules/development_rules.json", local.all_cidr_ranges))[k] } : {}
  test_rules            = fileexists("./firewall-rules/test_rules.json") ? { for k in sort(keys(jsondecode(templatefile("./firewall-rules/test_rules.json", local.all_cidr_ranges)))) : k => jsondecode(templatefile("./firewall-rules/test_rules.json", local.all_cidr_ranges))[k] } : {}
  preproduction_rules   = fileexists("./firewall-rules/preproduction_rules.json") ? { for k in sort(keys(jsondecode(templatefile("./firewall-rules/preproduction_rules.json", local.all_cidr_ranges)))) : k => jsondecode(templatefile("./firewall-rules/preproduction_rules.json", local.all_cidr_ranges))[k] } : {}
  production_rules      = fileexists("./firewall-rules/production_rules.json") ? { for k in sort(keys(jsondecode(templatefile("./firewall-rules/production_rules.json", local.all_cidr_ranges)))) : k => jsondecode(templatefile("./firewall-rules/production_rules.json", local.all_cidr_ranges))[k] } : {}
  live_data_rules       = fileexists("./firewall-rules/live_data_rules.json") ? { for k in sort(keys(jsondecode(templatefile("./firewall-rules/live_data_rules.json", local.all_cidr_ranges)))) : k => jsondecode(templatefile("./firewall-rules/live_data_rules.json", local.all_cidr_ranges))[k] } : {}
  non_live_data_rules   = fileexists("./firewall-rules/non_live_data_rules.json") ? { for k in sort(keys(jsondecode(templatefile("./firewall-rules/non_live_data_rules.json", local.all_cidr_ranges)))) : k => jsondecode(templatefile("./firewall-rules/non_live_data_rules.json", local.all_cidr_ranges))[k] } : {}
  fqdn_firewall_rules   = fileexists("./firewall-rules/fqdn_rules.json") ? jsondecode(file("./firewall-rules/fqdn_rules.json")) : {}
  inline_firewall_rules = fileexists("./firewall-rules/inline_rules.json") ? jsondecode(templatefile("./firewall-rules/inline_rules.json", local.all_cidr_ranges)) : {}


  firewall_rules = merge(
    local.sandbox_rules,
    local.development_rules,
    local.test_rules,
    local.preproduction_rules,
    local.production_rules,
    local.live_data_rules,
    local.non_live_data_rules
  )
  firewall_sets = fileexists("./firewall-rules/sets.json") ? jsondecode(templatefile("./firewall-rules/sets.json", local.all_cidr_ranges)) : {}

  vpn_attachments = fileexists("./vpn_attachments.json") ? jsondecode(file("./vpn_attachments.json")) : tomap({})

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
    if contains(keys(vpn), "github_environment") && vpn.github_environment != ""
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
    "172.16.10.0/24",
    "172.17.0.0/16",
    "172.18.0.0/15",
    "172.20.0.0/15",
    "172.22.0.0/15",
    "172.25.181.0/24",
    "195.59.116.244/32"
  ]

  parole_board_vpn_static_routes = ["10.50.0.0/16"]

  yjb_vpn_static_route_srx01 = ["10.20.228.0/22"]

  yjb_vpn_static_route_srx02 = ["10.20.224.0/22"]


  core-vpcs = {
    for file in fileset("../../../environments-networks", "*.json") :
    replace(file, ".json", "") => jsondecode(file("../../../environments-networks/${file}"))
  }

  # VPN Health Alerts - Notification Configuration
  # Filter VPN attachments that have notification settings
  vpns_with_notifications = {
    for name, cfg in local.vpn_attachments :
    name => cfg
    if(
      try(cfg.notification_slack_channel_id, "") != "" ||
      try(cfg.notification_email, "") != ""
    )
  }

  # Create maps using VPN names as keys for Slack notifications
  vpn_slack_notifications = {
    for name, cfg in local.vpns_with_notifications :
    name => cfg.notification_slack_channel_id
    if try(cfg.notification_slack_channel_id, "") != ""
  }

  # Create maps using VPN names as keys for Email notifications
  vpn_email_notifications = {
    for name, cfg in local.vpns_with_notifications :
    name => cfg.notification_email
    if try(cfg.notification_email, "") != ""
  }

  # Group VPNs by notification destination (for EventBridge rules that can handle multiple VPNs)
  vpns_by_slack_channel = {
    for channel_id in distinct([
      for name, cfg in local.vpns_with_notifications :
      cfg.notification_slack_channel_id
      if try(cfg.notification_slack_channel_id, "") != ""
    ]) :
    channel_id => [
      for name, cfg in local.vpns_with_notifications :
      name
      if try(cfg.notification_slack_channel_id, "") == channel_id
    ]
  }

  vpns_by_email = {
    for email in distinct([
      for name, cfg in local.vpns_with_notifications :
      cfg.notification_email
      if try(cfg.notification_email, "") != ""
    ]) :
    email => [
      for name, cfg in local.vpns_with_notifications :
      name
      if try(cfg.notification_email, "") == email
    ]
  }

  # Create EventBridge rule keys using first VPN name for each destination (one rule per destination)
  vpn_eventbridge_slack_rules = {
    for channel_id, vpn_list in local.vpns_by_slack_channel :
    vpn_list[0] => {
      channel_id = channel_id
      vpn_list   = vpn_list
    }
  }

  vpn_eventbridge_email_rules = {
    for email, vpn_list in local.vpns_by_email :
    vpn_list[0] => {
      email    = email
      vpn_list = vpn_list
    }
  }

  # Combine all VPN notification configs for unified policy handling
  all_vpn_health_notifications = merge(
    { for k, v in local.vpn_slack_notifications : "slack-${k}" => v },
    { for k, v in local.vpn_email_notifications : "email-${k}" => v }
  )

}


locals {
  resolver_query_log_config_names = toset(["core-logging-rlq-cloudwatch", "core-logging-rlq-s3"])
  vpc_ids                         = { for key, value in module.vpc_inspection : key => value["vpc_id"] if key == "live_data" }
  rlq_ids                         = { for name, config in data.aws_route53_resolver_query_log_config.core_logging : name => config.id }
  vpc_rlq_associations = merge([
    for vpc_key, vpc_id in local.vpc_ids : {
      for rlq_name, rlq_id in local.rlq_ids :
      "${vpc_key}_${rlq_name}" => {
        vpc_id = vpc_id
        rlq_id = rlq_id
      }
    }
  ]...)
}

data "aws_route53_resolver_query_log_config" "core_logging" {
  for_each = local.resolver_query_log_config_names
  filter {
    name   = "Name"
    values = [each.value]
  }
}

resource "aws_route53_resolver_query_log_config_association" "core_logging" {
  for_each                     = local.is-production ? local.vpc_rlq_associations : {}
  resolver_query_log_config_id = each.value.rlq_id
  resource_id                  = each.value.vpc_id
}

module "stream_firewall_logs" {
  source                     = "github.com/ministryofjustice/modernisation-platform-terraform-aws-data-firehose?ref=c350bc56f980cddededac981d1bfc8479da715e9" # v3.0.0
  cloudwatch_log_group_names = [module.vpc_inspection["live_data"].fw_cloudwatch_name, module.firewall_logging.cloudwatch_log_group_name]
  destination_http_endpoint  = data.aws_ssm_parameter.cortex_xsiam_endpoint.value
  tags                       = local.tags
  kms_key_enable_rotation    = true
  s3_bucket_logging_enabled  = true
  s3_bucket_logging_target   = module.stream_firewall_logs.s3_bucket_arn
  s3_bucket_logging_prefix   = "logs/"
  s3_encryption_type         = "aws:kms"
  s3_kms_key_arn             = aws_kms_key.environment_logging.arn
}


# Public DNS Query Logging
resource "aws_cloudwatch_log_group" "public_dns_query_logging" {
  provider          = aws.aws-us-east-1
  name              = "/aws/route53/core-public-dns-query-logging"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.public_dns_query_logging.arn
  tags              = local.tags
}

resource "aws_cloudwatch_log_resource_policy" "public_dns_query_logging" {
  provider    = aws.aws-us-east-1
  policy_name = "core-public-dns-query-logging"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRoute53ToPutLogs"
        Effect = "Allow"
        Principal = {
          Service = "route53.amazonaws.com"
        }
        Action = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = [
          aws_cloudwatch_log_group.public_dns_query_logging.arn,
          "${aws_cloudwatch_log_group.public_dns_query_logging.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_route53_query_log" "public_dns_query_logging" {
  provider                 = aws.aws-us-east-1
  for_each                 = aws_route53_zone.application_zones
  zone_id                  = each.value.zone_id
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.public_dns_query_logging.arn
}

resource "aws_kms_key" "public_dns_query_logging" {
  provider                = aws.aws-us-east-1
  description             = "KMS key for encrypting public DNS query logging CloudWatch log group"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags
}

resource "aws_kms_alias" "public_dns_query_logging" {
  provider      = aws.aws-us-east-1
  name          = "alias/public-dns-query-logging"
  target_key_id = aws_kms_key.public_dns_query_logging.id
}

resource "aws_kms_key_policy" "public_dns_query_logging" {
  provider = aws.aws-us-east-1
  key_id   = aws_kms_key.public_dns_query_logging.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Allow administration of the key"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs to use the key"
        Effect = "Allow"
        Principal = {
          Service = "logs.us-east-1.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:us-east-1:${local.environment_management.account_ids["core-network-services-production"]}:log-group:/aws/route53/core-public-dns-query-logging"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "cwl_to_core_logging" {
  provider = aws.aws-us-east-1
  name     = "${local.application_name}-cwl-to-core-logging"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "logs.us-east-1.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cwl_to_core_logging_policy" {
  provider = aws.aws-us-east-1
  name     = "${local.application_name}-cwl-to-core-logging-policy"
  role     = aws_iam_role.cwl_to_core_logging.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["logs:PutSubscriptionFilter"],
      Resource = "arn:aws:logs:us-east-1:${local.environment_management.account_ids["core-logging-production"]}:destination:r53-public-dns-logs-destination"
    }]
  })
}

resource "aws_cloudwatch_log_subscription_filter" "forward_to_core_logging" {
  provider        = aws.aws-us-east-1
  name            = "${local.application_name}-cwl-to-core-logging"
  log_group_name  = aws_cloudwatch_log_group.public_dns_query_logging.name
  filter_pattern  = ""
  destination_arn = "arn:aws:logs:us-east-1:${local.environment_management.account_ids["core-logging-production"]}:destination:r53-public-dns-logs-destination"
  role_arn        = aws_iam_role.cwl_to_core_logging.arn

  depends_on = [
    aws_cloudwatch_log_group.public_dns_query_logging,
    aws_iam_role_policy.cwl_to_core_logging_policy
  ]
}

# monitoring for aws config, cloudtrail, security hub
module "core_monitoring" {
  source                     = "../../modules/core-monitoring"
  pagerduty_integration_keys = local.pagerduty_integration_keys
}

# Route53 monitoring

# SNS topic for Route53 Hosted Zone DDoS monitoring
# tfsec:ignore:aws-sns-enable-topic-encryption
resource "aws_sns_topic" "route53_monitoring" {
  #checkov:skip=CKV_AWS_26:"encrypted topics do not work with pagerduty subscription"
  provider = aws.aws-us-east-1
  name     = "route53_monitoring"

  tags = local.tags
}

# subscribe to the sns topic to the pagerduty service
module "pagerduty_route53" {
  providers = {
    aws = aws.aws-us-east-1
  }
  depends_on = [
    aws_sns_topic.route53_monitoring
  ]
  source                    = "github.com/ministryofjustice/modernisation-platform-terraform-pagerduty-integration?ref=d88bd90d490268896670a898edfaba24bba2f8ab" # v3.0.0
  sns_topics                = [aws_sns_topic.route53_monitoring.name]
  pagerduty_integration_key = local.pagerduty_integration_keys["ddos_cloudwatch"]
}

module "pagerduty_transit_gateway_production" {
  depends_on = [
    aws_sns_topic.tgw_monitoring_production
  ]
  source                    = "github.com/ministryofjustice/modernisation-platform-terraform-pagerduty-integration?ref=d88bd90d490268896670a898edfaba24bba2f8ab" # v3.0.0
  sns_topics                = [aws_sns_topic.tgw_monitoring_production.name]
  pagerduty_integration_key = local.pagerduty_integration_keys["tgw_cloudwatch"]
}

# hosted zone DDoS monitoring
resource "aws_cloudwatch_metric_alarm" "ddos_attack_modernisation_platform_public_hosted_zone" {
  provider = aws.aws-us-east-1

  alarm_name          = "DDoSDetected-modernisation-platform-public-hosted-zone"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  datapoints_to_alarm = "1"
  evaluation_periods  = "20"
  metric_name         = "DDoSDetected"
  namespace           = "AWS/DDoSProtection"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alarm for DDoS events detected on resource ${aws_route53_zone.modernisation-platform.arn}"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.route53_monitoring.arn]
  dimensions = {
    ResourceArn = aws_route53_zone.modernisation-platform.arn
  }
  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "ddos_attack_application_public_hosted_zone" {
  for_each = aws_route53_zone.application_zones
  provider = aws.aws-us-east-1

  alarm_name          = "DDoSDetected-${each.value.tags.Name}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  datapoints_to_alarm = "1"
  evaluation_periods  = "20"
  metric_name         = "DDoSDetected"
  namespace           = "AWS/DDoSProtection"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alarm for DDoS events detected on resource ${each.value.arn}"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.route53_monitoring.arn]
  dimensions = {
    ResourceArn = each.value.arn
  }
  tags = local.tags
}

## Transit Gateway monitoring
data "aws_ec2_transit_gateway_peering_attachment" "transit_gateway_production" {
  for_each = toset(local.active_tgw_peering_attachments)
  filter {
    name   = "tag:Name"
    values = [each.key]
  }
}

data "aws_ec2_transit_gateway_vpc_attachment" "transit_gateway_production" {
  for_each = toset(local.active_tgw_vpc_attachments)
  filter {
    name   = "tag:Name"
    values = [each.key]
  }
}

resource "aws_cloudwatch_metric_alarm" "production_attachment_no_traffic_5_minutes" {
  for_each            = merge(data.aws_ec2_transit_gateway_vpc_attachment.transit_gateway_production, data.aws_ec2_transit_gateway_peering_attachment.transit_gateway_production)
  alarm_actions       = [aws_sns_topic.tgw_monitoring_production.arn]
  alarm_description   = format("Low traffic detected for VPC attachment %s", each.value.tags.Name)
  alarm_name          = format("NoVPCAttachmentTraffic-%s", each.value.tags.Name)
  comparison_operator = "LessThanOrEqualToThreshold"
  datapoints_to_alarm = "15"
  dimensions = {
    TransitGateway           = aws_ec2_transit_gateway.transit-gateway.id
    TransitGatewayAttachment = each.value["id"]
  }
  evaluation_periods = "15"
  metric_name        = "BytesIn"
  namespace          = "AWS/TransitGateway"
  period             = "60"
  statistic          = "Sum"
  threshold          = "1"
  treat_missing_data = "breaching"
  tags               = local.tags
}

# tfsec:ignore:aws-sns-enable-topic-encryption
resource "aws_sns_topic" "tgw_monitoring_production" {
  #checkov:skip=CKV_AWS_26:"encrypted topics do not work with pagerduty subscription"
  name = "tgw_monitoring_production"

  tags = local.tags
}

# TF sec exclusions
# - Ignore warnings regarding log groups not encrypted using customer-managed KMS keys - following cost/benefit discussion and longer term plans for logging solution
#tfsec:ignore:AWS089
resource "aws_cloudwatch_log_group" "tgw_flowlog_group" {
  name              = "tgw-flowlogs"
  retention_in_days = 365 # 0 = never expire
  kms_key_id        = aws_kms_key.environment_logging.arn
  tags = local.tags
}

resource "aws_flow_log" "tgw_flowlog" {
  depends_on                    = [aws_cloudwatch_log_group.tgw_flowlog_group]
  for_each                      = merge(data.aws_ec2_transit_gateway_vpc_attachment