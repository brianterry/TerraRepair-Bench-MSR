resource "aws_cloudwatch_log_group" "dmesg" {
  name              = "${var.cloudwatch_prefix}/var/log/dmesg"
  retention_in_days = 365
  kms_key_id        = data.aws_kms_key.cloudwatch.arn
}

resource "aws_cloudwatch_log_group" "docker" {
  name              = "${var.cloudwatch_prefix}/var/log/docker"
  retention_in_days = 365
  kms_key_id        = data.aws_kms_key.cloudwatch.arn
}

resource "aws_cloudwatch_log_group" "ecs-agent" {
  name              = "${var.cloudwatch_prefix}/var/log/ecs/ecs-agent.log"
  retention_in_days = 365
  kms_key_id        = data.aws_kms_key.cloudwatch.arn
}

resource "aws_cloudwatch_log_group" "ecs-init" {
  name              = "${var.cloudwatch_prefix}/var/log/ecs/ecs-init.log"
  retention_in_days = 365
  kms_key_id        = data.aws_kms_key.cloudwatch.arn
}

resource "aws_cloudwatch_log_group" "audit" {
  name              = "${var.cloudwatch_prefix}/var/log/ecs/audit.log"
  retention_in_days = 365
  kms_key_id        = data.aws_kms_key.cloudwatch.arn
}

resource "aws_cloudwatch_log_group" "messages" {
  name              = "${var.cloudwatch_prefix}/var/log/messages"
  retention_in_days = 365
  kms_key_id        = data.aws_kms_key.cloudwatch.arn
}

data "aws_kms_key" "cloudwatch" {
  key_id = "alias/cloudwatch"
}

resource "aws_security_group_rule" "outbound_internet_access" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.instance.id
  description       = "Allow outbound HTTPS access"
}

resource "aws_launch_configuration" "launch" {
  name_prefix          = "${var.environment}_${var.cluster}_${var.instance_group}_"
  image_id             = var.aws_ami != "" ? var.aws_ami : data.aws_ami.latest_ecs_ami.image_id
  instance_type        = var.instance_type
  security_groups      = ["${aws_security_group.instance.id}"]
  user_data            = data.template_file.user_data.rendered
  iam_instance_profile = var.iam_instance_profile_id
  key_name             = var.key_name

  root_block_device {
    encrypted = true
  }

  metadata_options {
    http_tokens = "required"
  }

  lifecycle {
    create_before_destroy = true
  }
}