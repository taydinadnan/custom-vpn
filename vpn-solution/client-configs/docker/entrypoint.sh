#!/bin/sh
# WireGuard Docker Container Entrypoint Script

set -e

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# Check if running as root (required for WireGuard)
if [ "$(id -u)" != "0" ]; then
    error "Container must run as root to manage network interfaces"
fi

# Validate required environment variables
validate_env() {
    log "Validating environment variables..."
    
    [ -z "$WG_PRIVATE_KEY" ] && error "WG_PRIVATE_KEY environment variable is required"
    [ -z "$WG_ADDRESS" ] && error "WG_ADDRESS environment variable is required"
    [ -z "$WG_SERVER_PUBLIC_KEY" ] && error "WG_SERVER_PUBLIC_KEY environment variable is required"
    [ -z "$WG_ENDPOINT" ] && error "WG_ENDPOINT environment variable is required"
    
    log "Environment validation passed"
}

# Generate WireGuard configuration
generate_config() {
    local interface_name="${1:-wg0}"
    local config_file="/etc/wireguard/${interface_name}.conf"
    
    log "Generating WireGuard configuration for interface: $interface_name"
    
    # Use envsubst to replace environment variables in template
    envsubst < /etc/wireguard/wg0.conf.template > "$config_file"
    
    # Set proper permissions
    chmod 600 "$config_file"
    
    log "Configuration generated: $config_file"
}

# Start health check server
start_health_server() {
    log "Starting health check server on port 8080..."
    
    # Simple HTTP server for health checks
    cat > /tmp/health_server.py << 'EOF'
import http.server
import socketserver
import json
import subprocess
import sys
from datetime import datetime

class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            try:
                # Check if WireGuard interface is up
                result = subprocess.run(['wg', 'show'], capture_output=True, text=True)
                
                if result.returncode == 0 and 'interface:' in result.stdout:
                    health_data = {
                        'status': 'healthy',
                        'interface': 'active',
                        'timestamp': datetime.utcnow().isoformat()
                    }
                    self.send_response(200)
                else:
                    raise Exception("WireGuard interface not active")
                    
            except Exception as e:
                health_data = {
                    'status': 'unhealthy',
                    'error': str(e),
                    'timestamp': datetime.utcnow().isoformat()
                }
                self.send_response(503)
            
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(health_data).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        # Suppress default logging
        pass

if __name__ == '__main__':
    with socketserver.TCPServer(("", 8080), HealthHandler) as httpd:
        httpd.serve_forever()
EOF
    
    python3 /tmp/health_server.py &
    echo $! > /tmp/health_server.pid
}

# Connect to VPN
connect_vpn() {
    local interface_name="${1:-wg0}"
    
    log "Connecting to VPN interface: $interface_name"
    
    # Bring up WireGuard interface
    wg-quick up "$interface_name"
    
    log "VPN connection established"
    
    # Show connection status
    wg show "$interface_name"
}

# Disconnect from VPN
disconnect_vpn() {
    local interface_name="${1:-wg0}"
    
    log "Disconnecting from VPN interface: $interface_name"
    
    wg-quick down "$interface_name" || true
    
    log "VPN disconnected"
}

# Monitor connection
monitor_connection() {
    local interface_name="${1:-wg0}"
    
    log "Starting connection monitor for interface: $interface_name"
    
    while true; do
        if ! wg show "$interface_name" > /dev/null 2>&1; then
            log "Connection lost, attempting to reconnect..."
            connect_vpn "$interface_name"
        fi
        
        sleep "${HEALTH_CHECK_INTERVAL:-30}"
    done
}

# Cleanup function
cleanup() {
    log "Cleaning up..."
    
    # Stop health server
    if [ -f /tmp/health_server.pid ]; then
        kill "$(cat /tmp/health_server.pid)" 2>/dev/null || true
        rm -f /tmp/health_server.pid
    fi
    
    # Disconnect VPN
    disconnect_vpn "${WG_INTERFACE:-wg0}"
    
    log "Cleanup completed"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Main execution
main() {
    local interface_name="${1:-${WG_INTERFACE:-wg0}}"
    
    log "Starting WireGuard VPN client container"
    log "Interface: $interface_name"
    
    # Validate environment
    validate_env
    
    # Generate configuration
    generate_config "$interface_name"
    
    # Start health check server
    start_health_server
    
    # Connect to VPN
    connect_vpn "$interface_name"
    
    # Start connection monitor in background
    monitor_connection "$interface_name" &
    
    log "VPN client is running. Press Ctrl+C to stop."
    
    # Keep container running
    while true; do
        sleep 60
        
        # Optional: Log connection statistics
        if [ "$LOG_LEVEL" = "DEBUG" ]; then
            log "Connection statistics:"
            wg show "$interface_name" 2>/dev/null || log "No active connection"
        fi
    done
}

# Run main function with all arguments
main "$@"