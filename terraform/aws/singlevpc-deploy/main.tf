terraform {
  required_version = ">= 0.13, < 0.14"
}

provider "aws" {
  region = var.aws_region
  version = "~> 2.53"
}

variable deployment_name {
  description = "Name of the deployment. This name will prefix the resources so it is easy to determine which resources are part of this deployment."
  type = string
  default = ""
}

variable vpc_name {
  description = "Name of the VPC"
  type = string
  default = "Application"
}

variable aws_region {
  default = "us-west-2"
}

variable vpc_cidr_block {
  description = "CIDR block for the VPC"
  default = "10.100.0.0/16"
}

variable onprem_IPaddress {
  description = ""
}

variable ra_key {
  default = ""
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "terraform_remote_state" "panorama" {
  backend = "local"

  config = {
    path = "../panorama/terraform.tfstate"
  }
}

locals {
  availability_zones = data.aws_availability_zones.available.names
  a-block = cidrsubnet(aws_vpc.this.cidr_block, 1, 0)
  b-block = cidrsubnet(aws_vpc.this.cidr_block, 1, 1)
  name = "${var.deployment_name != "" ? "${var.deployment_name} ${var.vpc_name}" : var.vpc_name}"
  deployment_name = "${var.deployment_name != "" ? "${var.deployment_name} " : ""}"
  management_sg_rules = {
    ssh-from-on-prem = {
      type = "ingress"
      cidr_blocks = var.onprem_IPaddress
      protocol = "tcp"
      from_port = "22"
      to_port = "22"
    }
    https-from-on-prem = {
      type = "ingress"
      cidr_blocks = var.onprem_IPaddress
      protocol = "tcp"
      from_port = "443"
      to_port = "443"
    }
    egress = {
      type = "egress"
      cidr_blocks = "0.0.0.0/0"
      protocol = "-1"
      from_port = 0
      to_port = 0
    }
  }
  public_sg_rules = {
    ingress = {
      type = "ingress"
      cidr_blocks = "0.0.0.0/0"
      protocol = "-1"
      from_port = 0
      to_port = 0
    }
    egress = {
      type = "egress"
      cidr_blocks = "0.0.0.0/0"
      protocol = "-1"
      from_port = 0
      to_port = 0
    }
  }
  private_sg_rules = {
    ingress = {
      type = "ingress"
      cidr_blocks = aws_vpc.this.cidr_block
      protocol = "-1"
      from_port = 0
      to_port = 0
    }
    egress = {
      type = "egress"
      cidr_blocks = "0.0.0.0/0"
      protocol = "-1"
      from_port = 0
      to_port = 0
    }
  }
}

# Create a VPC for Panorama
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "${local.name} VPC"
  }
  enable_dns_hostnames = true
}

resource "aws_vpc_peering_connection" "mgmt" {
  peer_vpc_id   = data.terraform_remote_state.panorama.outputs.vpc
  vpc_id        = aws_vpc.this.id
  auto_accept = true
}

# This module figures out how many bits to add to get a /24. Also supports smaller subnets if the starting
# network is smaller than a /25. In that case it will divide it into two subnets.
module "newbits" {
  source = "../modules/subnetting/"
  cidr_block = local.a-block
}

# Create a subnet for the primary Panorama 
resource "aws_subnet" "public_subnet_primary" {
  vpc_id = aws_vpc.this.id
  availability_zone = local.availability_zones[0]
  # Define the subnet as the first subnet in the range
  cidr_block = cidrsubnet(local.a-block, module.newbits.newbits, 0)
  tags = {
    Name = "${local.deployment_name}public - ${local.availability_zones[0]}"
  }
}

resource "aws_subnet" "private_subnet_primary" {
  vpc_id = aws_vpc.this.id
  availability_zone = local.availability_zones[0]
  # Define the subnet as the first subnet in the range
  cidr_block = cidrsubnet(local.a-block, module.newbits.newbits, 1)
   tags = {
    Name = "${local.deployment_name}fw - ${local.availability_zones[0]}"
  }
}

resource "aws_subnet" "mgmt_subnet_primary" {
  vpc_id = aws_vpc.this.id
  availability_zone = local.availability_zones[0]
  # Define the subnet as the first subnet in the range
  cidr_block = cidrsubnet(local.a-block, module.newbits.newbits, 127)
   tags = {
    Name = "${local.deployment_name}mgmt - ${local.availability_zones[0]}"
  }
}

resource "aws_subnet" "public_subnet_secondary" {
  vpc_id = aws_vpc.this.id
  availability_zone = local.availability_zones[1]
  # Define the subnet as the first subnet in the range
  cidr_block = cidrsubnet(local.b-block, module.newbits.newbits, 0)
   tags = {
    Name = "${local.deployment_name}public - ${local.availability_zones[1]}"
  }
}

resource "aws_subnet" "private_subnet_secondary" {
  vpc_id = aws_vpc.this.id
  availability_zone = local.availability_zones[1]
  # Define the subnet as the first subnet in the range
  cidr_block = cidrsubnet(local.b-block, module.newbits.newbits, 1)
   tags = {
    Name = "${local.deployment_name}fw - ${local.availability_zones[1]}"
  }
}

resource "aws_subnet" "mgmt_subnet_secondary" {
  vpc_id = aws_vpc.this.id
  availability_zone = local.availability_zones[1]
  # Define the subnet as the first subnet in the range
  cidr_block = cidrsubnet(local.b-block, module.newbits.newbits, 127)
   tags = {
    Name = "${local.deployment_name}mgmt - ${local.availability_zones[1]}"
  }
}

resource "aws_subnet" "app_subnet_primary" {
  vpc_id = aws_vpc.this.id
  availability_zone = local.availability_zones[0]
  # Define the subnet as the first subnet in the range
  cidr_block = cidrsubnet(local.a-block, module.newbits.newbits, 2)
  tags = {
    Name = "${local.deployment_name}web - ${local.availability_zones[0]}"
  } 
}

resource "aws_subnet" "app_subnet_secondary" {
  vpc_id = aws_vpc.this.id
  availability_zone = local.availability_zones[1]
  # Define the subnet as the first subnet in the range
  cidr_block = cidrsubnet(local.b-block, module.newbits.newbits, 2)
   tags = {
    Name = "${local.deployment_name}web - ${local.availability_zones[1]}"
  }
}

resource "aws_subnet" "business_subnet_primary" {
  vpc_id = aws_vpc.this.id
  availability_zone = local.availability_zones[0]
  # Define the subnet as the first subnet in the range
  cidr_block = cidrsubnet(local.a-block, module.newbits.newbits, 3)
   tags = {
    Name = "${local.deployment_name}business - ${local.availability_zones[0]}"
  }
}

resource "aws_subnet" "business_subnet_secondary" {
  vpc_id = aws_vpc.this.id
  availability_zone = local.availability_zones[1]
  # Define the subnet as the first subnet in the range
  cidr_block = cidrsubnet(local.b-block, module.newbits.newbits, 3)
   tags = {
    Name = "${local.deployment_name}business - ${local.availability_zones[1]}"
  }
}

resource "aws_subnet" "db_subnet_primary" {
  vpc_id = aws_vpc.this.id
  availability_zone = local.availability_zones[0]
  # Define the subnet as the first subnet in the range
  cidr_block = cidrsubnet(local.a-block, module.newbits.newbits, 4)
   tags = {
    Name = "${local.deployment_name}db - ${local.availability_zones[0]}"
  }
}

resource "aws_subnet" "db_subnet_secondary" {
  vpc_id = aws_vpc.this.id
  availability_zone = local.availability_zones[1]
  # Define the subnet as the first subnet in the range
  cidr_block = cidrsubnet(local.b-block, module.newbits.newbits, 4)
   tags = {
    Name = "${local.deployment_name}db - ${local.availability_zones[1]}"
  }
}

# Create an IGW so Panorama can get to the Internet for updates and licensing
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name} IGW"
  }
}

# Create a new route table that will have a default route to the IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name} Public"
  }
}

resource "aws_route_table" "mgmt" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name} Mgmt"
  }
}

resource "aws_route_table" "private-a" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name} Private-a"
  }
}

resource "aws_route_table" "private-b" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name} Private-b"
  }
}

# Set the default route to point to the IGW
resource "aws_route" "public_default" {
  route_table_id = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.this.id
}

resource "aws_route" "mgmt_default" {
  route_table_id = aws_route_table.mgmt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.this.id
}

resource "aws_route" "to_panorama" {
  route_table_id = aws_route_table.mgmt.id
  destination_cidr_block = data.terraform_remote_state.panorama.outputs.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.mgmt.id
}

resource "aws_route" "from_panorama" {
  route_table_id = data.terraform_remote_state.panorama.outputs.mgmt_route_table
  destination_cidr_block = aws_vpc.this.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.mgmt.id
}

resource "aws_route_table_association" "management_primary" {
  subnet_id      = aws_subnet.mgmt_subnet_primary.id
  route_table_id = aws_route_table.mgmt.id
}

resource "aws_route_table_association" "management_secondary" {
  subnet_id      = aws_subnet.mgmt_subnet_secondary.id
  route_table_id = aws_route_table.mgmt.id
}

resource "aws_route_table_association" "public_primary" {
  subnet_id      = aws_subnet.public_subnet_primary.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_secondary" {
  subnet_id      = aws_subnet.public_subnet_secondary.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "web_primary" {
  subnet_id      = aws_subnet.app_subnet_primary.id
  route_table_id = aws_route_table.private-a.id
}

resource "aws_route_table_association" "business_primary" {
  subnet_id      = aws_subnet.business_subnet_primary.id
  route_table_id = aws_route_table.private-a.id
}

resource "aws_route_table_association" "db_primary" {
  subnet_id      = aws_subnet.db_subnet_primary.id
  route_table_id = aws_route_table.private-a.id
}

resource "aws_route_table_association" "web_secondary" {
  subnet_id      = aws_subnet.app_subnet_secondary.id
  route_table_id = aws_route_table.private-b.id
}

resource "aws_route_table_association" "business_secondary" {
  subnet_id      = aws_subnet.business_subnet_secondary.id
  route_table_id = aws_route_table.private-b.id
}

resource "aws_route_table_association" "db_secondary" {
  subnet_id      = aws_subnet.db_subnet_secondary.id
  route_table_id = aws_route_table.private-b.id
}

resource "aws_security_group" "public" {
  name = "${local.name} Firewall-Public"
  description = "Allow inbound applications from the internet"
  vpc_id = aws_vpc.this.id
}

resource "aws_security_group_rule" "public" {
  for_each = local.public_sg_rules
  security_group_id = aws_security_group.public.id
  type = each.value.type
  from_port = each.value.from_port
  to_port = each.value.to_port
  protocol = each.value.protocol
  cidr_blocks = [each.value.cidr_blocks]
}

resource "aws_security_group" "private" {
  name = "${local.name} Firewall-Private"
  description = "Allow inbound traffic to the firewalls private interfaces"
  vpc_id = aws_vpc.this.id
}

resource "aws_security_group_rule" "private" {
  for_each = local.private_sg_rules
  security_group_id = aws_security_group.private.id
  type = each.value.type
  from_port = each.value.from_port
  to_port = each.value.to_port
  protocol = each.value.protocol
  cidr_blocks = [each.value.cidr_blocks]
}

resource "aws_security_group" "mgmt" {
  name = "${local.name} Firewall-Mgmt"
  description = "Allow inbound management to the firewall"
  vpc_id = aws_vpc.this.id
}

resource "aws_security_group_rule" "mgmt" {
  for_each = local.management_sg_rules
  security_group_id = aws_security_group.mgmt.id
  type = each.value.type
  from_port = each.value.from_port
  to_port = each.value.to_port
  protocol = each.value.protocol
  cidr_blocks = [each.value.cidr_blocks]
}

resource "aws_security_group_rule" "from_vmseries" {
  security_group_id = data.terraform_remote_state.panorama.outputs.mgmt_sg
  type = "ingress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = [aws_vpc.this.cidr_block]
}

module "vmseries-a" {
  source = "../modules/vmseries/"
  instance_name = "vmseries-a"
  aws_key = data.terraform_remote_state.panorama.outputs.key_pair
  mgmt_security_group = aws_security_group.mgmt.id
  mgmt_subnet_id = aws_subnet.mgmt_subnet_primary.id
  mgmt_subnet_block = aws_subnet.mgmt_subnet_primary.cidr_block
  public_security_group = aws_security_group.public.id
  public_subnet_id = aws_subnet.public_subnet_primary.id
  public_subnet_block = aws_subnet.public_subnet_primary.cidr_block
  private_security_group = aws_security_group.private.id
  private_subnet_id = aws_subnet.private_subnet_primary.id
  private_subnet_block = aws_subnet.private_subnet_primary.cidr_block
  bootstrap_s3bucket = aws_s3_bucket.vmseries-a.id
  bootstrap_profile = aws_iam_instance_profile.bootstrap_profile.id
  private_route_table = aws_route_table.private-a.id
}

module "vmseries-b" {
  source = "../modules/vmseries/"
  instance_name = "vmseries-b"
  aws_key = data.terraform_remote_state.panorama.outputs.key_pair
  mgmt_security_group = aws_security_group.mgmt.id
  mgmt_subnet_id = aws_subnet.mgmt_subnet_secondary.id
  mgmt_subnet_block = aws_subnet.mgmt_subnet_secondary.cidr_block
  public_security_group = aws_security_group.public.id
  public_subnet_id = aws_subnet.public_subnet_secondary.id
  public_subnet_block = aws_subnet.public_subnet_secondary.cidr_block
  private_security_group = aws_security_group.private.id
  private_subnet_id = aws_subnet.private_subnet_secondary.id
  private_subnet_block = aws_subnet.private_subnet_secondary.cidr_block
  bootstrap_s3bucket = aws_s3_bucket.vmseries-b.id
  bootstrap_profile = aws_iam_instance_profile.bootstrap_profile.id
  private_route_table = aws_route_table.private-b.id
}