#!/bin/bash
# WireGuard VPN Client Setup Script for Linux
# Supports Ubuntu, Debian, CentOS, Fedora, and Arch Linux

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        warn "This script should not be run as root for security reasons"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Detect Linux distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    else
        error "Cannot detect Linux distribution"
    fi
    
    log "Detected distribution: $DISTRO $VERSION"
}

# Install WireGuard
install_wireguard() {
    log "Installing WireGuard..."
    
    case $DISTRO in
        ubuntu|debian)
            sudo apt update
            sudo apt install -y wireguard wireguard-tools resolvconf
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                sudo dnf install -y wireguard-tools
            else
                sudo yum install -y epel-release
                sudo yum install -y wireguard-tools
            fi
            ;;
        arch|manjaro)
            sudo pacman -S --noconfirm wireguard-tools
            ;;
        *)
            error "Unsupported distribution: $DISTRO"
            ;;
    esac
    
    log "WireGuard installed successfully"
}

# Create configuration directory
setup_config_dir() {
    log "Setting up configuration directory..."
    
    sudo mkdir -p /etc/wireguard
    sudo chmod 700 /etc/wireguard
    
    log "Configuration directory created"
}

# Import configuration
import_config() {
    local config_file="$1"
    local connection_name="$2"
    
    if [[ ! -f "$config_file" ]]; then
        error "Configuration file not found: $config_file"
    fi
    
    log "Importing configuration as '$connection_name'..."
    
    # Validate configuration
    if ! wg-quick strip "$config_file" > /dev/null 2>&1; then
        error "Invalid WireGuard configuration file"
    fi
    
    # Copy configuration
    sudo cp "$config_file" "/etc/wireguard/${connection_name}.conf"
    sudo chmod 600 "/etc/wireguard/${connection_name}.conf"
    
    log "Configuration imported successfully"
}

# Generate client configuration
generate_config() {
    local connection_name="$1"
    
    log "Generating client configuration..."
    
    # Generate keys
    local private_key=$(wg genkey)
    local public_key=$(echo "$private_key" | wg pubkey)
    
    log "Generated key pair"
    log "Public key (share with administrator): $public_key"
    
    # Create configuration template
    cat > "/tmp/${connection_name}.conf" << EOF
[Interface]
PrivateKey = $private_key
Address = CLIENT_IP_PLACEHOLDER/32
DNS = 1.1.1.1, 1.0.0.1

# Linux-specific settings
# PreUp = echo "Connecting to VPN..."
# PostUp = iptables -A OUTPUT ! -o %i -m mark ! --mark \$(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
# PreDown = iptables -D OUTPUT ! -o %i -m mark ! --mark \$(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
# PostDown = echo "Disconnected from VPN"

[Peer]
PublicKey = SERVER_PUBLIC_KEY_PLACEHOLDER
Endpoint = SERVER_ENDPOINT_PLACEHOLDER:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
    
    echo
    warn "IMPORTANT: Edit /tmp/${connection_name}.conf and replace placeholder values:"
    warn "- CLIENT_IP_PLACEHOLDER: Your assigned VPN IP"
    warn "- SERVER_PUBLIC_KEY_PLACEHOLDER: Server's public key"
    warn "- SERVER_ENDPOINT_PLACEHOLDER: Server hostname/IP"
    echo
    warn "After editing, run: $0 --import /tmp/${connection_name}.conf $connection_name"
}

# Enable systemd service
enable_service() {
    local connection_name="$1"
    
    log "Enabling systemd service for '$connection_name'..."
    
    sudo systemctl enable "wg-quick@${connection_name}.service"
    
    log "Service enabled. Use 'sudo systemctl start wg-quick@${connection_name}' to connect"
}

# Connection management functions
connect_vpn() {
    local connection_name="$1"
    
    log "Connecting to VPN '$connection_name'..."
    sudo wg-quick up "$connection_name"
    log "Connected successfully"
}

disconnect_vpn() {
    local connection_name="$1"
    
    log "Disconnecting from VPN '$connection_name'..."
    sudo wg-quick down "$connection_name"
    log "Disconnected successfully"
}

status_vpn() {
    log "WireGuard Status:"
    sudo wg show
}

# Test connection
test_connection() {
    log "Testing VPN connection..."
    
    # Check if WireGuard interface is up
    if ! sudo wg show | grep -q interface; then
        warn "No active WireGuard connections found"
        return
    fi
    
    # Test external connectivity
    log "Testing external connectivity..."
    if curl -s --max-time 10 https://1.1.1.1 > /dev/null; then
        log "External connectivity: OK"
    else
        warn "External connectivity: FAILED"
    fi
    
    # Check DNS resolution
    log "Testing DNS resolution..."
    if nslookup google.com > /dev/null 2>&1; then
        log "DNS resolution: OK"
    else
        warn "DNS resolution: FAILED"
    fi
    
    # Show current IP
    log "Current public IP:"
    curl -s https://ipinfo.io/ip || echo "Unable to determine public IP"
}

# Uninstall function
uninstall() {
    log "Uninstalling WireGuard client..."
    
    # Stop all connections
    for conf in /etc/wireguard/*.conf; do
        if [[ -f "$conf" ]]; then
            local name=$(basename "$conf" .conf)
            sudo wg-quick down "$name" 2>/dev/null || true
            sudo systemctl disable "wg-quick@${name}.service" 2>/dev/null || true
        fi
    done
    
    # Remove configurations
    sudo rm -rf /etc/wireguard/
    
    log "WireGuard client uninstalled"
}

# Show usage
usage() {
    cat << EOF
WireGuard VPN Client Setup Script for Linux

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    install                     Install WireGuard
    generate <name>             Generate new client configuration
    import <file> <name>        Import configuration file
    connect <name>              Connect to VPN
    disconnect <name>           Disconnect from VPN
    status                      Show connection status
    test                        Test VPN connection
    uninstall                   Remove WireGuard client
    
Examples:
    $0 install                  # Install WireGuard
    $0 generate myvpn           # Generate configuration template
    $0 import config.conf myvpn # Import configuration
    $0 connect myvpn            # Connect to VPN
    $0 disconnect myvpn         # Disconnect from VPN
    $0 status                   # Show status
    $0 test                     # Test connection

EOF
}

# Main function
main() {
    check_root
    detect_distro
    
    case "${1:-}" in
        install)
            install_wireguard
            setup_config_dir
            ;;
        generate)
            [[ $# -eq 2 ]] || error "Usage: $0 generate <connection_name>"
            generate_config "$2"
            ;;
        import)
            [[ $# -eq 3 ]] || error "Usage: $0 import <config_file> <connection_name>"
            import_config "$2" "$3"
            enable_service "$3"
            ;;
        connect)
            [[ $# -eq 2 ]] || error "Usage: $0 connect <connection_name>"
            connect_vpn "$2"
            ;;
        disconnect)
            [[ $# -eq 2 ]] || error "Usage: $0 disconnect <connection_name>"
            disconnect_vpn "$2"
            ;;
        status)
            status_vpn
            ;;
        test)
            test_connection
            ;;
        uninstall)
            uninstall
            ;;
        --help|-h|help)
            usage
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"