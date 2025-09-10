# Management Server Infrastructure
# Hosts the FastAPI management interface and monitoring stack

# Management Server Security Group
resource "aws_security_group" "management" {
  name_prefix = "${local.name_prefix}-mgmt-"
  vpc_id      = aws_vpc.main.id

  # HTTPS for management interface
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.management_allowed_cidrs
    description = "HTTPS management interface"
  }

  # HTTP redirect
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.management_allowed_cidrs
    description = "HTTP redirect to HTTPS"
  }

  # FastAPI application
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "FastAPI application"
  }

  # Prometheus
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Prometheus metrics"
  }

  # Grafana
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Grafana dashboard"
  }

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
    description = "SSH management"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-management-sg"
  })
}

# Management Server Instance
resource "aws_instance" "management" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.management_instance_type
  key_name      = var.key_name

  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.management.id]
  associate_public_ip_address = true

  user_data = base64encode(templatefile("${path.module}/templates/management-userdata.sh", {
    environment       = var.environment
    wireguard_network = var.wireguard_network
    domain_name       = var.management_domain
  }))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  monitoring = var.enable_detailed_monitoring

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-management"
    Role = "management-server"
  })
}

# Elastic IP for management server
resource "aws_eip" "management" {
  instance = aws_instance.management.id
  domain   = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-management-eip"
  })

  depends_on = [aws_internet_gateway.main]
}

# Application Load Balancer for management interface
resource "aws_lb" "management" {
  name               = "${local.name_prefix}-mgmt-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.management.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = var.environment == "production" ? true : false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mgmt-alb"
  })
}

# Target Group for management server
resource "aws_lb_target_group" "management" {
  name     = "${local.name_prefix}-mgmt-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mgmt-tg"
  })
}

# Target Group Attachment
resource "aws_lb_target_group_attachment" "management" {
  target_group_arn = aws_lb_target_group.management.arn
  target_id        = aws_instance.management.id
  port             = 80
}

# ALB Listener for HTTPS
resource "aws_lb_listener" "management_https" {
  load_balancer_arn = aws_lb.management.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.management.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.management.arn
  }
}

# ALB Listener for HTTP (redirect to HTTPS)
resource "aws_lb_listener" "management_http" {
  load_balancer_arn = aws_lb.management.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# SSL Certificate
resource "aws_acm_certificate" "management" {
  domain_name       = var.management_domain
  validation_method = "DNS"

  subject_alternative_names = [
    "*.${var.management_domain}"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mgmt-cert"
  })
}

# Route53 Zone (if managing DNS)
resource "aws_route53_zone" "management" {
  count = var.domain_name != "vpn.example.com" ? 1 : 0
  name  = var.management_domain

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mgmt-zone"
  })
}

# Route53 Record for management domain
resource "aws_route53_record" "management" {
  count   = var.domain_name != "vpn.example.com" ? 1 : 0
  zone_id = aws_route53_zone.management[0].zone_id
  name    = var.management_domain
  type    = "A"

  alias {
    name                   = aws_lb.management.dns_name
    zone_id                = aws_lb.management.zone_id
    evaluate_target_health = true
  }
}

# Route53 Record for certificate validation
resource "aws_route53_record" "management_cert_validation" {
  for_each = var.domain_name != "vpn.example.com" ? {
    for dvo in aws_acm_certificate.management.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.management[0].zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "management" {
  count                   = var.domain_name != "vpn.example.com" ? 1 : 0
  certificate_arn         = aws_acm_certificate.management.arn
  validation_record_fqdns = [for record in aws_route53_record.management_cert_validation : record.fqdn]
}