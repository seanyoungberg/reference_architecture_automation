terraform {
  required_version = ">= 0.12, < 0.13"
}

variable template {
}

variable vr {}

variable public {}

variable private {}

variable psk {}

variable id-a {}

variable id-b {}

variable as {}

variable privatezone {}

variable publiczone {}

variable dg {}

variable stacka {}

variable stackb {}

variable peer {}

locals {
  tunnela_subnet = "169.254.0.20/30"
  tunnelb_subnet = "169.254.0.24/30"
}

resource "panos_panorama_tunnel_interface" "this" {
    name = "tunnel.1"
    template = var.template
    static_ips = [panos_panorama_template_variable.tunnelip.name]
    comment = "VPN to on-premises NGFWs"
    mtu = 1427
}

resource "panos_panorama_virtual_router_entry" "this" {
    template = var.template
    virtual_router = var.vr
    interface = panos_panorama_tunnel_interface.this.name
}

resource "panos_panorama_zone" "this" {
    name = "vpn"
    template = var.template
    mode = "layer3"
    interfaces = [panos_panorama_tunnel_interface.this.name]
}

resource "panos_panorama_ike_crypto_profile" "this" {
    name = "NGFW-IKE"
    template = var.template
    dh_groups = ["group20"]
    authentications = ["sha512"]
    encryptions = ["aes-256-cbc"]
    lifetime_value = 8
    authentication_multiple = 3
}

resource "panos_panorama_ipsec_crypto_profile" "this" {
    name = "NGFW-IPSec"
    template = var.template
    authentications = ["sha512"]
    encryptions = ["aes-256-gcm"]
    dh_group = "group20"
    lifetime_type = "hours"
    lifetime_value = 1
}

resource "panos_panorama_ike_gateway" "this" {
    name = "NGFW-GW"
    template = var.template
    version = "ikev2-preferred"
    interface = var.public
    peer_ip_type = "ip"
    peer_ip_value = panos_panorama_template_variable.ikepeer.name
    pre_shared_key = var.psk
    local_id_type = "ipaddr"
    local_id_value = panos_panorama_template_variable.bgpid.name
    enable_nat_traversal = true
    nat_traversal_keep_alive = 10
    ikev1_exchange_mode = "main"
    ikev1_crypto_profile = panos_panorama_ike_crypto_profile.this.name
    enable_dead_peer_detection = true
    dead_peer_detection_interval = 10
    dead_peer_detection_retry = 3
    ikev2_crypto_profile = panos_panorama_ike_crypto_profile.this.name
    depends_on = [
    panos_panorama_template_variable.ikepeer,
  ]
}

resource "panos_panorama_template_variable" "tunnelip" {
    template = var.template
    name = "$myTunnel-Interface-IP"
    type = "ip-netmask"
    value = "None"
}

resource "panos_panorama_template_variable" "bgpid" {
    template = var.template
    name = "$myBGP-Router-ID"
    type = "ip-netmask"
    value = "None"
}

resource "panos_panorama_template_variable" "tunnelpeer" {
    template = var.template
    name = "$myTunnel-Interface-Peer"
    type = "ip-netmask"
    value = "None"
}

resource "panos_panorama_template_variable" "ikepeer" {
    template = var.template
    name = "$myIKE-Gateway-Peer"
    type = "ip-netmask"
    value = "None"
}

resource "panos_panorama_ipsec_tunnel" "this" {
    name = "NGFW-TUN"
    template = var.template
    tunnel_interface = panos_panorama_tunnel_interface.this.name
    anti_replay = true
    ak_ike_gateway = panos_panorama_ike_gateway.this.name
    ak_ipsec_crypto_profile = panos_panorama_ipsec_crypto_profile.this.name
    copy_tos = true
}

resource "panos_panorama_redistribution_profile_ipv4" "connected" {
    name = "connected"
    template = var.template
    virtual_router = var.vr
    priority = 10
    action = "redist"
    types = ["connect"]
    interfaces = [var.private]
}

resource "panos_panorama_redistribution_profile_ipv4" "static" {
    name = "static"
    template = var.template
    virtual_router = var.vr
    priority = 10
    action = "redist"
    types = ["static"]
    interfaces = [var.private]
}

resource "panos_panorama_bgp" "this" {
    template = var.template
    virtual_router = var.vr
    router_id = panos_panorama_template_variable.bgpid.name
    as_number = var.as
    install_route = true
    enable = true
}

resource "panos_panorama_bgp_redist_rule" "connected" {
    template = var.template
    virtual_router = panos_panorama_bgp.this.virtual_router
    route_table = "unicast"
    name = panos_panorama_redistribution_profile_ipv4.connected.name
}

resource "panos_panorama_bgp_redist_rule" "static" {
    template = var.template
    virtual_router = panos_panorama_bgp.this.virtual_router
    route_table = "unicast"
    name = panos_panorama_redistribution_profile_ipv4.static.name
}

resource "panos_panorama_bgp_peer_group" "this" {
    template = var.template
    virtual_router = panos_panorama_bgp.this.virtual_router
    name = "NGFWs"
    import_next_hop = "use-peer"
    export_next_hop = "use-self"
    remove_private_as = false
}

resource "panos_panorama_bgp_peer" "peer1" {
    template = var.template
    virtual_router = panos_panorama_bgp.this.virtual_router
    bgp_peer_group = panos_panorama_bgp_peer_group.this.name
    name = "NGFW-1"
    peer_as = "65001"
    local_address_interface = panos_panorama_tunnel_interface.this.name
    local_address_ip = panos_panorama_template_variable.tunnelip.name
    peer_address_ip = panos_panorama_template_variable.tunnelpeer.name
    keep_alive_interval = 10
    hold_time = 30
    enable_sender_side_loop_detection = true
}

resource "panos_panorama_nat_rule_group" "this" {
    device_group = var.dg
    rule {
        name = "inbound-vpn"
        original_packet {
            source_zones = [panos_panorama_zone.this.name]
            destination_zone = var.privatezone
            source_addresses = ["any"]
            destination_addresses = ["any"]
        }
        translated_packet {
            source {
                dynamic_ip_and_port {
                    interface_address {
                        interface = var.private
                    }
                }
            }
            destination {
            }
        }
    }
}

resource "panos_panorama_security_rule_group" "example" {
    device_group = var.dg
    position_keyword = "top"
    rule {
        name = "inbound-internet"
        source_zones = [var.publiczone]
        source_addresses = ["any"]
        source_users = ["any"]
        hip_profiles = ["any"]
        destination_zones = [var.publiczone]
        destination_addresses = ["any"]
        applications = ["ipsec-esp-udp","ike"]
        services = ["application-default"]
        categories = ["any"]
        action = "allow"
    }
    rule {
        name = "intrazone-vpn"
        source_zones = [panos_panorama_zone.this.name]
        source_addresses = ["any"]
        source_users = ["any"]
        hip_profiles = ["any"]
        destination_zones = [panos_panorama_zone.this.name]
        destination_addresses = ["any"]
        applications = ["bgp"]
        services = ["application-default"]
        categories = ["any"]
        action = "allow"
    }
    rule {
        name = "inbound-vpn"
        source_zones = [panos_panorama_zone.this.name]
        source_addresses = ["any"]
        source_users = ["any"]
        hip_profiles = ["any"]
        destination_zones = [var.privatezone]
        destination_addresses = ["any"]
        applications = ["ssh","web-browsing"]
        services = ["application-default"]
        categories = ["any"]
        action = "allow"
    }
}

resource "panos_panorama_template_variable" "tunnelip-a" {
    template_stack = var.stacka
    name = panos_panorama_template_variable.tunnelip.name
    type = panos_panorama_template_variable.tunnelip.type
    value = cidrhost(local.tunnela_subnet,1)
}

resource "panos_panorama_template_variable" "bgpid-a" {
    template_stack = var.stacka
    name = panos_panorama_template_variable.bgpid.name
    type = panos_panorama_template_variable.bgpid.type
    value = var.id-a
}

resource "panos_panorama_template_variable" "tunnelpeer-a" {
    template_stack = var.stacka
    name = panos_panorama_template_variable.tunnelpeer.name
    type = panos_panorama_template_variable.tunnelpeer.type
    value = cidrhost(local.tunnela_subnet,0)
}

resource "panos_panorama_template_variable" "ikepeer-a" {
    template_stack = var.stacka
    name = panos_panorama_template_variable.ikepeer.name
    type = panos_panorama_template_variable.ikepeer.type
    value = var.peer
}

resource "panos_panorama_template_variable" "tunnelip-b" {
    template_stack = var.stackb
    name = panos_panorama_template_variable.tunnelip.name
    type = panos_panorama_template_variable.tunnelip.type
    value = cidrhost(local.tunnelb_subnet,1)
}

resource "panos_panorama_template_variable" "bgpid-b" {
    template_stack = var.stackb
    name = panos_panorama_template_variable.bgpid.name
    type = panos_panorama_template_variable.bgpid.type
    value = var.id-b
}

resource "panos_panorama_template_variable" "tunnelpeer-b" {
    template_stack = var.stackb
    name = panos_panorama_template_variable.tunnelpeer.name
    type = panos_panorama_template_variable.tunnelpeer.type
    value = cidrhost(local.tunnelb_subnet,0)
}

resource "panos_panorama_template_variable" "ikepeer-b" {
    template_stack = var.stackb
    name = panos_panorama_template_variable.ikepeer.name
    type = panos_panorama_template_variable.ikepeer.type
    value = var.peer
}