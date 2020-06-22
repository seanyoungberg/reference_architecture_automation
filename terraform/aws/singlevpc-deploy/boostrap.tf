variable "authcode" {
}

variable "panorama_bootstrap_key" {
}

variable "bootstrap_s3bucket1_create" {
    default = "vmseries-a"
}

variable "bootstrap_s3bucket2_create" {
    default = "vmseries-b"
}

#************************************************************************************
# CREATE 2 S3 BUCKETS FOR FW1 & FW2
#************************************************************************************
resource "random_string" "randomstring" {
  length      = 25
  min_lower   = 15
  min_numeric = 10
  special     = false
}

resource "aws_s3_bucket" "vmseries-a" {
  bucket        = join("", list(var.bootstrap_s3bucket1_create, "-", random_string.randomstring.result))
  acl           = "private"
  force_destroy = true
}

resource "aws_s3_bucket" "vmseries-b" {
  bucket        = join("", list(var.bootstrap_s3bucket2_create, "-", random_string.randomstring.result))
  acl           = "private"
  force_destroy = true
}


#************************************************************************************
# CREATE FW1 DIRECTORIES & UPLOAD FILES FROM /bootstrap_files/fw1 DIRECTORY
#************************************************************************************
/*resource "aws_s3_bucket_object" "bootstrap_xml" {
  bucket = aws_s3_bucket.vmseries-a.id
  acl    = "private"
  key    = "config/bootstrap.xml"
  source = "/dev/null"
}*/

resource "aws_s3_bucket_object" "a-init-cft_txt" {
  bucket = aws_s3_bucket.vmseries-a.id
  acl    = "private"
  key    = "config/init-cfg.txt"
  content = <<-EOF
            type=dhcp-client
            panorama-server=${data.terraform_remote_state.panorama.outputs.primary_private_ip}
            panorama-server=${data.terraform_remote_state.panorama.outputs.secondary_private_ip}
            tplname=${panos_panorama_template_stack.a.name}
            dgname=${panos_panorama_device_group.this.name}
            hostname=${module.vmseries-a.instance_name}
            dns-primary=169.254.169.253
            vm-auth-key=${var.panorama_bootstrap_key}
            dhcp-accept-server-hostname=yes
            dhcp-accept-server-domain=yes
            EOF
}

resource "aws_s3_bucket_object" "a-software" {
  bucket = aws_s3_bucket.vmseries-a.id
  acl    = "private"
  key    = "software/"
  source = "/dev/null"
}

resource "aws_s3_bucket_object" "a-license" {
  bucket = aws_s3_bucket.vmseries-a.id
  acl    = "private"
  key    = "license/authcodes"
  content = var.authcode
}

resource "aws_s3_bucket_object" "a-content" {
  bucket = aws_s3_bucket.vmseries-a.id
  acl    = "private"
  key    = "content/"
  source = "/dev/null"
}


#************************************************************************************
# CREATE FW2 DIRECTORIES & UPLOAD FILES FROM /bootstrap_files/fw2 DIRECTORY
#************************************************************************************
resource "aws_s3_bucket_object" "b-init-cft_txt" {
  bucket = aws_s3_bucket.vmseries-b.id
  acl    = "private"
  key    = "config/init-cfg.txt"
  content = <<-EOF
            type=dhcp-client
            panorama-server=${data.terraform_remote_state.panorama.outputs.primary_private_ip}
            panorama-server=${data.terraform_remote_state.panorama.outputs.secondary_private_ip}
            tplname=${panos_panorama_template_stack.b.name}
            dgname=${panos_panorama_device_group.this.name}
            hostname=${module.vmseries-b.instance_name}
            dns-primary=169.254.169.253
            vm-auth-key=${var.panorama_bootstrap_key}
            dhcp-accept-server-hostname=yes
            dhcp-accept-server-domain=yes
            EOF
}

resource "aws_s3_bucket_object" "b-software" {
  bucket = aws_s3_bucket.vmseries-b.id
  acl    = "private"
  key    = "software/"
  source = "/dev/null"
}

resource "aws_s3_bucket_object" "b-license" {
  bucket = aws_s3_bucket.vmseries-b.id
  acl    = "private"
  key    = "license/authcodes"
  content = var.authcode
}

resource "aws_s3_bucket_object" "b-content" {
  bucket = aws_s3_bucket.vmseries-b.id
  acl    = "private"
  key    = "content/"
  source = "/dev/null"
}


#************************************************************************************
# CREATE & ASSIGN IAM ROLE, POLICY, & INSTANCE PROFILE
#************************************************************************************
resource "aws_iam_role" "bootstrap_role" {
  name = "vmsereis_bootstrap_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
      "Service": "ec2.amazonaws.com"
    },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "bootstrap_policy" {
  name = "vmseries_bootstrap_policy"
  role = aws_iam_role.bootstrap_role.id

  policy = <<EOF
{
  "Version" : "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${aws_s3_bucket.vmseries-a.id}"
    },
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${aws_s3_bucket.vmseries-a.id}/*"
    },
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${aws_s3_bucket.vmseries-b.id}"
    },
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${aws_s3_bucket.vmseries-b.id}/*"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "bootstrap_profile" {
  name = "vmseries_bootstrap_profile"
  role = aws_iam_role.bootstrap_role.name
  path = "/"
}