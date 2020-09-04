terraform {
  required_version = ">= 0.13, < 0.14"
}

variable vpc {}

variable subnets {}

variable public_subnets {}

variable device_group {}

variable public_zone {}

variable private_zone {}

variable interface_ips {}

variable public_interface {}

variable private_interface {}

variable log_profile {}

data "aws_ami" "latest_ecs" {
most_recent = true

owners = ["amazon"]

 filter {
   name   = "name"
   values = ["amzn2-ami-hvm*"]
 }
} 

resource "aws_security_group" "external-alb" {
  name        = "External ALB"
  description = "Allow inbound applications from the internet"
  vpc_id      = var.vpc
}

resource "aws_security_group_rule" "public" {
  security_group_id = aws_security_group.external-alb.id
  type              = "ingress"
  from_port         = 0
  to_port           = "80"
  protocol          = "TCP"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "public-outbound" {
  security_group_id = aws_security_group.external-alb.id
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
}

resource "aws_security_group" "internal-alb" {
  name        = "Internal ALB"
  description = "Allow inbound applications from the VM-Series"
  vpc_id      = var.vpc
}

resource "aws_security_group_rule" "private" {
  security_group_id = aws_security_group.internal-alb.id
  type              = "ingress"
  from_port         = 0
  to_port           = "80"
  protocol          = "TCP"
  cidr_blocks       = ["10.100.0.0/16"]
}

resource "aws_security_group_rule" "private-outbound" {
  security_group_id = aws_security_group.internal-alb.id
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
}

resource "aws_network_interface" "web-a" {
  subnet_id         = var.subnets[0]
  security_groups   = [aws_security_group.internal-alb.id]

  tags = {
    Name = "web-a"
  }
}

resource "aws_network_interface" "web-b" {
  subnet_id         = var.subnets[1]
  security_groups   = [aws_security_group.internal-alb.id]

  tags = {
    Name = "web-b"
  }
}

resource "aws_instance" "web-a" {
    ami           = data.aws_ami.latest_ecs.image_id
    instance_type = "t2.micro"
    user_data     = <<-EOF
                    #!/bin/bash
                    sudo su
                    yum -y install httpd
                    echo "<p> First Instance </p>" >> /var/www/html/index.html
                    sudo systemctl enable httpd
                    sudo systemctl start httpd
                    EOF
    network_interface {
        device_index         = 0
        network_interface_id = aws_network_interface.web-a.id
    }

    tags = {
        Name = "web-a"
    }
}

resource "aws_instance" "web-b" {
    ami           = data.aws_ami.latest_ecs.image_id
    instance_type = "t2.micro"
    user_data     = <<-EOF
                    #!/bin/bash
                    sudo su
                    yum -y install httpd
                    echo "<p> Second Instance </p>" >> /var/www/html/index.html
                    sudo systemctl enable httpd
                    sudo systemctl start httpd
                    EOF
    network_interface {
        device_index         = 0
        network_interface_id = aws_network_interface.web-b.id
    }

    tags = {
        Name = "web-b"
    }
}

resource "aws_lb_target_group" "internal" {
  name     = "web-servers"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc
}

resource "aws_lb_target_group_attachment" "web-a" {
  target_group_arn = aws_lb_target_group.internal.id
  target_id        = aws_instance.web-a.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "web-b" {
  target_group_arn = aws_lb_target_group.internal.id
  target_id        = aws_instance.web-b.id
  port             = 80
}

resource "aws_lb" "internal" {
  name               = "InternalApplication-ALB"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.internal-alb.id]
  subnets            = var.subnets

  enable_deletion_protection = false

  tags = {
    Environment = "production"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.internal.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal.id
  }
}

resource "panos_panorama_address_object" "internal_ALB" {
    name = "internal-ALB"
    device_group  = var.device_group
    type          = "fqdn"
    value         = aws_lb.internal.dns_name
}

resource "panos_panorama_nat_rule_group" "inbound" {
    device_group = var.device_group
    rule {
        name = "inbound-example-application"
        original_packet {
            source_zones          = [var.public_zone]
            destination_zone      = var.public_zone
            destination_interface = var.public_interface
            service               = "service-http"
            source_addresses      = ["any"]
            destination_addresses = ["any"]
        }
        translated_packet {
            source {
                dynamic_ip_and_port {
                    interface_address {
                        interface = var.private_interface
                    }
                }
            }
            destination {
                dynamic_translation {
                    address = panos_panorama_address_object.internal_ALB.name
                }
            }
        }
    }
}

resource "panos_panorama_security_rule_group" "inbound" {
    device_group     = var.device_group 
    position_keyword = "top"
    rule {
        name                  = "inbound-example-application"
        source_zones          = [var.public_zone] 
        source_addresses      = ["any"]
        source_users          = ["any"]
        hip_profiles          = ["any"]
        destination_zones     = [var.private_zone] 
        destination_addresses = ["any"]
        applications          = ["web-browsing"]
        services              = ["application-default"]
        categories            = ["any"]
        action                = "allow"
        log_setting           = var.log_profile 
    }
}

resource "aws_lb_target_group" "external" {
  name        = "vm-series"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc
}

resource "aws_lb_target_group_attachment" "vmseries-a" {
  target_group_arn = aws_lb_target_group.external.id
  target_id        = var.interface_ips[0] 
  port             = 80

}

resource "aws_lb_target_group_attachment" "vmseries-b" {
  target_group_arn = aws_lb_target_group.external.id
  target_id        = var.interface_ips[1]
  port             = 80

}

resource "aws_lb" "external" {
  name               = "ExternalApplication-ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.external-alb.id]
  subnets            = var.public_subnets

  enable_deletion_protection = false

  tags = {
    Environment = "production"
  }
}

resource "aws_lb_listener" "application" {
  load_balancer_arn = aws_lb.external.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.external.id
  }
}