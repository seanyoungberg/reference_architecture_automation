output "device_group" {
    value = panos_panorama_device_group.this.name
}

/*output "stack_a" {
    value = panos_panorama_template_stack.a.name
}

output "stack_b" {
    value = panos_panorama_template_stack.b.name
}*/

output "vpc" {
    value = aws_vpc.this.id
}

output "subnets" {
    value = [aws_subnet.app_subnet_primary.id, aws_subnet.app_subnet_secondary.id]
}

output "public_subnets" {
    value = [aws_subnet.public_subnet_primary.id, aws_subnet.public_subnet_secondary.id]
}

output "public_zone" {
    value = panos_panorama_zone.public.name
}

output "private_zone" {
    value = panos_panorama_zone.private.name
}
    
output "public_interface" {
    value = panos_panorama_ethernet_interface.public.name
}

output "private_interface" {
    value = panos_panorama_ethernet_interface.private.name
}

output "interface_ips" {
    value = [module.vmseries-a.public_interface_ip,module.vmseries-b.public_interface_ip]
}

output "log_profile" {
    value = panos_panorama_log_forwarding_profile.this.name
}

output "panorama" {
    value = data.terraform_remote_state.panorama.outputs.primary_eip
}