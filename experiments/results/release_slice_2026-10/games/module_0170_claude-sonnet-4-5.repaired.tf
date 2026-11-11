data "aws_region" "current" {}

resource "random_id" "username" {
  keepers = {
    zone_id = "${var.zone_id}"
  }

  byte_length = 6
}

resource "aws_iam_role" "smtp_role" {
  name = "ses-smtp-${random_id.username.hex}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ses.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "smtp_policy" {
  name = "${aws_iam_role.smtp_role.name}-policy"
  role = "${aws_iam_role.smtp_role.name}"

  policy = <<EOF
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Effect":"Allow",
      "Action":[
        "ses:SendEmail",
        "ses:SendRawEmail"
      ],
      "Resource":"*",
      "Condition":{
        "StringLike":{
          "ses:FromAddress": "*@${var.domain}"
        }
      }
    }
  ]
}
EOF
}

resource "aws_ses_domain_identity" "identity" {
  domain = "${var.domain}"
}

resource "aws_ses_domain_dkim" "dkim" {
  domain = "${aws_ses_domain_identity.identity.domain}"
}

resource "aws_ses_domain_mail_from" "mail_from" {
  domain           = "${aws_ses_domain_identity.identity.domain}"
  mail_from_domain = "${var.mx_subdomain}.${aws_ses_domain_identity.identity.domain}"
}

resource "aws_route53_record" "ses_txt_record" {
  zone_id = "${var.zone_id}"
  name    = "_amazonses.${aws_ses_domain_identity.identity.domain}"
  type    = "TXT"
  ttl     = "600"
  records = ["${aws_ses_domain_identity.identity.verification_token}"]
}

resource "aws_route53_record" "mx_record" {
  zone_id = "${var.zone_id}"
  name    = "${aws_ses_domain_mail_from.mail_from.mail_from_domain}"
  type    = "MX"
  ttl     = "600"
  records = ["10 feedback-smtp.${data.aws_region.current.name}.amazonses.com"]
}

resource "aws_route53_record" "spf_record" {
  zone_id = "${var.zone_id}"
  name    = "${aws_ses_domain_mail_from.mail_from.mail_from_domain}"
  type    = "TXT"
  ttl     = "600"
  records = ["v=spf1 include:amazonses.com -all"]
}

resource "aws_route53_record" "dkim_record" {
  count   = 3
  zone_id = "${var.zone_id}"
  name    = "${element(aws_ses_domain_dkim.dkim.dkim_tokens, count.index)}._domainkey.${aws_ses_domain_identity.identity.domain}"
  type    = "CNAME"
  ttl     = "600"
  records = ["${element(aws_ses_domain_dkim.dkim.dkim_tokens, count.index)}.dkim.amazonses.com"]
}

output "smtp_server" {
  value = "email-smtp.${data.aws_region.current.name}.amazonaws.com"
}

output "smtp_username" {
  value = ""
}

output "smtp_password" {
  value = ""
}

variable "zone_id" {}

variable "domain" {}

variable "mx_subdomain" {
    default = "mx"
}