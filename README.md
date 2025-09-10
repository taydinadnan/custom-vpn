# 🚀 How to Deploy Your VPN Solution

Here's exactly how to run and deploy your production-ready VPN solution:

## 📋 Prerequisites Setup

### 1. Install Required Tools

```bash
# Install Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install terraform

# Install Ansible
sudo apt-get install ansible

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Install additional tools
sudo apt-get install jq curl git docker.io
```

### 2. AWS Account Setup

```bash
# Configure AWS credentials
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key  
# Default region: eu-west-1
# Default output format: json

# Test AWS connection
aws sts get-caller-identity
```

### 3. Create SSH Key Pair

```bash
# Create SSH key for EC2 instances
aws ec2 create-key-pair --key-name vpn-keypair --query 'KeyMaterial' --output text > ~/.ssh/vpn-keypair.pem
chmod 400 ~/.ssh/vpn-keypair.pem
```

## ⚙️ Configuration Changes Required

### 1. Edit Terraform Variables

```bash
cd /app/vpn-solution/terraform
cp terraform.tfvars.example terraform.tfvars
```

**Edit `terraform.tfvars`** with your values:

```hcl
# REQUIRED CHANGES:
environment = "production"
aws_region  = "eu-west-1"  # Change to your preferred region

# REPLACE WITH YOUR DOMAINS (or keep defaults for testing)
domain_name       = "vpn.yourdomain.com"        # Your VPN domain
management_domain = "mgmt.yourdomain.com"       # Management interface domain

# SECURITY - CRITICAL: Replace with your actual IP addresses
ssh_allowed_cidrs        = ["YOUR_IP_ADDRESS/32"]     # Your IP only!
management_allowed_cidrs = ["YOUR_IP_ADDRESS/32"]     # Your IP only!

# SSH Key (created above)
key_name = "vpn-keypair"

# Optional: Adjust instance sizes for cost
instance_type            = "t3.medium"    # VPN servers
management_instance_type = "t3.small"     # Management server
```

**To find your IP address:**
```bash
curl https://ipinfo.io/ip
# Use this IP in the terraform.tfvars file above
```

### 2. Set Up Terraform Backend (Optional but Recommended)

```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://your-vpn-terraform-state-$(date +%s)

# Edit terraform/main.tf and update the backend bucket name:
# backend "s3" {
#   bucket = "your-vpn-terraform-state-xxxxx"  # Use your bucket name
#   key    = "vpn/terraform.tfstate"
#   region = "eu-west-1"
# }
```

## 🚀 Deployment Options

### Option 1: One-Command Deployment (Recommended)

```bash
cd /app/vpn-solution

# Set environment variables
export DOMAIN_NAME="vpn.yourdomain.com"
export MANAGEMENT_DOMAIN="mgmt.yourdomain.com"
export ENVIRONMENT="production"

# Run complete deployment
./scripts/provision.sh
```

### Option 2: Step-by-Step Deployment

```bash
cd /app/vpn-solution

# 1. Deploy infrastructure
cd terraform
terraform init
terraform plan    # Review what will be created
terraform apply   # Type 'yes' to confirm

# 2. Configure servers (wait for infrastructure to be ready)
cd ../ansible
# Create inventory from terraform outputs
terraform -chdir=../terraform output -json > ../terraform-outputs.json

# Generate inventory file
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

# Run Ansible configuration
ansible-playbook -i inventory/hosts.yml site.yml

# 3. Test deployment
cd ../scripts
./integration-tests.sh production
```

## 🔍 Verify Deployment

### 1. Check Infrastructure

```bash
cd /app/vpn-solution/terraform
terraform output
```

You should see outputs like:
```
management_interface_url = "https://mgmt.yourdomain.com"
wireguard_server_endpoint = "vpn-nlb-xxxxx.elb.eu-west-1.amazonaws.com:51820"
management_public_ip = "xx.xx.xx.xx"
```

### 2. Test Management Interface

```bash
# Get management URL
MGMT_URL=$(terraform output -raw management_interface_url)

# Test health endpoint
curl -k "$MGMT_URL/health"
# Should return: {"status":"healthy","timestamp":"..."}

# Access web interface
echo "Management Interface: $MGMT_URL"
echo "API Documentation: $MGMT_URL/api/docs"
echo "Monitoring: $MGMT_URL/grafana"
```

### 3. Test VPN Server

```bash
# Test VPN port
VPN_ENDPOINT=$(terraform output -raw wireguard_server_endpoint)
VPN_HOST=$(echo $VPN_ENDPOINT | cut -d: -f1)
VPN_PORT=$(echo $VPN_ENDPOINT | cut -d: -f2)

nc -z -u $VPN_HOST $VPN_PORT
echo "VPN server test: $?"  # Should be 0 for success
```

## 👤 Create Your First VPN User

### Via Web Interface

1. Open: `https://mgmt.yourdomain.com/api/docs`
2. Click "Authorize" and enter token: `demo-token`
3. Use POST `/users` endpoint to create a user:
   ```json
   {
     "username": "testuser",
     "email": "test@example.com"
   }
   ```
4. Get configuration via GET `/users/{user_id}/config`

### Via Command Line

```bash
# Create user
curl -X POST "$MGMT_URL/api/users" \
  -H "Authorization: Bearer demo-token" \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","email":"test@example.com"}'

# List users to get ID
curl -X GET "$MGMT_URL/api/users" \
  -H "Authorization: Bearer demo-token"

# Get configuration (replace USER_ID)
curl -X GET "$MGMT_URL/api/users/USER_ID/config" \
  -H "Authorization: Bearer demo-token"
```

## 📱 Connect VPN Clients

### Linux Client
```bash
cd /app/vpn-solution/client-configs/linux
./setup.sh install
./setup.sh import your-config.conf myvpn
./setup.sh connect myvpn
```

### Windows Client
1. Run `/app/vpn-solution/client-configs/windows/setup.bat` as Administrator
2. Choose option 1 to install WireGuard
3. Import your configuration file

### Mobile Clients
- **iOS**: Follow guide in `/app/vpn-solution/client-configs/mobile/ios-setup.md`
- **Android**: Follow guide in `/app/vpn-solution/client-configs/mobile/android-setup.md`

## 🔒 Important Security Changes

### 1. Change Default Authentication

**Edit the management server FastAPI app:**

```bash
# SSH to management server
ssh -i ~/.ssh/vpn-keypair.pem ubuntu@$(terraform output -raw management_public_ip)

# Update API authentication in /opt/vpn-management/app/main.py
# Replace "demo-token" with a secure token
```

### 2. Restrict Access IPs

Make sure you updated `terraform.tfvars` with your actual IP addresses:
```hcl
ssh_allowed_cidrs        = ["YOUR.IP.ADDRESS/32"]
management_allowed_cidrs = ["YOUR.IP.ADDRESS/32"]
```

### 3. Set Up SSL Certificates (If Using Custom Domains)

```bash
# SSH to management server
ssh -i ~/.ssh/vpn-keypair.pem ubuntu@MANAGEMENT_IP

# Get SSL certificate
sudo certbot --nginx -d mgmt.yourdomain.com

# Set up auto-renewal
sudo crontab -e
# Add: 0 12 * * * /usr/bin/certbot renew --quiet
```

## 📊 Access Monitoring

1. **Grafana Dashboard**: `https://mgmt.yourdomain.com/grafana`
   - Login: admin / admin123!
   - Change password on first login

2. **Prometheus Metrics**: `https://mgmt.yourdomain.com/prometheus`
   - Login: admin / admin (basic auth)

3. **API Documentation**: `https://mgmt.yourdomain.com/api/docs`

## 💰 Cost Estimate

Your running costs will be approximately:
- **Monthly**: $93-128 USD (2 VPN servers + 1 management server)
- **Data Transfer**: Variable based on usage
- **Storage**: ~$10-15/month

## 🚨 Common Issues & Solutions

### Issue 1: Terraform Apply Fails
```bash
# Check AWS credentials
aws sts get-caller-identity

# Check quota limits
aws service-quotas list-service-quotas --service-code ec2

# Enable detailed logs
export TF_LOG=DEBUG
terraform apply
```

### Issue 2: Ansible Connection Fails
```bash
# Test SSH connection
ssh -i ~/.ssh/vpn-keypair.pem ubuntu@MANAGEMENT_IP

# Check security groups allow SSH from your IP
aws ec2 describe-security-groups --group-ids sg-xxxxx
```

### Issue 3: Management Interface Not Accessible
```bash
# Check nginx status
ssh -i ~/.ssh/vpn-keypair.pem ubuntu@MANAGEMENT_IP
sudo systemctl status nginx

# Check docker services
sudo docker-compose -f /opt/vpn-management/docker-compose.yml ps

# Check logs
sudo docker-compose logs -f
```

## 🧹 Clean Up (If Needed)

To destroy everything:
```bash
cd /app/vpn-solution/terraform
terraform destroy
# Type 'yes' to confirm
```

## 🆘 Need Help?

1. **Check logs**: All setup logs are in `/var/log/` on servers
2. **Run tests**: Use `./scripts/integration-tests.sh` to diagnose issues
3. **Review documentation**: Check `/app/vpn-solution/docs/` for detailed guides

**You're now ready to deploy your production VPN service!** 🎉
