provider "panos" {
    hostname = data.terraform_remote_state.panorama.outputs.primary_eip
    #username = "admin"
    //logging = ["action", "send"]
}

variable vpn_psk {
}

variable vpn_as {
}

variable vpn_peer {
}

resource "panos_panorama_device_group" "this" {
    name = "AWS"
}

resource "panos_panorama_log_forwarding_profile" "this" {
    name = "Forward-to-Cortex-Data-Lake"
    device_group = panos_panorama_device_group.this.name
    enhanced_logging = true
    match_list {
        name = "traffic-enhanced-app-logging"
        log_type = "traffic"
        send_to_panorama = true
    }
    match_list {
        name = "threat-enhanced-app-logging"
        log_type = "threat"
        send_to_panorama = true
    }
    match_list {
        name = "wildfire-enhanced-app-logging"
        log_type = "wildfire"
        send_to_panorama = true
    }
    match_list {
        name = "url-enhanced-app-logging"
        log_type = "url"
        send_to_panorama = true
    }
    match_list {
        name = "data-enhanced-app-logging"
        log_type = "data"
        send_to_panorama = true
    }
    match_list {
        name = "tunnel-enhanced-app-logging"
        log_type = "tunnel"
        send_to_panorama = true
    }
    match_list {
        name = "auth-enhanced-app-logging"
        log_type = "auth"
        send_to_panorama = true
    }

}

resource "panos_panorama_nat_rule_group" "outbound" {
    device_group = panos_panorama_device_group.this.name
    rule {
        name = "outbound-internet"
        original_packet {
            source_zones = [panos_panorama_zone.private.name]
            destination_zone = panos_panorama_zone.public.name
            source_addresses = ["any"]
            destination_addresses = ["any"]
        }
        translated_packet {
            source {
                dynamic_ip_and_port {
                    interface_address {
                        interface = panos_panorama_ethernet_interface.public.name
                    }
                }
            }
            destination {
                }
            }
        }
}

resource "panos_panorama_security_rule_group" "outbound" {
    device_group = panos_panorama_device_group.this.name
    position_keyword = "top"
    rule {
        name = "outbound-interet"
        source_zones = [panos_panorama_zone.private.name]
        source_addresses = ["any"]
        source_users = ["any"]
        hip_profiles = ["any"]
        destination_zones = [panos_panorama_zone.public.name]
        destination_addresses = ["any"]
        applications = ["yum","ntp"]
        services = ["application-default"]
        categories = ["any"]
        action = "allow"
        log_setting = panos_panorama_log_forwarding_profile.this.name
    }
}

resource "panos_panorama_template" "baseline" {
    name = "Baseline-VMSeries-Settings"
}

resource "panos_panorama_template" "network" {
    name = "AWS Network-Settings"
}

resource "panos_panorama_template_stack" "a" {
    name = "AWS AZ-a-Stack"
    templates = [panos_panorama_template.baseline.name, panos_panorama_template.network.name]
}

resource "panos_panorama_template_stack" "b" {
    name = "AWS AZ-b-Stack"
    templates = [panos_panorama_template.baseline.name, panos_panorama_template.network.name]
}

resource "panos_panorama_virtual_router" "default" {
    name = "vr-default"
    template = panos_panorama_template.network.name
}

resource "panos_panorama_virtual_router_entry" "public" {
    template = panos_panorama_template.network.name
    virtual_router = panos_panorama_virtual_router.default.name
    interface = panos_panorama_ethernet_interface.public.name
}

resource "panos_panorama_virtual_router_entry" "private" {
    template = panos_panorama_template.network.name
    virtual_router = panos_panorama_virtual_router.default.name
    interface = panos_panorama_ethernet_interface.private.name
}


resource "panos_panorama_zone" "public" {
    name = "public"
    template = panos_panorama_template.network.name
    mode = "layer3"
    interfaces = [panos_panorama_ethernet_interface.public.name]
}

resource "panos_panorama_zone" "private" {
    name = "private"
    template = panos_panorama_template.network.name
    mode = "layer3"
    interfaces = [panos_panorama_ethernet_interface.private.name]
}

resource "panos_panorama_ethernet_interface" "public" {
    template = panos_panorama_template.network.name
    name = "ethernet1/1"
    mode = "layer3"
    enable_dhcp = true
    create_dhcp_default_route = true
}

resource "panos_panorama_ethernet_interface" "private" {
    template = panos_panorama_template.network.name
    name = "ethernet1/2"
    mode = "layer3"
    enable_dhcp = true
    create_dhcp_default_route = false
}

resource "panos_panorama_static_route_ipv4" "web-a-a" {
    name = "Web-a"
    virtual_router = panos_panorama_virtual_router.default.name
    template_stack = panos_panorama_template_stack.a.name
    destination = aws_subnet.app_subnet_primary.cidr_block
    interface = panos_panorama_ethernet_interface.private.name
    next_hop = cidrhost(aws_subnet.private_subnet_primary.cidr_block,1)
}
resource "panos_panorama_static_route_ipv4" "web-b-a" {
    name = "Web-b"
    virtual_router = panos_panorama_virtual_router.default.name
    template_stack = panos_panorama_template_stack.a.name
    destination = aws_subnet.app_subnet_secondary.cidr_block
    interface = panos_panorama_ethernet_interface.private.name
    next_hop = cidrhost(aws_subnet.private_subnet_primary.cidr_block,1)
}
resource "panos_panorama_static_route_ipv4" "db-a-a" {
    name = "DB-a"
    virtual_router = panos_panorama_virtual_router.default.name
    template_stack = panos_panorama_template_stack.a.name
    destination = aws_subnet.db_subnet_primary.cidr_block
    interface = panos_panorama_ethernet_interface.private.name
    next_hop = cidrhost(aws_subnet.private_subnet_primary.cidr_block,1)
}
resource "panos_panorama_static_route_ipv4" "db-b-a" {
    name = "DB-b"
    virtual_router = panos_panorama_virtual_router.default.name
    template_stack = panos_panorama_template_stack.a.name
    destination = aws_subnet.db_subnet_secondary.cidr_block
    interface = panos_panorama_ethernet_interface.private.name
    next_hop = cidrhost(aws_subnet.private_subnet_primary.cidr_block,1)
}
resource "panos_panorama_static_route_ipv4" "business-a-a" {
    name = "Business-a"
    virtual_router = panos_panorama_virtual_router.default.name
    template_stack = panos_panorama_template_stack.a.name
    destination = aws_subnet.business_subnet_primary.cidr_block
    interface = panos_panorama_ethernet_interface.private.name
    next_hop = cidrhost(aws_subnet.private_subnet_primary.cidr_block,1)
}
resource "panos_panorama_static_route_ipv4" "business-b-a" {
    name = "Business-b"
    virtual_router = panos_panorama_virtual_router.default.name
    template_stack = panos_panorama_template_stack.a.name
    destination = aws_subnet.business_subnet_secondary.cidr_block
    interface = panos_panorama_ethernet_interface.private.name
    next_hop = cidrhost(aws_subnet.private_subnet_primary.cidr_block,1)
}

# Define routes on the second stack
resource "panos_panorama_static_route_ipv4" "web-a-b" {
    name = "Web-a"
    virtual_router = panos_panorama_virtual_router.default.name
    template_stack = panos_panorama_template_stack.b.name
    destination = aws_subnet.app_subnet_primary.cidr_block
    interface = panos_panorama_ethernet_interface.private.name
    next_hop = cidrhost(aws_subnet.private_subnet_secondary.cidr_block,1)
}
resource "panos_panorama_static_route_ipv4" "web-b-b" {
    name = "Web-b"
    virtual_router = panos_panorama_virtual_router.default.name
    template_stack = panos_panorama_template_stack.b.name
    destination = aws_subnet.app_subnet_secondary.cidr_block
    interface = panos_panorama_ethernet_interface.private.name
    next_hop = cidrhost(aws_subnet.private_subnet_secondary.cidr_block,1)
}
resource "panos_panorama_static_route_ipv4" "db-a-b" {
    name = "DB-a"
    virtual_router = panos_panorama_virtual_router.default.name
    template_stack = panos_panorama_template_stack.b.name
    destination = aws_subnet.db_subnet_primary.cidr_block
    interface = panos_panorama_ethernet_interface.private.name
    next_hop = cidrhost(aws_subnet.private_subnet_secondary.cidr_block,1)
}
resource "panos_panorama_static_route_ipv4" "db-b-b" {
    name = "DB-b"
    virtual_router = panos_panorama_virtual_router.default.name
    template_stack = panos_panorama_template_stack.b.name
    destination = aws_subnet.db_subnet_secondary.cidr_block
    interface = panos_panorama_ethernet_interface.private.name
    next_hop = cidrhost(aws_subnet.private_subnet_secondary.cidr_block,1)
}
resource "panos_panorama_static_route_ipv4" "business-a-b" {
    name = "Business-a"
    virtual_router = panos_panorama_virtual_router.default.name
    template_stack = panos_panorama_template_stack.b.name
    destination = aws_subnet.business_subnet_primary.cidr_block
    interface = panos_panorama_ethernet_interface.private.name
    next_hop = cidrhost(aws_subnet.private_subnet_secondary.cidr_block,1)
}
resource "panos_panorama_static_route_ipv4" "business-b-b" {
    name = "Business-b"
    virtual_router = panos_panorama_virtual_router.default.name
    template_stack = panos_panorama_template_stack.b.name
    destination = aws_subnet.business_subnet_secondary.cidr_block
    interface = panos_panorama_ethernet_interface.private.name
    next_hop = cidrhost(aws_subnet.private_subnet_secondary.cidr_block,1)
}


module "vpn" {
    source = "../modules/vpn/"
    dg = panos_panorama_device_group.this.name
    template = panos_panorama_template.network.name
    vr = panos_panorama_virtual_router.default.name
    public = panos_panorama_ethernet_interface.public.name
    publiczone = panos_panorama_zone.public.name
    private = panos_panorama_ethernet_interface.private.name
    privatezone = panos_panorama_zone.private.name
    stacka = panos_panorama_template_stack.a.name
    stackb = panos_panorama_template_stack.b.name
    psk = var.vpn_psk
    id-a = module.vmseries-a.eip
    id-b = module.vmseries-b.eip
    peer = var.vpn_peer
    as = var.vpn_as
}

