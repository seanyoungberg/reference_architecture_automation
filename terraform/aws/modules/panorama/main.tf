terraform {
  required_version = ">= 0.12, < 0.13"
}

variable name {
  description = "VPC name"
}

variable security_group {
  description = "Security group to apply to Panorama"
}

variable aws_region {}

variable availability_zones {}

variable aws_key {}

variable instance_type {
  description = "Instance type for Panorama"
  default = "m4.2xlarge"
}

variable panorama_version {
  description = "Mainline version for Panorama. Does not define a specific release number."
  default = "9.1"
}

variable enable_ha {
  description = "Should Panorama be deployed as a HA pair"
}

variable deployment_name {
  description = "Prefix for the resouce names."
}

variable vpc_cidr_block {
  description = "CIDR block for the management VPC"
}

locals {
  # Defining the name once and using it in multiple resouces later
  primary_name = "${var.deployment_name}Panorama-primary"
  secondary_name = "${var.deployment_name}Panorama-secondary"
  # The marketplace product code for all versions of Panorama
  product_code = "eclz7j04vu9lf8ont8ta3n17o"
}

# Find the image for Panorama
data "aws_ami" "panorama" {
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
    values = ["Panorama-AWS-${var.panorama_version}*"]
  }
}

# Create a VPC for Panorama
resource "aws_vpc" "management-vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "${var.name} VPC"
  }
  enable_dns_hostnames = true
}

# This module figures out how many bits to add to get a /24. Also supports smaller subnets if the starting
# network is smaller than a /25. In that case it will divide it into two subnets.
module "newbits" {
  source = "../subnetting/"
  cidr_block = aws_vpc.management-vpc.cidr_block
}

# Create a subnet for the primary Panorama 
resource "aws_subnet" "management_subnet_primary" {
  vpc_id = aws_vpc.management-vpc.id
  availability_zone = var.availability_zones[0]
  # Define the subnet as the first subnet in the range
  cidr_block = cidrsubnet(aws_vpc.management-vpc.cidr_block, module.newbits.newbits, 0)
   tags = {
    Name = "${var.name} - ${var.availability_zones[0]}"
  }
}

# Create an IGW so Panorama can get to the Internet for updates and licensing
resource "aws_internet_gateway" "management_igw" {
  vpc_id = aws_vpc.management-vpc.id

  tags = {
    Name = "${var.name} IGW"
  }
}

# Create a new route table that will have a default route to the IGW
resource "aws_route_table" "management_igw" {
  vpc_id = aws_vpc.management-vpc.id

  tags = {
    Name = "${var.name} IGW"
  }
}

# Set the default route to point to the IGW
resource "aws_route" "in_default" {
  route_table_id = aws_route_table.management_igw.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.management_igw.id
}

# Set the primary Panorama subnet to use the IGW route table
resource "aws_route_table_association" "management_igw_primary" {
  subnet_id      = aws_subnet.management_subnet_primary.id
  route_table_id = aws_route_table.management_igw.id
}

# Create an interface and set the internal IP to the 4th IP address in the subnet.
resource "aws_network_interface" "management" {
  subnet_id         = aws_subnet.management_subnet_primary.id
  private_ips       = [cidrhost(aws_subnet.management_subnet_primary.cidr_block,4)]
  security_groups   = [var.security_group]
  source_dest_check = true

  tags = {
    Name = local.primary_name
  }
}

# Create an external IP address and associate it to the management interface
resource "aws_eip" "management" {
  vpc               = true
  network_interface = aws_network_interface.management.id

  tags = {
    Name = local.primary_name
  }

  depends_on = [
    aws_instance.panorama,
  ]
}

resource "aws_instance" "panorama" {
  disable_api_termination              = false
  instance_initiated_shutdown_behavior = "stop"

  ebs_optimized = true
  ami           = data.aws_ami.panorama.image_id
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

    tags = {
    Name = local.primary_name
  }
}


# Everything below here is for the second Panorama. Since it is optional the resources use the enable_ha variable
# to determine if they should deploy.

# The subnet assumes that there are at least two availablity zones. 
resource "aws_subnet" "management_subnet_secondary" {
  count = var.enable_ha ? 1 : 0
  vpc_id = aws_vpc.management-vpc.id
  availability_zone = var.availability_zones[1]
  # Set the subnet to the second subnet in the range.  
  cidr_block = cidrsubnet(aws_vpc.management-vpc.cidr_block, module.newbits.newbits, 1)
   tags = {
    Name = "${var.name} - ${var.availability_zones[1]}"
  }
}

resource "aws_route_table_association" "management_igw_secondary" {
  count = var.enable_ha ? 1 : 0
  # Using [0] because the resource I am referencing was defined with a count statement. 
  subnet_id      = aws_subnet.management_subnet_secondary[0].id
  route_table_id = aws_route_table.management_igw.id
}

resource "aws_network_interface" "secondary_management" {
  count = var.enable_ha ? 1 : 0  
  subnet_id         =  aws_subnet.management_subnet_secondary[0].id
  # Set the IP to the fourth host address in the subnet. 
  private_ips       = [cidrhost(aws_subnet.management_subnet_secondary[0].cidr_block,4)]
  security_groups   = [var.security_group]
  source_dest_check = true

  tags = {
    Name = local.secondary_name
  }
}

resource "aws_eip" "secondary_management" {
  count = var.enable_ha ? 1 : 0
  vpc               = true
  network_interface = aws_network_interface.secondary_management[0].id

  tags = {
    Name = local.secondary_name
  }

  depends_on = [
    aws_instance.secondary_panorama,
  ]
}

resource "aws_instance" "secondary_panorama" {
  count = var.enable_ha ? 1 : 0
  disable_api_termination              = false
  instance_initiated_shutdown_behavior = "stop"

  ebs_optimized = true
  ami           = data.aws_ami.panorama.image_id
  instance_type = var.instance_type
  key_name      = var.aws_key

  monitoring = false

  # Setting this to true so that the disk is deleted when the instance is deleted. 
  root_block_device {
    delete_on_termination = "true"
  }

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.secondary_management[0].id
  }

    tags = {
    Name = local.secondary_name
  }
}

