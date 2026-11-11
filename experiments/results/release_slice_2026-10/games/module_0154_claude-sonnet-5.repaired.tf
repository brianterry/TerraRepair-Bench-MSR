provider "aws" {
  region = "eu-west-1"

  # Make it faster by skipping something
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true
}

data "aws_caller_identity" "current" {}

data "aws_organizations_organization" "this" {}

####################################################
# Lambda Function (building locally, storing on S3,
# set allowed triggers, set policies)
####################################################

module "lambda_function" {
  source = "../../"

  function_name          = "${random_pet.this.id}-lambda1"
  description            = "My awesome lambda function"
  handler                = "index.lambda_handler"
  runtime                = "python3.12"
  ephemeral_storage_size = 10240
  architectures          = ["x86_64"]
  publish                = true
  # recursive_loop       = "Allow"

  source_path = "${path.module}/../fixtures/python-app1"

  store_on_s3 = true
  s3_bucket   = module.s3_bucket.s3_bucket_id
  s3_prefix   = "lambda-builds/"

  s3_object_override_default_tags = true
  s3_object_tags = {
    S3ObjectName = "lambda1"
    Override     = "true"
  }

  artifacts_dir = "${path.root}/.terraform/lambda-builds/"

  layers = [
    module.lambda_layer_local.lambda_layer_arn,
    module.lambda_layer_s3.lambda_layer_arn,
  ]

  environment_variables = {
    Hello      = "World"
    Serverless = "Terraform"
  }

  cloudwatch_logs_log_group_class             = "INFREQUENT_ACCESS"
  cloudwatch_logs_deletion_protection_enabled = false

  role_path = "/tf-managed/"

  attach_dead_letter_policy = true
  dead_letter_target_arn    = aws_sqs_queue.dlq.arn

  allowed_triggers = {
    Config = {
      principal        = "config.amazonaws.com"
      principal_org_id = data.aws_organizations_organization.this.id
    }
    APIGatewayAny = {
      service    = "apigateway"
      source_arn = "arn:aws:execute-api:eu-west-1:${data.aws_caller_identity.current.account_id}:aqnku8akd0/*/*/*"
    },
    APIGatewayDevPost = {
      service    = "apigateway"
      source_arn = "arn:aws:execute-api:eu-west-1:${data.aws_caller_identity.current.account_id}:aqnku8akd0/dev/POST/*"
    },
    OneRule = {
      principal  = "events.amazonaws.com"
      source_arn = "arn:aws:events:eu-west-1:${data.aws_caller_identity.current.account_id}:rule/RunDaily"
    }
  }

  ######################
  # Lambda Function URL
  ######################
  create_lambda_function_url = true
  authorization_type         = "AWS_IAM"
  cors = {
    allow_credentials = true
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["date", "keep-alive"]
    expose_headers    = ["keep-alive", "date"]
    max_age           = 86400
  }
  invoke_mode = "RESPONSE_STREAM"

  ######################
  # Additional policies
  ######################

  assume_role_policy_statements = {
    account_root = {
      effect  = "Allow",
      actions = ["sts:AssumeRole"],
      principals = {
        account_principal = {
          type        = "AWS",
          identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
        }
      }
      condition = {
        stringequals_condition = {
          test     = "StringEquals"
          variable = "sts:ExternalId"
          values   = ["12345"]
        }
      }
    }
  }

  attach_policy_json = true
  policy_json        = <<-EOT
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "xray:GetSamplingStatisticSummaries"
                ],
                "Resource": ["*"]
            }
        ]
    }
  EOT

  attach_policy_jsons = true
  policy_jsons = [
    <<-EOT
      {
          "Version": "2012-10-17",
          "Statement": [
              {
                  "Effect": "Allow",
                  "Action": [
                      "xray:*"
                  ],
                  "Resource": ["*"]
              }
          ]
      }
    EOT
  ]
  number_of_policy_jsons = 1

  attach_policy = true
  policy        = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"

  attach_policies    = true
  policies           = ["arn:aws:iam::aws:policy/AWSXrayReadOnlyAccess"]
  number_of_policies = 1

  attach_policy_statements = true
  policy_statements = {
    dynamodb = {
      effect    = "Allow",
      actions   = ["dynamodb:BatchWriteItem"],
      resources = ["arn:aws:dynamodb:eu-west-1:052212379155:table/Test"]
    },
    s3_read = {
      effect    = "Deny",
      actions   = ["s3:HeadObject", "s3:GetObject"],
      resources = ["arn:aws:s3:::my-bucket/*"]
    }
  }

  timeouts = {
    create = "20m"
    update = "20m"
    delete = "20m"
  }

  function_tags = {
    Language = "python"
  }

  tags = {
    Module = "lambda1"
  }
}

##########################################################
# Lambda Function (deploying existing package from local)
##########################################################

module "lambda_function_existing_package_local" {
  source = "../../"

  function_name = "${random_pet.this.id}-lambda-existing-package-local"
  description   = "My awesome lambda function"
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  publish       = true

  create_package         = false
  local_existing_package = "${path.module}/../fixtures/python-zip/existing_package.zip"
  #  s3_existing_package = {
  #    bucket = "humane-bear-bucket"
  #    key = "builds/506df8bef5a4fb01883cce3673c9ff0ed88fb52e8583410e0cca7980a72211a0.zip"
  #    version_id = null
  #  }

  layers = [
    module.lambda_layer_local.lambda_layer_arn,
    module.lambda_layer_s3.lambda_layer_arn,
  ]
}

#################################
# Lambda Layer (storing locally)
#################################

module "lambda_layer_local" {
  source = "../../"

  create_layer = true

  layer_name               = "${random_pet.this.id}-layer-local"
  description              = "My amazing lambda layer (deployed from local)"
  compatible_runtimes      = ["python3.12"]
  compatible_architectures = ["arm64"]

  source_path = "${path.module}/../fixtures/python-app1"
}

####################################################
# Lambda Layer with package deploying externally
# (e.g., using separate CI/CD pipeline)
####################################################

module "lambda_layer_with_package_deploying_externally" {
  source = "../../"

  create_layer = true

  layer_name          = "${random_pet.this.id}-layer-local"
  description         = "My amazing lambda layer (deployed from local)"
  compatible_runtimes = ["python3.12"]

  create_package         = false
  local_existing_package = "../fixtures/python-zip/existing_package.zip"

  ignore_source_code_hash = true
}

###############################
# Lambda Layer (storing on S3)
###############################

module "lambda_layer_s3" {
  source = "../../"

  create_layer = true

  layer_name          = "${random_pet.this.id}-layer-s3"
  description         = "My amazing lambda layer (deployed from S3)"
  compatible_runtimes = ["python3.12"]

  source_path = "${path.module}/../fixtures/python-app1"

  store_on_s3 = true
  s3_bucket   = module.s3_bucket.s3_bucket_id
}

##############
# Lambda@Edge
##############

module "lambda_at_edge" {
  source = "../../"

  lambda_at_edge = true

  function_name = "${random_pet.this.id}-lambda-at-edge"
  description   = "My awesome lambda@edge function"
  handler       = "index.lambda_handler"
  runtime       = "python3.12"

  source_path = "${path.module}/../fixtures/python-app1"
  hash_extra  = "this string should be included in hash function to produce different filename for the same source" # this is also a build trigger if this changes

  tags = {
    Module = "lambda-at-edge"
  }
}

###############################################
# Lambda Function with provisioned concurrency
###############################################

module "lambda_with_provisioned_concurrency" {
  source = "../../"

  function_name = "${random_pet.this.id}-lambda-provisioned"
  handler       = "index.lambda_handler"
  runtime       = "python3.12"

  source_path = "${path.module}/../fixtures/python-app1"
  publish     = true

  hash_extra = "hash-extra-lambda-provisioned"

  provisioned_concurrent_executions = -1 # 2
}

###############################################
# Lambda Function with mixed trusted entities
###############################################

module "lambda_with_mixed_trusted_entities" {
  source = "../../"

  function_name = "${random_pet.this.id}-lambda-mixed-trusted-entities"
  handler       = "index.lambda_handler"
  runtime       = "python3.12"

  source_path = "${path.module}/../fixtures/python-app1"

  trusted_entities = [
    "appsync.amazonaws.com",
    {
      type = "AWS",
      identifiers = [
        "arn:aws:iam::307990089504:root",
      ]
    },
    {
      type = "Service",
      identifiers = [
        "codedeploy.amazonaws.com",
        "ecs.amazonaws.com"
      ]
    }
  ]
}

##############################
# Lambda Functions + for_each
##############################

module "lambda_function_for_each" {
  source = "../../"

  for_each = toset(["dev", "staging", "prod"])

  region = "us-east-1"

  function_name = "my-${each.value}"
  description   = "My awesome lambda function"
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  publish       = true

  create_package         = false
  local_existing_package = "${path.module}/../fixtures/python-zip/existing_package.zip"
}

####################################################
# Lambda Function with package deploying externally
# (e.g., using separate CI/CD pipeline)
####################################################

module "lambda_function_with_package_deploying_externally" {
  source = "../../"

  function_name = "${random_pet.this.id}-lambda-with-package-deploying-externally"
  handler       = "index.lambda_handler"
  runtime       = "python3.12"

  create_package         = false
  local_existing_package = "../fixtures/python-zip/existing_package.zip"

  ignore_source_code_hash = true
}

####################################################
# Lambda Function no create log group permission
####################################################

module "lambda_function_no_create_log_group_permission" {
  source = "../../"

  function_name = "${random_pet.this.id}-lambda-no-create-log-group-permission"
  handler       = "index.lambda_handler"
  runtime       = "python3.12"

  create_package         = false
  local_existing_package = "../fixtures/python-zip/existing_package.zip"

  attach_create_log_group_permission = false
}

####################################################
# Lambda Function with custom log group (existing)
####################################################

module "lambda_function_with_custom_log_group" {
  source = "../../"

  function_name = "${random_pet.this.id}-lambda-with-custom-log-group"
  handler       = "index.lambda_handler"
  runtime       = "python3.12"

  create_package         = false
  local_existing_package = "../fixtures/python-zip/existing_package.zip"

  use_existing_cloudwatch_log_group = true

  logging_log_group             = aws_cloudwatch_log_group.custom.name
  logging_log_format            = "JSON"
  logging_application_log_level = "INFO"
  logging_system_log_level      = "DEBUG"
}

####################################################################
# Lambda Function with custom log group (automatically provisioned)
####################################################################

module "lambda_function_with_custom_auto_log_group" {
  source = "../../"

  function_name = "${random_pet.this.id}-lambda-with-custom-auto-log-group"
  handler       = "index.lambda_handler"
  runtime       = "python3.12"

  create_package         = false
  local_existing_package = "../fixtures/python-zip/existing_package.zip"

  logging_log_group             = "/example-auto/${random_pet.this.id}"
  logging_log_format            = "JSON"
  logging_application_log_level = "INFO"
  logging_system_log_level      = "DEBUG"
}

###########
# Disabled
###########

module "disabled_lambda" {
  source = "../../"

  create = false
}

##################
# Extra resources
##################

resource "random_pet" "this" {
  length = 2
}

resource "aws_kms_key" "this" {
  description         = "CMK used to encrypt S3, SQS, and CloudWatch log data"
  enable_key_rotation = true
}

module "s3_bucket" {
  source = "github.com/terraform-aws-modules/terraform-aws-s3-bucket?ref=e3bffb24bd1d6b6b77f1a3b50c9d2c3d9b3d44a1"

  bucket_prefix = "${random_pet.this.id}-"
  force_destroy = true

  # S3 bucket-level Public Access Block configuration
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = {
    enabled = true
  }

  logging = {
    target_bucket = "${random_pet.this.id}-logs"
    target_prefix = "log/"
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.this.arn
      }
      bucket_key_enabled = true
    }
  }
}

resource "aws_sqs_queue" "dlq" {
  name              = random_pet.this.id
  kms_master_key_id = aws_kms_key.this.id
}

resource "aws_cloudwatch_log_group" "custom" {
  name              = "/example/${random_pet.this.id}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.this.arn
}


# Lambda Function
output "lambda_function_arn" {
  description = "The ARN of the Lambda Function"
  value       = module.lambda_function.lambda_function_arn
}

output "lambda_function_arn_static" {
  description = "The static ARN of the Lambda Function. Use this to avoid cycle errors between resources (e.g., Step Functions)"
  value       = module.lambda_function.lambda_function_arn_static
}

output "lambda_function_code_sha256" {
  description = "The base64-encoded representation of the source code package file"
  value       = module.lambda_function.lambda_function_code_sha256
}

output "lambda_function_invoke_arn" {
  description = "The Invoke ARN of the Lambda Function"
  value       = module.lambda_function.lambda_function_invoke_arn
}

output "lambda_function_name" {
  description = "The name of the Lambda Function"
  value       = module.lambda_function.lambda_function_name
}

output "lambda_function_qualified_arn" {
  description = "The ARN identifying your Lambda Function Version"
  value       = module.lambda_function.lambda_function_qualified_arn
}

output "lambda_function_qualified_invoke_arn" {
  description = "The Invoke ARN identifying your Lambda Function Version"
  value       = module.lambda_function.lambda_function_qualified_invoke_arn
}

output "lambda_function_version" {
  description = "Latest published version of Lambda Function"
  value       = module.lambda_function.lambda_function_version
}

output "lambda_function_last_modified" {
  description = "The date Lambda Function resource was last modified"
  value       = module.lambda_function.lambda_function_last_modified
}

output "lambda_function_kms_key_arn" {
  description = "The ARN for the KMS encryption key of Lambda Function"
  value       = module.lambda_function.lambda_function_kms_key_arn
}

output "lambda_function_source_code_hash" {
  description = "The user-defined hash of the source code package file"
  value       = module.lambda_function.lambda_function_source_code_hash
}

output "lambda_function_source_code_size" {
  description = "The size in bytes of the function .zip file"
  value       = module.lambda_function.lambda_function_source_code_size
}

# Lambda Function URL
output "lambda_function_url" {
  description = "The URL of the Lambda Function URL"
  value       = module.lambda_function.lambda_function_url
}

output "lambda_function_url_id" {
  description = "The Lambda Function URL generated id"
  value       = module.lambda_function.lambda_function_url_id
}

# Lambda Layer
output "lambda_layer_arn" {
  description = "The ARN of the Lambda Layer with version"
  value       = module.lambda_function.lambda_layer_arn
}

output "lambda_layer_layer_arn" {
  description = "The ARN of the Lambda Layer without version"
  value       = module.lambda_function.lambda_layer_layer_arn
}

output "lambda_layer_code_sha256" {
  description = "The base64-encoded representation of the Lambda Layer source code package file"
  value       = module.lambda_function.lambda_layer_code_sha256
}

output "lambda_layer_created_date" {
  description = "The date Lambda Layer resource was created"
  value       = module.lambda_function.lambda_layer_created_date
}

output "lambda_layer_source_code_hash" {
  description = "The user-defined hash of the Lambda Layer source code package file"
  value       = module.lambda_function.lambda_layer_source_code_hash
}

output "lambda_layer_source_code_size" {
  description = "The size in bytes of the Lambda Layer .zip file"
  value       = module.lambda_function.lambda_layer_source_code_size
}

output "lambda_layer_version" {
  description = "The Lambda Layer version"
  value       = module.lambda_function.lambda_layer_version
}

# IAM Role
output "lambda_role_arn" {
  description = "The ARN of the IAM role created for the Lambda Function"
  value       = module.lambda_function.lambda_role_arn
}

output "lambda_role_name" {
  description = "The name of the IAM role created for the Lambda Function"
  value       = module.lambda_function.lambda_role_name
}

# CloudWatch Log Group
output "lambda_cloudwatch_log_group_arn" {
  description = "The ARN of the Cloudwatch Log Group"
  value       = module.lambda_function.lambda_cloudwatch_log_group_arn
}

# Deployment package
output "local_filename" {
  description = "The filename of zip archive deployed (if deployment was from local)"
  value       = module.lambda_function.local_filename
}

output "s3_object" {
  description = "The map with S3 object data of zip archive deployed (if deployment was from S3)"
  value       = module.lambda_function.s3_object
}




terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 2.0"
    }
  }
}