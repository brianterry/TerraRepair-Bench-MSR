resource "aws_iam_account_password_policy" "main" {
  count = (var.password_policy_minimum_length || var.password_policy_no_lowercase_required || var.password_policy_no_numbers_required || var.password_policy_no_uppercase_required || var.password_policy_no_symbol_required || var.password_policy_reuse_enabled || var.password_policy_expiration_threshold)? 1 : 0

  minimum_password_length        =!var.password_policy_minimum_length ? 8 : 6
  require_lowercase_characters   = true
  require_numbers                = true
  require_uppercase_characters   = true
  require_symbols                = true
  password_reuse_prevention      =!var.password_policy_reuse_enabled? 5 : 0
  max_password_age = var.password_policy_expiration_threshold? 0 : 60
}

resource "aws_iam_policy" "policy" {
  count = var.admin_iam_policy? 1 : 0

  name_prefix = "wildcard_IAM_policy"
  path        = "/"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "admin_not_indicated_policy" {
  count = var.admin_not_indicated_policy? 1 : 0

  name  = "sadcloud_superuser_policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}