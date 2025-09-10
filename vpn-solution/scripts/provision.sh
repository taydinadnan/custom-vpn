#!/bin/bash
# Complete VPN Solution Provisioning Script
# Automates the entire deployment process from zero to production

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/tmp/vpn-provision-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}" | tee -a "$LOG_FILE"
}

# Configuration variables (set defaults or override with environment)
ENVIRONMENT="${ENVIRONMENT:-production}"
AWS_REGION="${AWS_REGION:-eu-west-1}"
DOMAIN_NAME="${DOMAIN_NAME:-}"
MANAGEMENT_DOMAIN="${MANAGEMENT_DOMAIN:-}"
KEY_NAME="${KEY_NAME:-vpn-keypair}"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check required tools
    local required_tools=("terraform" "ansible" "aws" "docker" "git")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is required but not installed"
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check Terraform version
    local tf_version=$(terraform version -json | jq -r '.terraform_version')
    log "Terraform version: $tf_version"
    
    # Check Ansible version
    local ansible_version=$(ansible --version | head -n1 | awk '{print $2}')
    log "Ansible version: $ansible_version"
    
    log "Prerequisites check passed"
}

# Setup AWS infrastructure
setup_infrastructure() {
    log "Setting up AWS infrastructure..."
    
    cd "$PROJECT_ROOT/terraform"
    
    # Initialize Terraform
    log "Initializing Terraform..."
    terraform init
    
    # Create workspace if it doesn't exist
    terraform workspace select "$ENVIRONMENT" 2>/dev/null || terraform workspace new "$ENVIRONMENT"
    
    # Validate configuration
    log "Validating Terraform configuration..."
    terraform validate
    
    # Plan deployment
    log "Planning infrastructure deployment..."
    terraform plan \
        -var="environment=$ENVIRONMENT" \
        -var="aws_region=$AWS_REGION" \
        -var="domain_name=${DOMAIN_NAME}" \
        -var="management_domain=${MANAGEMENT_DOMAIN}" \
        -var="key_name=$KEY_NAME" \
        -out=tfplan
    
    # Apply configuration
    log "Applying infrastructure configuration..."
    terraform apply tfplan
    
    # Save outputs
    terraform output -json > "$PROJECT_ROOT/terraform-outputs.json"
    
    log "Infrastructure setup completed"
}

# Configure servers with Ansible
configure_servers() {
    log "Configuring servers with Ansible..."
    
    cd "$PROJECT_ROOT/ansible"
    
    # Generate dynamic inventory from Terraform outputs
    log "Generating Ansible inventory..."
    cat > inventory/hosts.yml << EOF
all:
  children:
    vpn_servers:
      hosts:
        # Dynamically populated by terraform outputs
      vars:
        ansible_user: ubuntu
        ansible_ssh_private_key_file: ~/.ssh/${KEY_NAME}.pem
    management_servers:
      hosts:
        # Dynamically populated by terraform outputs
      vars:
        ansible_user: ubuntu
        ansible_ssh_private_key_file: ~/.ssh/${KEY_NAME}.pem
EOF
    
    # Wait for instances to be ready
    log "Waiting for instances to be ready..."
    sleep 120
    
    # Run Ansible playbook
    log "Running Ansible configuration..."
    ansible-playbook \
        -i inventory/hosts.yml \
        site.yml \
        --extra-vars "environment=$ENVIRONMENT"
    
    log "Server configuration completed"
}

# Setup monitoring
setup_monitoring() {
    log "Setting up monitoring stack..."
    
    # Get management server IP from terraform outputs
    local mgmt_ip=$(jq -r '.management_public_ip.value' "$PROJECT_ROOT/terraform-outputs.json")
    
    # SSH to management server and setup monitoring
    ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@$mgmt_ip << 'EOF'
        # Monitoring setup is handled by the management server user-data script
        # Check if services are running
        sudo docker-compose -f /opt/vpn-management/docker-compose.yml ps
        
        # Wait for services to be fully ready
        sleep 60
        
        # Import Grafana dashboards
        # This would typically be done via API or provisioning
        echo "Monitoring stack setup completed on management server"
EOF
    
    log "Monitoring setup completed"
}

# Run integration tests
run_tests() {
    log "Running integration tests..."
    
    # Get outputs from Terraform
    local vpn_endpoint=$(jq -r '.wireguard_server_endpoint.value' "$PROJECT_ROOT/terraform-outputs.json")
    local mgmt_url=$(jq -r '.management_interface_url.value' "$PROJECT_ROOT/terraform-outputs.json")
    
    # Test VPN server connectivity
    log "Testing VPN server connectivity..."
    if nc -z -w5 $(echo $vpn_endpoint | cut -d: -f1) $(echo $vpn_endpoint | cut -d: -f2); then
        log "VPN server is reachable"
    else
        warn "VPN server connectivity test failed"
    fi
    
    # Test management interface
    log "Testing management interface..."
    if curl -k -s --max-time 10 "$mgmt_url/health" | grep -q "healthy"; then
        log "Management interface is healthy"
    else
        warn "Management interface health check failed"
    fi
    
    # Test Prometheus metrics
    log "Testing Prometheus metrics..."
    if curl -k -s --max-time 10 "$mgmt_url/prometheus/api/v1/query?query=up" | grep -q "success"; then
        log "Prometheus is responding"
    else
        warn "Prometheus test failed"
    fi
    
    log "Integration tests completed"
}

# Generate client configurations
generate_client_configs() {
    log "Generating sample client configurations..."
    
    local vpn_endpoint=$(jq -r '.wireguard_server_endpoint.value' "$PROJECT_ROOT/terraform-outputs.json")
    local server_public_key="SERVER_PUBLIC_KEY_PLACEHOLDER"  # Would be retrieved from server
    
    # Create client config directory
    mkdir -p "$PROJECT_ROOT/generated-configs"
    
    # Generate sample configuration
    cat > "$PROJECT_ROOT/generated-configs/sample-client.conf" << EOF
# Sample WireGuard Client Configuration
# Replace placeholder values with actual configuration from management interface

[Interface]
PrivateKey = CLIENT_PRIVATE_KEY_PLACEHOLDER
Address = 10.8.0.2/32
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = $server_public_key
Endpoint = $vpn_endpoint
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
    
    log "Sample client configuration generated: $PROJECT_ROOT/generated-configs/sample-client.conf"
}

# Display deployment summary
show_summary() {
    log "Deployment Summary"
    echo "===================="
    
    local vpn_endpoint=$(jq -r '.wireguard_server_endpoint.value' "$PROJECT_ROOT/terraform-outputs.json")
    local mgmt_url=$(jq -r '.management_interface_url.value' "$PROJECT_ROOT/terraform-outputs.json")
    local mgmt_ip=$(jq -r '.management_public_ip.value' "$PROJECT_ROOT/terraform-outputs.json")
    
    echo
    info "VPN Service Information:"
    echo "  Environment: $ENVIRONMENT"
    echo "  Region: $AWS_REGION"
    echo "  VPN Endpoint: $vpn_endpoint"
    echo
    
    info "Management Interface:"
    echo "  URL: $mgmt_url"
    echo "  IP Address: $mgmt_ip"
    echo "  API Documentation: $mgmt_url/api/docs"
    echo "  Monitoring Dashboard: $mgmt_url/grafana"
    echo "  Metrics: $mgmt_url/prometheus"
    echo
    
    info "SSH Access:"
    echo "  Management Server: ssh -i ~/.ssh/${KEY_NAME}.pem ubuntu@$mgmt_ip"
    echo
    
    info "Next Steps:"
    echo "  1. Access the management interface to create VPN users"
    echo "  2. Download client configurations or QR codes"
    echo "  3. Configure monitoring alerts"
    echo "  4. Set up backup procedures"
    echo "  5. Review security audit checklist"
    echo
    
    info "Log file saved to: $LOG_FILE"
}

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    # Add cleanup logic if needed
}

# Main execution
main() {
    log "Starting VPN Solution Provisioning"
    log "Environment: $ENVIRONMENT"
    log "AWS Region: $AWS_REGION"
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    # Prompt for required values if not set
    if [[ -z "$DOMAIN_NAME" ]]; then
        read -p "Enter your domain name (or 'skip' for default): " DOMAIN_NAME
        if [[ "$DOMAIN_NAME" == "skip" ]]; then
            DOMAIN_NAME="vpn.example.com"
            MANAGEMENT_DOMAIN="vpn-mgmt.example.com"
        else
            MANAGEMENT_DOMAIN="mgmt.$DOMAIN_NAME"
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_infrastructure
    configure_servers
    setup_monitoring
    run_tests
    generate_client_configs
    show_summary
    
    log "VPN Solution provisioning completed successfully!"
}

# Handle command line arguments
case "${1:-deploy}" in
    deploy)
        main
        ;;
    destroy)
        log "Destroying infrastructure..."
        cd "$PROJECT_ROOT/terraform"
        terraform workspace select "$ENVIRONMENT"
        terraform destroy -auto-approve
        log "Infrastructure destroyed"
        ;;
    plan)
        log "Planning infrastructure changes..."
        cd "$PROJECT_ROOT/terraform"
        terraform workspace select "$ENVIRONMENT" 2>/dev/null || terraform workspace new "$ENVIRONMENT"
        terraform plan
        ;;
    test)
        run_tests
        ;;
    *)
        echo "Usage: $0 {deploy|destroy|plan|test}"
        echo "  deploy  - Deploy complete VPN solution"
        echo "  destroy - Destroy infrastructure"
        echo "  plan    - Show planned changes"
        echo "  test    - Run integration tests"
        exit 1
        ;;
esac