output "primary_ip" {
    value = aws_eip.management.public_ip
    description = "The public IP of the primary Panorama"
}

# I have to use the join because if I tried to access [0] and it isn't created then it errors out. Since there is only one management
# interface then the output will eithe be nothing or the IP of the second Panorama instance. If conditional output ever happen this 
# should be adjusted.
output "secondary_ip" {
    value = join(",", aws_eip.secondary_management[*].public_ip)
    description = "The public IP of the secondary Panorama"
}

output "primary_private_ip" {
    value = aws_network_interface.management.private_ip
    description = "The private IP of the primary Panorama"
}

# I have to use the join because if I tried to access [0] and it isn't created then it errors out. Since there is only one management
# interface then the output will eithe be nothing or the IP of the second Panorama instance. If conditional output ever happen this 
# should be adjusted.
output "secondary_private_ip" {
    value = join(",", aws_network_interface.secondary_management[*].private_ip)
    description = "The public IP of the secondary Panorama"
}

output "management_vpc_id" {
    value = aws_vpc.management-vpc.id
    description = "The VPC created to Panorama"
}

output "management_vpc_cidr" {
    value = aws_vpc.management-vpc.cidr_block
}

output "management_route_table" {
    value = aws_route_table.management_igw.id
}
