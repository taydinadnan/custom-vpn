#!/bin/bash
# Management Server Bootstrap Script
# Sets up FastAPI management interface, monitoring stack, and reverse proxy

set -euo pipefail

# Variables from Terraform
ENVIRONMENT="${environment}"
WIREGUARD_NETWORK="${wireguard_network}"
DOMAIN_NAME="${domain_name}"

# Logging
exec > >(tee /var/log/management-setup.log)
exec 2>&1

echo "Starting management server setup..."
echo "Environment: $ENVIRONMENT"
echo "Domain: $DOMAIN_NAME"

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker.io \
    docker-compose \
    nginx \
    certbot \
    python3-certbot-nginx \
    curl \
    jq \
    htop \
    awscli \
    git \
    python3-pip \
    python3-venv

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Create application directory structure
mkdir -p /opt/vpn-management/{app,data,config,logs}
cd /opt/vpn-management

# Create Docker Compose configuration
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # FastAPI Management Application
  api:
    build: ./app
    container_name: vpn-management-api
    restart: unless-stopped
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://postgres:securepassword@db:5432/vpn_management
      - REDIS_URL=redis://redis:6379/0
      - ENVIRONMENT=${ENVIRONMENT}
      - WIREGUARD_NETWORK=${WIREGUARD_NETWORK}
    volumes:
      - ./data:/app/data
      - ./config:/app/config
      - /var/log:/app/logs
    depends_on:
      - db
      - redis
    networks:
      - vpn-network

  # PostgreSQL Database
  db:
    image: postgres:15-alpine
    container_name: vpn-management-db
    restart: unless-stopped
    environment:
      - POSTGRES_DB=vpn_management
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=securepassword
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./config/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - vpn-network

  # Redis for caching and sessions
  redis:
    image: redis:7-alpine
    container_name: vpn-management-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - vpn-network

  # Prometheus for metrics
  prometheus:
    image: prom/prometheus:latest
    container_name: vpn-prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=7d'
      - '--web.enable-lifecycle'
    volumes:
      - ./config/prometheus:/etc/prometheus
      - prometheus_data:/prometheus
    networks:
      - vpn-network

  # Grafana for visualization
  grafana:
    image: grafana/grafana:latest
    container_name: vpn-grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123!
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_INSTALL_PLUGINS=grafana-piechart-panel
    volumes:
      - grafana_data:/var/lib/grafana
      - ./config/grafana:/etc/grafana/provisioning
    networks:
      - vpn-network

  # Loki for log aggregation
  loki:
    image: grafana/loki:latest
    container_name: vpn-loki
    restart: unless-stopped
    ports:
      - "3100:3100"
    command: -config.file=/etc/loki/local-config.yaml
    volumes:
      - loki_data:/loki
      - ./config/loki:/etc/loki
    networks:
      - vpn-network

volumes:
  postgres_data:
  redis_data:
  prometheus_data:
  grafana_data:
  loki_data:

networks:
  vpn-network:
    driver: bridge
EOF

# Create application directory and Dockerfile
mkdir -p app
cat > app/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

# Run the application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

# Create application requirements
cat > app/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
sqlalchemy==2.0.23
alembic==1.12.1
psycopg2-binary==2.9.9
redis==5.0.1
cryptography==41.0.8
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-multipart==0.0.6
prometheus-client==0.19.0
boto3==1.34.0
qrcode[pil]==7.4.2
python-dotenv==1.0.0
celery==5.3.4
flower==2.0.1
httpx==0.25.2
jinja2==3.1.2
aiofiles==23.2.1
asyncpg==0.29.0
EOF

# Create FastAPI application
cat > app/main.py << 'EOF'
"""
VPN Management API
FastAPI application for managing WireGuard VPN users and configurations
"""

from fastapi import FastAPI, HTTPException, Depends, Security, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse
from pydantic import BaseModel, Field
from typing import List, Optional
import os
import json
import qrcode
import io
import base64
from datetime import datetime, timedelta
import uuid
import subprocess
import logging
from prometheus_client import Counter, Histogram, generate_latest
import asyncio

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Metrics
REQUEST_COUNT = Counter('vpn_api_requests_total', 'Total API requests', ['method', 'endpoint'])
REQUEST_DURATION = Histogram('vpn_api_request_duration_seconds', 'Request duration')

app = FastAPI(
    title="VPN Management API",
    description="Production-ready WireGuard VPN management interface",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Security
security = HTTPBearer()

# Models
class User(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    username: str
    email: str
    public_key: str = ""
    private_key: str = ""
    allowed_ips: str = "10.8.0.0/24"
    created_at: datetime = Field(default_factory=datetime.utcnow)
    is_active: bool = True

class UserCreate(BaseModel):
    username: str
    email: str
    allowed_ips: Optional[str] = "10.8.0.0/24"

class UserUpdate(BaseModel):
    username: Optional[str] = None
    email: Optional[str] = None
    is_active: Optional[bool] = None

class ConfigResponse(BaseModel):
    config: str
    qr_code: str

# Mock database (replace with real database in production)
users_db = {}

# Utility functions
def generate_wireguard_keys():
    """Generate WireGuard key pair"""
    try:
        # Generate private key
        private_key = subprocess.check_output(['wg', 'genkey'], text=True).strip()
        # Generate public key from private key
        public_key = subprocess.check_output(['wg', 'pubkey'], input=private_key, text=True).strip()
        return private_key, public_key
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to generate WireGuard keys: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate keys")

def create_client_config(user: User, server_public_key: str, server_endpoint: str) -> str:
    """Create WireGuard client configuration"""
    config = f"""[Interface]
PrivateKey = {user.private_key}
Address = {user.allowed_ips}
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = {server_public_key}
Endpoint = {server_endpoint}:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
"""
    return config

def generate_qr_code(config: str) -> str:
    """Generate QR code for mobile clients"""
    qr = qrcode.QRCode(version=1, box_size=10, border=5)
    qr.add_data(config)
    qr.make(fit=True)
    
    img = qr.make_image(fill_color="black", back_color="white")
    img_buffer = io.BytesIO()
    img.save(img_buffer, format='PNG')
    img_buffer.seek(0)
    
    return base64.b64encode(img_buffer.getvalue()).decode()

async def verify_token(credentials: HTTPAuthorizationCredentials = Security(security)):
    """Verify JWT token (simplified - implement proper JWT verification)"""
    # In production, implement proper JWT verification
    if credentials.credentials != "demo-token":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return credentials.credentials

# Routes
@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.utcnow()}

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return PlainTextResponse(generate_latest())

@app.post("/users", response_model=User)
async def create_user(user_data: UserCreate, token: str = Depends(verify_token)):
    """Create a new VPN user"""
    REQUEST_COUNT.labels(method="POST", endpoint="/users").inc()
    
    # Check if username already exists
    if any(u.username == user_data.username for u in users_db.values()):
        raise HTTPException(status_code=400, detail="Username already exists")
    
    # Generate WireGuard keys
    private_key, public_key = generate_wireguard_keys()
    
    # Create user
    user = User(
        username=user_data.username,
        email=user_data.email,
        private_key=private_key,
        public_key=public_key,
        allowed_ips=user_data.allowed_ips
    )
    
    users_db[user.id] = user
    
    logger.info(f"Created user: {user.username}")
    return user

@app.get("/users", response_model=List[User])
async def list_users(token: str = Depends(verify_token)):
    """List all VPN users"""
    REQUEST_COUNT.labels(method="GET", endpoint="/users").inc()
    return list(users_db.values())

@app.get("/users/{user_id}", response_model=User)
async def get_user(user_id: str, token: str = Depends(verify_token)):
    """Get a specific user"""
    REQUEST_COUNT.labels(method="GET", endpoint="/users/{user_id}").inc()
    
    if user_id not in users_db:
        raise HTTPException(status_code=404, detail="User not found")
    
    return users_db[user_id]

@app.put("/users/{user_id}", response_model=User)
async def update_user(user_id: str, user_update: UserUpdate, token: str = Depends(verify_token)):
    """Update a user"""
    REQUEST_COUNT.labels(method="PUT", endpoint="/users/{user_id}").inc()
    
    if user_id not in users_db:
        raise HTTPException(status_code=404, detail="User not found")
    
    user = users_db[user_id]
    
    if user_update.username is not None:
        user.username = user_update.username
    if user_update.email is not None:
        user.email = user_update.email
    if user_update.is_active is not None:
        user.is_active = user_update.is_active
    
    logger.info(f"Updated user: {user.username}")
    return user

@app.delete("/users/{user_id}")
async def delete_user(user_id: str, token: str = Depends(verify_token)):
    """Delete a user"""
    REQUEST_COUNT.labels(method="DELETE", endpoint="/users/{user_id}").inc()
    
    if user_id not in users_db:
        raise HTTPException(status_code=404, detail="User not found")
    
    user = users_db.pop(user_id)
    logger.info(f"Deleted user: {user.username}")
    return {"message": "User deleted successfully"}

@app.get("/users/{user_id}/config", response_model=ConfigResponse)
async def get_user_config(user_id: str, token: str = Depends(verify_token)):
    """Generate WireGuard configuration for a user"""
    REQUEST_COUNT.labels(method="GET", endpoint="/users/{user_id}/config").inc()
    
    if user_id not in users_db:
        raise HTTPException(status_code=404, detail="User not found")
    
    user = users_db[user_id]
    
    # Mock values - replace with actual server configuration
    server_public_key = "SERVER_PUBLIC_KEY_PLACEHOLDER"
    server_endpoint = "vpn.example.com"
    
    config = create_client_config(user, server_public_key, server_endpoint)
    qr_code = generate_qr_code(config)
    
    return ConfigResponse(config=config, qr_code=qr_code)

@app.get("/stats")
async def get_stats(token: str = Depends(verify_token)):
    """Get VPN statistics"""
    REQUEST_COUNT.labels(method="GET", endpoint="/stats").inc()
    
    total_users = len(users_db)
    active_users = sum(1 for u in users_db.values() if u.is_active)
    
    return {
        "total_users": total_users,
        "active_users": active_users,
        "inactive_users": total_users - active_users,
        "timestamp": datetime.utcnow()
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

# Create configuration directories and files
mkdir -p config/{prometheus,grafana,loki,postgres}

# Prometheus configuration
cat > config/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alert_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []

scrape_configs:
  - job_name: 'vpn-management-api'
    static_configs:
      - targets: ['api:8000']
    metrics_path: '/metrics'
    scrape_interval: 30s

  - job_name: 'wireguard-servers'
    ec2_sd_configs:
      - region: eu-west-1
        port: 9100
        filters:
          - name: tag:Role
            values: ['wireguard-server']
    relabel_configs:
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: '${1}:9100'

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']
EOF

# Prometheus alert rules
cat > config/prometheus/alert_rules.yml << 'EOF'
groups:
  - name: vpn_alerts
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% for {{ $labels.instance }}"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 90% for {{ $labels.instance }}"

      - alert: VPNServerDown
        expr: up{job="wireguard-servers"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "VPN server is down"
          description: "VPN server {{ $labels.instance }} is unreachable"
EOF

# Grafana datasource configuration
mkdir -p config/grafana/datasources
cat > config/grafana/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
EOF

# PostgreSQL initialization
cat > config/postgres/init.sql << 'EOF'
-- VPN Management Database Schema

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    public_key TEXT NOT NULL,
    private_key TEXT NOT NULL,
    allowed_ips CIDR NOT NULL DEFAULT '10.8.0.0/24',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    action VARCHAR(50) NOT NULL,
    details JSONB,
    ip_address INET,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_active ON users(is_active);
CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_timestamp ON audit_logs(timestamp);

-- Create audit trigger
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_logs (user_id, action, details)
    VALUES (NEW.id, TG_OP, to_jsonb(NEW));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW
    EXECUTE FUNCTION audit_trigger_function();
EOF

# Loki configuration
cat > config/loki/local-config.yaml << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 168h

storage_config:
  boltdb:
    directory: /loki/index

  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: true
  retention_period: 168h
EOF

# Configure Nginx reverse proxy
cat > /etc/nginx/sites-available/vpn-management << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;

    # Health check endpoint
    location /health {
        proxy_pass http://localhost:8000/health;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Redirect HTTP to HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN_NAME;

    # SSL configuration (will be managed by Certbot)
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # API endpoints
    location /api/ {
        proxy_pass http://localhost:8000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Grafana
    location /grafana/ {
        proxy_pass http://localhost:3000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Prometheus (admin only)
    location /prometheus/ {
        auth_basic "Prometheus";
        auth_basic_user_file /etc/nginx/.htpasswd;
        proxy_pass http://localhost:9090/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Static files and frontend
    location / {
        root /var/www/html;
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

# Enable site
ln -sf /etc/nginx/sites-available/vpn-management /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Create basic auth for Prometheus
echo "admin:\$apr1\$rUe.7YEP\$oXQ.8RxvIk7c2JJ.yLDj71" > /etc/nginx/.htpasswd

# Test Nginx configuration
nginx -t

# Start Docker services
cd /opt/vpn-management
docker-compose up -d

# Wait for services to start
sleep 30

# Start Nginx
systemctl enable nginx
systemctl start nginx

# Create basic HTML page
mkdir -p /var/www/html
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPN Management Interface</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        h1 { color: #333; }
        .service-link { display: inline-block; margin: 10px; padding: 15px 25px; background: #007bff; color: white; text-decoration: none; border-radius: 5px; }
        .service-link:hover { background: #0056b3; }
    </style>
</head>
<body>
    <div class="container">
        <h1>VPN Management Interface</h1>
        <p>Welcome to the VPN Management System</p>
        
        <h2>Services</h2>
        <a href="/api/docs" class="service-link">API Documentation</a>
        <a href="/grafana" class="service-link">Monitoring Dashboard</a>
        <a href="/prometheus" class="service-link">Metrics (Admin)</a>
        
        <h2>API Endpoints</h2>
        <ul>
            <li><strong>GET /api/health</strong> - Health check</li>
            <li><strong>POST /api/users</strong> - Create new user</li>
            <li><strong>GET /api/users</strong> - List all users</li>
            <li><strong>GET /api/users/{id}/config</strong> - Get user configuration</li>
        </ul>
        
        <h2>Getting Started</h2>
        <p>Use the API documentation to explore available endpoints. Default authentication token: <code>demo-token</code></p>
    </div>
</body>
</html>
EOF

echo "Management server setup completed successfully!"
echo "Services available at:"
echo "  - Main interface: https://$DOMAIN_NAME"
echo "  - API docs: https://$DOMAIN_NAME/api/docs"
echo "  - Grafana: https://$DOMAIN_NAME/grafana"
echo "  - Prometheus: https://$DOMAIN_NAME/prometheus (admin/admin)"

# Final status check
docker-compose ps
systemctl status nginx