#!/bin/bash
# WireGuard VPN Server Bootstrap Script
# This script sets up a WireGuard server with security hardening

set -euo pipefail

# Variables from Terraform
WIREGUARD_PORT="${wireguard_port}"
WIREGUARD_NETWORK="${wireguard_network}"
ENVIRONMENT="${environment}"

# Logging
exec > >(tee /var/log/wireguard-setup.log)
exec 2>&1

echo "Starting WireGuard server setup..."
echo "Environment: $ENVIRONMENT"
echo "WireGuard Port: $WIREGUARD_PORT"
echo "WireGuard Network: $WIREGUARD_NETWORK"

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    wireguard \
    wireguard-tools \
    ufw \
    fail2ban \
    unbound \
    curl \
    jq \
    htop \
    iptables-persistent \
    netfilter-persistent \
    awscli \
    prometheus-node-exporter

# Enable IP forwarding
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
sysctl -p

# Generate WireGuard server keys
cd /etc/wireguard
wg genkey | tee server_private_key | wg pubkey > server_public_key
chmod 600 server_private_key

# Get server private key
SERVER_PRIVATE_KEY=$(cat server_private_key)

# Get the default network interface
DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# Create WireGuard configuration
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = $(echo $WIREGUARD_NETWORK | sed 's/0\/24/1\/24/')
ListenPort = $WIREGUARD_PORT
SaveConfig = false

# Enable packet forwarding
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE

EOF

# Set correct permissions
chmod 600 /etc/wireguard/wg0.conf

# Configure UFW firewall
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Allow SSH
ufw allow 22/tcp

# Allow WireGuard
ufw allow $WIREGUARD_PORT/udp

# Allow HTTP/HTTPS for health checks
ufw allow 80/tcp
ufw allow 8080/tcp

# Enable UFW
ufw --force enable

# Configure Fail2ban
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
ignoreip = 127.0.0.1/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

[wireguard]
enabled = true
port = $WIREGUARD_PORT
protocol = udp
filter = wireguard
logpath = /var/log/kern.log
maxretry = 5
EOF

# Create WireGuard filter for Fail2ban
cat > /etc/fail2ban/filter.d/wireguard.conf << EOF
[Definition]
failregex = ^.*wireguard.*: Invalid handshake initiation from <HOST>.*$
ignoreregex =
EOF

# Configure Unbound DNS resolver
cat > /etc/unbound/unbound.conf.d/vpn.conf << EOF
server:
    verbosity: 1
    interface: $(echo $WIREGUARD_NETWORK | sed 's/0\/24/1/')
    port: 53
    do-ip4: yes
    do-ip6: no
    do-udp: yes
    do-tcp: yes
    
    # Trust glue only if it is within the servers authority
    harden-glue: yes
    
    # Require DNSSEC data for trust-anchored zones
    harden-dnssec-stripped: yes
    
    # Use 0x20-encoded random bits in the query
    use-caps-for-id: yes
    
    # Reduce EDNS reassembly buffer size
    edns-buffer-size: 1472
    
    # TTL bounds
    cache-min-ttl: 3600
    cache-max-ttl: 86400
    
    # Privacy settings
    hide-identity: yes
    hide-version: yes
    
    # Access control
    access-control: 0.0.0.0/0 refuse
    access-control: 127.0.0.1/8 allow
    access-control: $WIREGUARD_NETWORK allow

forward-zone:
    name: "."
    forward-ssl-upstream: yes
    forward-addr: 1.1.1.1@853#cloudflare-dns.com
    forward-addr: 1.0.0.1@853#cloudflare-dns.com
EOF

# Create health check endpoint
mkdir -p /opt/wireguard-health
cat > /opt/wireguard-health/health.py << 'EOF'
#!/usr/bin/env python3
import subprocess
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading
import time

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            try:
                # Check if WireGuard interface is up
                result = subprocess.run(['wg', 'show', 'wg0'], 
                                      capture_output=True, text=True)
                
                if result.returncode == 0:
                    # Count active peers
                    lines = result.stdout.split('\n')
                    peer_count = len([line for line in lines if line.strip().startswith('peer:')])
                    
                    health_data = {
                        'status': 'healthy',
                        'interface': 'wg0',
                        'peer_count': peer_count,
                        'timestamp': int(time.time())
                    }
                    
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps(health_data).encode())
                else:
                    raise Exception("WireGuard interface not found")
                    
            except Exception as e:
                self.send_response(503)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                error_data = {
                    'status': 'unhealthy',
                    'error': str(e),
                    'timestamp': int(time.time())
                }
                self.wfile.write(json.dumps(error_data).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8080), HealthHandler)
    server.serve_forever()
EOF

chmod +x /opt/wireguard-health/health.py

# Create systemd service for health check
cat > /etc/systemd/system/wireguard-health.service << EOF
[Unit]
Description=WireGuard Health Check Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=/usr/bin/python3 /opt/wireguard-health/health.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
systemctl daemon-reload
systemctl enable wg-quick@wg0
systemctl enable fail2ban
systemctl enable unbound
systemctl enable wireguard-health
systemctl enable prometheus-node-exporter

# Start services
systemctl start wg-quick@wg0
systemctl start fail2ban
systemctl start unbound
systemctl start wireguard-health
systemctl start prometheus-node-exporter

# Create log rotation for privacy
cat > /etc/logrotate.d/wireguard << EOF
/var/log/wireguard-setup.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 0640 root root
}
EOF

# Set up CloudWatch agent for monitoring
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "metrics": {
        "namespace": "VPN/WireGuard",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait"],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": ["tcp_established", "tcp_time_wait"],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/auth.log",
                        "log_group_name": "/aws/ec2/vpn/auth",
                        "log_stream_name": "{instance_id}"
                    }
                ]
            }
        }
    }
}
EOF

# Store server public key in SSM Parameter Store for management API
aws ssm put-parameter \
    --name "/vpn/$ENVIRONMENT/wireguard/server-public-key" \
    --value "$(cat /etc/wireguard/server_public_key)" \
    --type "String" \
    --overwrite \
    --region "$(curl -s http://169.254.169.254/latest/meta-data/placement/region)" || true

echo "WireGuard server setup completed successfully!"
echo "Server public key: $(cat /etc/wireguard/server_public_key)"
echo "Health check available at: http://localhost:8080/health"

# Final status check
systemctl status wg-quick@wg0
wg show