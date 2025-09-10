# Terraform Variables for VPN Solution

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "owner" {
  description = "Owner tag for resources"
  type        = string
  default     = "vpn-ops-team"
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

# WireGuard Configuration
variable "wireguard_port" {
  description = "UDP port for WireGuard"
  type        = number
  default     = 51820
}

variable "wireguard_network" {
  description = "Internal network for WireGuard clients"
  type        = string
  default     = "10.8.0.0/24"
}

# Security Configuration
variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict this in production
}

variable "management_allowed_cidrs" {
  description = "CIDR blocks allowed for management interface"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict this in production
}

# Instance Configuration
variable "instance_type" {
  description = "EC2 instance type for VPN servers"
  type        = string
  default     = "t3.medium"
}

variable "min_size" {
  description = "Minimum number of VPN servers"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of VPN servers"
  type        = number
  default     = 10
}

variable "desired_capacity" {
  description = "Desired number of VPN servers"
  type        = number
  default     = 2
}

# Management Instance Configuration
variable "management_instance_type" {
  description = "EC2 instance type for management server"
  type        = string
  default     = "t3.small"
}

# Key Management
variable "key_name" {
  description = "AWS key pair name for EC2 instances"
  type        = string
  default     = "vpn-keypair"
}

# Domain Configuration
variable "domain_name" {
  description = "Domain name for VPN service"
  type        = string
  default     = "vpn.example.com"
}

variable "management_domain" {
  description = "Domain name for management interface"
  type        = string
  default     = "vpn-mgmt.example.com"
}

# Monitoring Configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7 # Minimal for privacy
}

# Backup Configuration
variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7 # Minimal for privacy
}

# Cost Optimization
variable "enable_spot_instances" {
  description = "Use spot instances for cost optimization (non-production)"
  type        = bool
  default     = false
}

variable "spot_max_price" {
  description = "Maximum price for spot instances"
  type        = string
  default     = "0.05"
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}