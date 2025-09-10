# Terraform Outputs

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

# Load Balancer Outputs
output "wireguard_nlb_dns_name" {
  description = "DNS name of the WireGuard Network Load Balancer"
  value       = aws_lb.wireguard.dns_name
}

output "wireguard_nlb_zone_id" {
  description = "Zone ID of the WireGuard Network Load Balancer"
  value       = aws_lb.wireguard.zone_id
}

output "management_alb_dns_name" {
  description = "DNS name of the Management Application Load Balancer"
  value       = aws_lb.management.dns_name
}

output "management_alb_zone_id" {
  description = "Zone ID of the Management Application Load Balancer"
  value       = aws_lb.management.zone_id
}

# Instance Outputs
output "management_instance_id" {
  description = "ID of the management server instance"
  value       = aws_instance.management.id
}

output "management_public_ip" {
  description = "Public IP of the management server"
  value       = aws_eip.management.public_ip
}

output "management_private_ip" {
  description = "Private IP of the management server"
  value       = aws_instance.management.private_ip
}

# Auto Scaling Group Outputs
output "wireguard_asg_name" {
  description = "Name of the WireGuard Auto Scaling Group"
  value       = aws_autoscaling_group.wireguard.name
}

output "wireguard_asg_arn" {
  description = "ARN of the WireGuard Auto Scaling Group"
  value       = aws_autoscaling_group.wireguard.arn
}

# Security Group Outputs
output "wireguard_security_group_id" {
  description = "ID of the WireGuard security group"
  value       = aws_security_group.wireguard.id
}

output "management_security_group_id" {
  description = "ID of the management security group"
  value       = aws_security_group.management.id
}

# Certificate Outputs
output "management_certificate_arn" {
  description = "ARN of the management SSL certificate"
  value       = aws_acm_certificate.management.arn
}

# DNS Outputs (conditional)
output "management_domain_zone_id" {
  description = "Route53 zone ID for management domain"
  value       = var.domain_name != "vpn.example.com" ? aws_route53_zone.management[0].zone_id : null
}

output "management_domain_name_servers" {
  description = "Name servers for the management domain"
  value       = var.domain_name != "vpn.example.com" ? aws_route53_zone.management[0].name_servers : null
}

# Configuration Values for Client Setup
output "wireguard_server_endpoint" {
  description = "WireGuard server endpoint for client configuration"
  value       = "${aws_lb.wireguard.dns_name}:${var.wireguard_port}"
}

output "wireguard_network" {
  description = "WireGuard internal network CIDR"
  value       = var.wireguard_network
}

output "management_interface_url" {
  description = "URL for the management interface"
  value       = var.domain_name != "vpn.example.com" ? "https://${var.management_domain}" : "https://${aws_lb.management.dns_name}"
}

# Environment Information
output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# Access Information
output "ssh_connection_commands" {
  description = "SSH connection commands for instances"
  value = {
    management_server = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_eip.management.public_ip}"
  }
}

# Monitoring URLs
output "monitoring_urls" {
  description = "URLs for monitoring interfaces"
  value = {
    grafana    = var.domain_name != "vpn.example.com" ? "https://${var.management_domain}/grafana" : "https://${aws_lb.management.dns_name}/grafana"
    prometheus = var.domain_name != "vpn.example.com" ? "https://${var.management_domain}/prometheus" : "https://${aws_lb.management.dns_name}/prometheus"
    api_docs   = var.domain_name != "vpn.example.com" ? "https://${var.management_domain}/api/docs" : "https://${aws_lb.management.dns_name}/api/docs"
  }
}

# Cost Optimization Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    note = "Costs are estimates based on us-east-1 pricing and may vary by region"
    ec2_instances = {
      management_server = "~$15-30/month (t3.small)"
      wireguard_servers = "~$30-60/month (2x t3.medium)"
    }
    load_balancers = {
      network_lb = "~$16/month"
      application_lb = "~$22/month"
    }
    data_transfer = "Variable based on usage"
    storage = "~$5-10/month (EBS volumes)"
    total_estimated = "~$88-138/month (excluding data transfer)"
  }
}

# Security Information
output "security_notes" {
  description = "Important security configuration notes"
  value = {
    ssh_access = "Restrict var.ssh_allowed_cidrs to your IP ranges in production"
    management_access = "Restrict var.management_allowed_cidrs to admin IP ranges"
    ssl_certificates = "SSL certificates are automatically provisioned via Let's Encrypt"
    wireguard_keys = "Server keys are automatically generated and stored in SSM Parameter Store"
    firewall = "UFW firewall is automatically configured on all instances"
    fail2ban = "Fail2ban is enabled for intrusion prevention"
  }
}

# Troubleshooting Information
output "troubleshooting_info" {
  description = "Troubleshooting commands and log locations"
  value = {
    log_locations = {
      wireguard_setup = "/var/log/wireguard-setup.log"
      management_setup = "/var/log/management-setup.log"
      nginx_access = "/var/log/nginx/access.log"
      nginx_error = "/var/log/nginx/error.log"
    }
    useful_commands = {
      check_wireguard = "sudo wg show"
      check_services = "sudo systemctl status wg-quick@wg0"
      check_docker = "docker-compose -f /opt/vpn-management/docker-compose.yml ps"
      check_logs = "sudo journalctl -u wg-quick@wg0 -f"
    }
  }
}