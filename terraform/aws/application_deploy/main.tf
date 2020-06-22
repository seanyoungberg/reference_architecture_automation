provider "panos" {
  hostname = data.terraform_remote_state.singlevpc.outputs.panorama
  version = "~> 1.6"
}

terraform {
  required_version = ">= 0.12, < 0.13"
}

provider "aws" {
  region = var.aws_region
  version = "~> 2.53"
}

variable "aws_region" {}

data "terraform_remote_state" "singlevpc" {
  backend = "local"

  config = {
    path = "../singlevpc-deploy/terraform.tfstate"
  }
}

module "application" {
    source = "../modules/application/"
    vpc = data.terraform_remote_state.singlevpc.outputs.vpc
    subnets = data.terraform_remote_state.singlevpc.outputs.subnets
    public_subnets = data.terraform_remote_state.singlevpc.outputs.public_subnets
    device_group = data.terraform_remote_state.singlevpc.outputs.device_group
    public_zone = data.terraform_remote_state.singlevpc.outputs.public_zone
    private_zone = data.terraform_remote_state.singlevpc.outputs.private_zone
    interface_ips = data.terraform_remote_state.singlevpc.outputs.interface_ips
    public_interface = data.terraform_remote_state.singlevpc.outputs.public_interface
    private_interface = data.terraform_remote_state.singlevpc.outputs.private_interface
    log_profile = data.terraform_remote_state.singlevpc.outputs.log_profile
}

