# VPN Solution Deployment Guide

This guide provides step-by-step instructions for deploying the production-ready VPN solution.

## Prerequisites

### Required Tools

Install the following tools on your deployment machine:

```bash
# Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install terraform

# Ansible
sudo apt-get install ansible

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Docker (for local testing)
sudo apt-get install docker.io docker-compose

# Additional tools
sudo apt-get install jq curl git
```

### AWS Account Setup

1. **Create AWS Account**
   - Sign up for AWS account
   - Enable billing alerts
   - Set up MFA for root account

2. **Create IAM User for Deployment**
   ```bash
   # Create IAM user with programmatic access
   # Attach policies: EC2FullAccess, VPCFullAccess, IAMFullAccess, Route53FullAccess
   aws iam create-user --user-name vpn-deployer
   aws iam create-access-key --user-name vpn-deployer
   ```

3. **Configure AWS CLI**
   ```bash
   aws configure
   # Enter Access Key ID
   # Enter Secret Access Key
   # Default region: eu-west-1
   # Default output format: json
   ```

### Domain Setup (Optional)

If using custom domains:

1. **Register Domain**
   - Register domain through AWS Route53 or external provider
   - If external, create hosted zone in Route53

2. **Update DNS Settings**
   - Point domain to Route53 name servers
   - Verify DNS propagation

## Deployment Steps

### Step 1: Clone Repository

```bash
git clone <repository-url>
cd vpn-solution
```

### Step 2: Configure Variables

1. **Create Terraform Variables File**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit Configuration**
   ```bash
   # terraform/terraform.tfvars
   environment         = "production"
   aws_region         = "eu-west-1"
   domain_name        = "vpn.yourdomain.com"
   management_domain  = "mgmt.yourdomain.com"
   key_name          = "vpn-keypair"
   
   # Network Configuration
   vpc_cidr = "10.0.0.0/16"
   public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
   private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]
   
   # Security Configuration
   ssh_allowed_cidrs = ["YOUR_IP/32"]  # Replace with your IP
   management_allowed_cidrs = ["YOUR_IP/32"]  # Replace with your IP
   
   # Instance Configuration
   instance_type = "t3.medium"
   management_instance_type = "t3.small"
   min_size = 2
   max_size = 10
   desired_capacity = 2
   ```

### Step 3: Generate SSH Key Pair

```bash
# Create SSH key pair for EC2 instances
aws ec2 create-key-pair --key-name vpn-keypair --query 'KeyMaterial' --output text > ~/.ssh/vpn-keypair.pem
chmod 400 ~/.ssh/vpn-keypair.pem
```

### Step 4: Set up Terraform Backend

1. **Create S3 Bucket for State**
   ```bash
   aws s3 mb s3://your-terraform-state-bucket-unique-name
   
   # Enable versioning
   aws s3api put-bucket-versioning \
     --bucket your-terraform-state-bucket-unique-name \
     --versioning-configuration Status=Enabled
   
   # Enable encryption
   aws s3api put-bucket-encryption \
     --bucket your-terraform-state-bucket-unique-name \
     --server-side-encryption-configuration '{
       "Rules": [{
         "ApplyServerSideEncryptionByDefault": {
           "SSEAlgorithm": "AES256"
         }
       }]
     }'
   ```

2. **Update Backend Configuration**
   ```bash
   # Edit terraform/main.tf
   terraform {
     backend "s3" {
       bucket = "your-terraform-state-bucket-unique-name"
       key    = "vpn/terraform.tfstate"
       region = "eu-west-1"
     }
   }
   ```

### Step 5: Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -out=tfplan

# Review plan carefully
terraform show tfplan

# Apply configuration
terraform apply tfplan
```

**Expected deployment time:** 10-15 minutes

### Step 6: Configure Servers with Ansible

```bash
cd ../ansible

# Create inventory from Terraform outputs
terraform -chdir=../terraform output -json > ../terraform-outputs.json

# Generate Ansible inventory
cat > inventory/hosts.yml << EOF
all:
  children:
    management_servers:
      hosts:
        management:
          ansible_host: $(jq -r '.management_public_ip.value' ../terraform-outputs.json)
      vars:
        ansible_user: ubuntu
        ansible_ssh_private_key_file: ~/.ssh/vpn-keypair.pem
EOF

# Run Ansible playbook
ansible-playbook -i inventory/hosts.yml site.yml
```

**Expected configuration time:** 5-10 minutes

### Step 7: Verify Deployment

1. **Check Infrastructure Status**
   ```bash
   # Get deployment outputs
   cd terraform
   terraform output
   ```

2. **Test Management Interface**
   ```bash
   MGMT_URL=$(terraform output -raw management_interface_url)
   curl -k "$MGMT_URL/health"
   ```

3. **Test VPN Server**
   ```bash
   VPN_ENDPOINT=$(terraform output -raw wireguard_server_endpoint)
   nc -z -u $(echo $VPN_ENDPOINT | cut -d: -f1) $(echo $VPN_ENDPOINT | cut -d: -f2)
   ```

### Step 8: Access Management Interface

1. **Get Management URL**
   ```bash
   terraform output management_interface_url
   ```

2. **Access Web Interface**
   - Open URL in browser
   - Accept SSL certificate (if self-signed initially)
   - Login with demo credentials

3. **Create First VPN User**
   - Navigate to API documentation: `https://mgmt.yourdomain.com/api/docs`
   - Use authentication token: `demo-token`
   - Create test user via API

## Post-Deployment Configuration

### SSL Certificate Setup

If using custom domains, set up proper SSL certificates:

```bash
# SSH to management server
ssh -i ~/.ssh/vpn-keypair.pem ubuntu@$(terraform output -raw management_public_ip)

# Obtain SSL certificate
sudo certbot --nginx -d mgmt.yourdomain.com

# Set up auto-renewal
sudo crontab -e
# Add: 0 12 * * * /usr/bin/certbot renew --quiet
```

### Monitoring Setup

1. **Access Grafana**
   - URL: `https://mgmt.yourdomain.com/grafana`
   - Login: admin/admin123!
   - Change default password

2. **Configure Alerts**
   - Set up notification channels
   - Configure alert rules
   - Test alerting

### Security Hardening

1. **Update SSH Configuration**
   ```bash
   # Edit /etc/ssh/sshd_config
   PermitRootLogin no
   PasswordAuthentication no
   Port 2222  # Change default port
   ```

2. **Configure Fail2ban**
   ```bash
   # Review /etc/fail2ban/jail.local
   # Adjust ban times and retry limits
   sudo systemctl restart fail2ban
   ```

3. **Update Firewall Rules**
   ```bash
   # Restrict SSH access further if needed
   sudo ufw limit 2222/tcp
   ```

## Client Configuration

### Generate Client Configuration

1. **Via Management Interface**
   - Create user via web interface
   - Download configuration file
   - Generate QR code for mobile

2. **Via API**
   ```bash
   # Create user
   curl -X POST "https://mgmt.yourdomain.com/api/users" \
     -H "Authorization: Bearer demo-token" \
     -H "Content-Type: application/json" \
     -d '{
       "username": "testuser",
       "email": "test@example.com"
     }'
   
   # Get configuration
   curl -X GET "https://mgmt.yourdomain.com/api/users/{user_id}/config" \
     -H "Authorization: Bearer demo-token"
   ```

### Client Setup Examples

#### Linux Client
```bash
# Install WireGuard
sudo apt install wireguard

# Import configuration
sudo cp client.conf /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf

# Connect
sudo wg-quick up wg0

# Test connection
curl https://ipinfo.io/ip
```

#### Windows Client
1. Download WireGuard from official website
2. Import configuration file or scan QR code
3. Activate tunnel

#### Mobile Clients
1. Install WireGuard app from app store
2. Scan QR code or import configuration
3. Connect to VPN

## Scaling and Optimization

### Horizontal Scaling

To handle more users:

```bash
# Update Terraform variables
# terraform/terraform.tfvars
desired_capacity = 4
max_size = 20

# Apply changes
terraform plan
terraform apply
```

### Performance Optimization

1. **Instance Types**
   - Monitor CPU/memory usage
   - Upgrade instance types if needed
   - Consider dedicated instances for high-traffic

2. **Network Optimization**
   - Enable enhanced networking
   - Use placement groups
   - Optimize MTU settings

3. **Database Optimization**
   - Monitor connection pool usage
   - Implement read replicas if needed
   - Optimize queries

### Cost Optimization

1. **Reserved Instances**
   - Purchase reserved instances for predictable workloads
   - Consider savings plans

2. **Spot Instances**
   - Use spot instances for non-critical workloads
   - Implement proper handling for interruptions

3. **Resource Optimization**
   - Right-size instances based on utilization
   - Use CloudWatch metrics for decisions
   - Implement auto-scaling policies

## Backup and Disaster Recovery

### Automated Backups

```bash
# Create backup script
cat > /opt/backup-script.sh << 'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d)
BACKUP_DIR="/opt/backups/$DATE"
mkdir -p "$BACKUP_DIR"

# Configuration backup
tar -czf "$BACKUP_DIR/configs.tar.gz" /etc/wireguard/ /opt/vpn-management/config/

# Database backup
docker-compose -f /opt/vpn-management/docker-compose.yml exec -T db pg_dump -U postgres vpn_management > "$BACKUP_DIR/database.sql"

# Upload to S3
aws s3 sync /opt/backups/ s3://your-backup-bucket/
EOF

# Schedule backups
sudo crontab -e
# Add: 0 2 * * * /opt/backup-script.sh
```

### Disaster Recovery Plan

1. **Documentation**
   - Document all configurations
   - Maintain runbooks
   - Test recovery procedures

2. **Cross-Region Setup**
   - Consider multi-region deployment
   - Implement data replication
   - Plan failover procedures

## Troubleshooting Common Issues

### Deployment Failures

1. **Terraform Errors**
   ```bash
   # Check AWS credentials
   aws sts get-caller-identity
   
   # Verify permissions
   aws iam get-user
   
   # Check resource limits
   aws service-quotas list-service-quotas --service-code ec2
   ```

2. **Ansible Failures**
   ```bash
   # Test SSH connectivity
   ssh -i ~/.ssh/vpn-keypair.pem ubuntu@SERVER_IP
   
   # Run with verbose output
   ansible-playbook -i inventory/hosts.yml site.yml -vvv
   ```

### Runtime Issues

1. **VPN Connection Issues**
   ```bash
   # Check server status
   sudo wg show
   
   # Check firewall
   sudo ufw status
   
   # Test port connectivity
   nc -zu SERVER_IP 51820
   ```

2. **Management Interface Issues**
   ```bash
   # Check nginx status
   sudo systemctl status nginx
   
   # Check docker services
   docker-compose ps
   
   # Check logs
   docker-compose logs
   ```

## Security Considerations

### Production Security Checklist

- [ ] Change all default passwords
- [ ] Implement proper authentication
- [ ] Configure SSL certificates
- [ ] Set up monitoring and alerting
- [ ] Implement backup procedures
- [ ] Review firewall rules
- [ ] Enable audit logging
- [ ] Plan incident response

### Ongoing Security

1. **Regular Updates**
   - System package updates
   - Application updates
   - Security patches

2. **Monitoring**
   - Security event monitoring
   - Log analysis
   - Anomaly detection

3. **Access Review**
   - Regular access audits
   - User account review
   - Permission validation

## Maintenance

### Regular Maintenance Tasks

#### Daily
- Monitor system health
- Review security logs
- Check service status

#### Weekly
- Update packages
- Review user activity
- Check backup integrity

#### Monthly
- Security audit
- Performance review
- Capacity planning

#### Quarterly
- Disaster recovery testing
- Security assessment
- Documentation updates

### Upgrade Procedures

1. **Plan Upgrade**
   - Review changes
   - Test in staging
   - Schedule maintenance window

2. **Execute Upgrade**
   - Take backups
   - Apply updates
   - Verify functionality

3. **Post-Upgrade**
   - Monitor for issues
   - Validate all services
   - Document changes

## Support and Resources

### Documentation
- [Architecture Documentation](./architecture.md)
- [Security Audit Checklist](./security-audit.md)
- [Operator Runbook](./operator-runbook.md)

### Community Resources
- WireGuard Documentation: https://www.wireguard.com/
- Terraform AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/
- Ansible Documentation: https://docs.ansible.com/

### Professional Support
- Consider professional support for production deployments
- Engage security consultants for audits
- Plan for ongoing operational support

---

**Deployment Complete!** Your VPN solution should now be operational. Review the operator runbook for ongoing management procedures.