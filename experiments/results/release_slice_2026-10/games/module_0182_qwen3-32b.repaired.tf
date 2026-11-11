resource "aws_cloudwatch_log_group" "dmesg" {
  name              = "${var.cloudwatch_prefix}/var/log/dmesg"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.log.key_id
}

resource "aws_cloudwatch_log_group" "docker" {
  name              = "${var.cloudwatch_prefix}/var/log/docker"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.log.key_id
}

resource "aws_cloudwatch_log_group" "ecs-agent" {
  name              = "${var.cloudwatch_prefix}/var/log/ecs/ecs-agent.log"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.log.key_id
}

resource "aws_cloudwatch_log_group" "ecs-init" {
  name              = "${var.cloudwatch_prefix}/var/log/ecs/ecs-init.log"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.log.key_id
}

resource "aws_cloudwatch_log_group" "audit" {
  name              = "${var.cloudwatch_prefix}/var/log/ecs/audit.log"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.log.key_id
}

resource "aws_cloudwatch_log_group" "messages" {
  name              = "${var.cloudwatch_prefix}/var/log/messages"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.log.key_id
}

resource "aws_kms_key" "log" {
  description = "KMS key for encrypting CloudWatch log groups"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Allow use of the key",
      "Effect": "Allow",
      "Principal": {
        "Service": "logs.amazonaws.com"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
}

data "aws_ami" "latest_ecs_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

resource "aws_security_group" "instance" {
  name        = "${var.environment}_${var.cluster}_${var.instance_group}"
  description = "Used in ${var.environment}"
  vpc_id      = var.vpc_id

  tags = {
    Environment   = var.environment
    Cluster       = var.cluster
    InstanceGroup = var.instance_group
  }
}

resource "aws_security_group_rule" "outbound_internet_access" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.instance.id
  description       = "Allow outbound internet access"
}

resource "aws_launch_configuration" "launch" {
  name_prefix          = "${var.environment}_${var.cluster}_${var.instance_group}_"
  image_id             = var.aws_ami != "" ? var.aws_ami : data.aws_ami.latest_ecs_ami.image_id
  instance_type        = var.instance_type
  security_groups      = ["${aws_security_group.instance.id}"]
  user_data            = data.template_file.user_data.rendered
  iam_instance_profile = var.iam_instance_profile_id
  key_name             = var.key_name
  metadata_options {
    http_token          = "required"
    http_put_response_hop_limit = 2
    http_endpoint       = "enabled"
  }

  block_device {
    device_name = "ephemeral0"
    no_device   = true
  }

  block_device {
    device_name = "/dev/xvda"
    ebs {
      encrypted = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "asg" {
  name                 = "${var.environment}_${var.cluster}_${var.instance_group}"
  max_size             = var.max_size
  min_size             = var.min_size
  desired_capacity     = var.desired_capacity
  force_delete         = true
  launch_configuration = aws_launch_configuration.launch.id
  vpc_zone_identifier  = var.private_subnet_ids
  load_balancers       = var.load_balancers

  tag {
    key                 = "Name"
    value               = "${var.environment}_ecs_${var.cluster}_${var.instance_group}"
    propagate_at_launch = "true"
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = "true"
  }

  tag {
    key                 = "Cluster"
    value               = var.cluster
    propagate_at_launch = "true"
  }

  tag {
    key                 = "InstanceGroup"
    value               = var.instance_group
    propagate_at_launch = "true"
  }

  tag {
    key                 = "DependsId"
    value               = var.depends_id
    propagate_at_launch = "false"
  }
}

data "template_file" "user_data" {
  template = "${file("${path.module}/templates/user_data.sh")}"

  vars = {
    ecs_config        = var.ecs_config
    ecs_logging       = var.ecs_logging
    cluster_name      = var.cluster
    env_name          = var.environment
    custom_userdata   = var.custom_userdata
    cloudwatch_prefix = var.cloudwatch_prefix
  }
}

output "ecs_instance_security_group_id" {
  value = aws_security_group.instance.id
}

variable "environment" {
  description = "The name of the environment"
}

variable "cloudwatch_prefix" {
  default     = ""
  description = "If you want to avoid cloudwatch collision or you don't want to merge all logs to one log group specify a prefix"
}

variable "cluster" {
  description = "The name of the cluster"
}

variable "instance_group" {
  default     = "default"
  description = "The name of the instances that you consider as a group"
}

variable "vpc_id" {
  description = "The VPC id"
}

variable "aws_ami" {
  description = "The AWS ami id to use"
}

variable "instance_type" {
  default     = "t2.micro"
  description = "AWS instance type to use"
}

variable "max_size" {
  default     = 1
  description = "Maximum size of the nodes in the cluster"
}

variable "min_size" {
  default     = 1
  description = "Minimum size of the nodes in the cluster"
}

variable "desired_capacity" {
  default     = 1
  description = "The desired capacity of the cluster"
}

variable "iam_instance_profile_id" {
  description = "The id of the instance profile that should be used for the instances"
}

variable "private_subnet_ids" {
  type        = list
  description = "The list of private subnets to place the instances in"
}

variable "load_balancers" {
  type        = list
  default     = []
  description = "The load balancers to couple to the instances. Only used when NOT using ALB"
}

variable "depends_id" {
  description = "Workaround to wait for the NAT gateway to finish before starting the instances"
}

variable "key_name" {
  description = "SSH key name to be used"
}

variable "custom_userdata" {
  default     = ""
  description = "Inject extra command in the instance template to be run on boot"
}

variable "ecs_config" {
  default     = "echo '' > /etc/ecs/ecs.config"
  description = "Specify ecs configuration or get it from S3. Example: aws s3 cp s3://some-bucket/ecs.config /etc/ecs/ecs.config"
}

variable "ecs_logging" {
  default     = "[\"json-file\",\"awslogs\"]"
  description = "Adding logging option to ECS that the Docker containers can use. It is possible to add fluentd as well"
}