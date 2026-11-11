```hcl
/*
Copyright 2022 The Kubernetes Authors.

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

resource "aws_s3_bucket" "registry-k8s-io" {
  bucket = "${var.prefix}registry-k8s-io-${data.aws_region.current.name}"

  # Block public ACLs
  block_public_acls = true

  # Block public policy
  block_public_policy = true

  # Enable server access logging
  server_access_logs {
    bucket = "logging-bucket-name"
    prefix = "logs/"
  }

  # Enable server access logging
  logging {
    target_bucket = "logging-bucket-name"
    target_prefix = "logs/"
  }

  # Enable server access logging
  access_logs_enabled = true

  # Enable server access logging
  access_logs_bucket = "logging-bucket-name"

  # Enable server access logging
  access_logs_prefix = "logs/"

  # Enable server access logging
  access_logs_target_acl = "bucket-owner-full-control"

  # Enable server access logging
  access_logs_target_kms_key_id = "kms-key-id"

  # Enable server access logging
  access_logs_target_storage_class = "STANDARD"

  # Enable server access logging
  access_logs_target_grant_read = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_write = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_list = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_delete = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_write_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_list_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_delete_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_write_acp_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_write_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_write_acp_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp_full_control_acp = "arn:aws:iam::123456789012:role/example-role"

  # Enable server access logging
  access_logs_target_grant_read_acp_full_control_write_acp_full_control_