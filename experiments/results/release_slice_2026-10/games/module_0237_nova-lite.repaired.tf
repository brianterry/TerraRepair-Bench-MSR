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
#tfsec:ignore:AWS002 tfsec:ignore:aws-s3-block-public-acls tfsec:ignore:aws-s3-enable-bucket-encryption tfsec:ignore:aws-s3-enable-bucket-encryption tfsec:ignore:aws-s3-enable-versioning tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket" "acm-pca" {
  #checkov:skip=CKV_AWS_18:Ignore warnings regarding lack of s3 bucket server access logging - considered overkill given bucket purpose and restricted access to bucket
  #checkov:skip=CKV_AWS_144:Ignore lack of cross-regional replication - not required here - represents an overkill
  #checkov:skip=CKV2_AWS_41:As noted above, logging considered overkill given bucket purpose
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
  # e.g. `hmpps-development = "10.26.0.0/16"
  platform_general_set_cidr_ranges = {
    for key, value in local.core-vpcs : key => value.cidr.subnet_sets.general.cidr
  }

  # This will take the vpc CIDR ranges for each business/env general subnet set, from the environments-networks files
  # e.g. `hmpps-development = "10.26.0.0/16"
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
  #checkov:skip=CKV_AWS_158:Temporarily skip KMS encryption check while logging solution is being updated
  name              = "external-inspection-flow-logs"
  retention_in_days = 365 # 0 = never expire
  tags              = local.tags
}

resource "aws_s3_bucket_logging" "acm-pca" {
  bucket = aws_s3_bucket.acm-pca.id
  log_file_prefix = "logs/"
  server_access_logs {
    destination_bucket = aws_s3_bucket.acm-pca.id
    destination_prefix = "logs/access/"
  }
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

# Static code analysis ignores