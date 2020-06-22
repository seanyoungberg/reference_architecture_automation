terraform {
  required_version = ">= 0.12, < 0.13"
}

variable instance_type {
  description = "Instance type for VM-Series"
  default = "m4.2xlarge"
}

variable vmseries_version {
  description = "Mainline version for VM-Series. Does not define a specific release number."
  default = "9.1"
}

variable aws_key {
}

variable instance_name {
}

variable mgmt_security_group {
}

variable mgmt_subnet_id {
}

variable mgmt_subnet_block {
}

variable public_security_group {
}

variable public_subnet_id {
}

variable public_subnet_block {
}

variable private_security_group {
}

variable private_subnet_id {
}

variable private_subnet_block {
}

variable bootstrap_profile {
}

variable bootstrap_s3bucket {
}

variable private_route_table {
}


locals {
  # The marketplace product code for all BYOL versions of VM-Series
  product_code = "6njl1pau431dv1qxipg63mvah"
}

# Find the image for VM-Series
data "aws_ami" "vmseries" {
  most_recent = true
  owners = ["aws-marketplace"]
  filter {
    name   = "owner-alias"
    values = ["aws-marketplace"]
  }

  filter {
    name   = "product-code"
    values = [local.product_code]
  }

  filter {
    name   = "name"
    # Using the asterisc, this finds the latest release in the mainline version
    values = ["PA-VM-AWS-${var.vmseries_version}*"]
  }
}

resource "aws_network_interface" "management" {
  subnet_id         = var.mgmt_subnet_id
  private_ips       = [cidrhost(var.mgmt_subnet_block,10)]
  security_groups   = [var.mgmt_security_group]
  source_dest_check = true

  tags = {
    Name = "${var.instance_name}-mgmt"
  }
}

# Create an external IP address and associate it to the management interface
resource "aws_eip" "management" {
  vpc               = true
  network_interface = aws_network_interface.management.id

  tags = {
    Name = "${var.instance_name}-mgmt"
  }

  depends_on = [
    aws_instance.this,
  ]
}

resource "aws_network_interface" "public" {
  subnet_id         = var.public_subnet_id
  private_ips       = [cidrhost(var.public_subnet_block,10)]
  security_groups   = [var.public_security_group]
  source_dest_check = false

  tags = {
    Name = "${var.instance_name}-public"
  }
}

# Create an external IP address and associate it to the public interface
resource "aws_eip" "public" {
  vpc               = true
  network_interface = aws_network_interface.public.id

  tags = {
    Name = "${var.instance_name}-public"
  }

  depends_on = [
    aws_instance.this,
  ]
}

resource "aws_network_interface" "private" {
  subnet_id         = var.private_subnet_id
  private_ips       = [cidrhost(var.private_subnet_block,10)]
  security_groups   = [var.private_security_group]
  source_dest_check = false

  tags = {
    Name = "${var.instance_name}-private"
  }
}

resource "aws_route" "private_default" {
  route_table_id = var.private_route_table
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id = aws_network_interface.private.id
}

resource "aws_instance" "this" {
  disable_api_termination              = false
  instance_initiated_shutdown_behavior = "stop"
  iam_instance_profile                 = var.bootstrap_profile
  user_data                            = base64encode(join("", list("vmseries-bootstrap-aws-s3bucket=", var.bootstrap_s3bucket)))

  ebs_optimized = true
  ami           = data.aws_ami.vmseries.image_id
  instance_type = var.instance_type
  key_name      = var.aws_key

  monitoring = false

  root_block_device {
    delete_on_termination = "true"
  }

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.management.id
  }

  network_interface {
    device_index         = 1
    network_interface_id = aws_network_interface.public.id
  }
 
  network_interface {
    device_index         = 2
    network_interface_id = aws_network_interface.private.id
  }

    tags = {
    Name = var.instance_name
  }
}

output eip {
    value = aws_eip.public.public_ip
}

output instance_name {
    value = var.instance_name
}

output public_interface_ip {
  value = tolist(aws_network_interface.public.private_ips)[0]
}