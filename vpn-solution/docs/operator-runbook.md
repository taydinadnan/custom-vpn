# VPN Solution Operator Runbook

This runbook provides step-by-step procedures for operating and maintaining the VPN solution.

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Daily Operations](#daily-operations)
3. [User Management](#user-management)
4. [Troubleshooting](#troubleshooting)
5. [Monitoring and Alerts](#monitoring-and-alerts)
6. [Maintenance Procedures](#maintenance-procedures)
7. [Emergency Procedures](#emergency-procedures)
8. [Backup and Recovery](#backup-and-recovery)

## Quick Reference

### Key URLs and Access Points

```bash
# Management Interface
https://vpn-mgmt.your-domain.com

# SSH Access
ssh -i ~/.ssh/vpn-keypair.pem ubuntu@MANAGEMENT_SERVER_IP

# Monitoring
https://vpn-mgmt.your-domain.com/grafana
https://vpn-mgmt.your-domain.com/prometheus

# API Documentation
https://vpn-mgmt.your-domain.com/api/docs
```

### Important File Locations

```bash
# WireGuard Configuration
/etc/wireguard/wg0.conf

# Application Logs
/var/log/wireguard-setup.log
/var/log/management-setup.log
/opt/vpn-management/logs/

# Service Status
sudo systemctl status wg-quick@wg0
sudo docker-compose -f /opt/vpn-management/docker-compose.yml ps
```

### Emergency Contacts

- **Primary On-Call:** [Contact Info]
- **Secondary On-Call:** [Contact Info]
- **Infrastructure Team:** [Contact Info]
- **Security Team:** [Contact Info]

## Daily Operations

### Morning Checklist

1. **Check Service Status**
   ```bash
   # Check WireGuard servers
   curl -s https://vpn-mgmt.your-domain.com/api/stats
   
   # Check management interface
   curl -s https://vpn-mgmt.your-domain.com/health
   ```

2. **Review Monitoring Dashboards**
   - Open Grafana dashboard
   - Check for any alerts
   - Review resource utilization

3. **Check System Logs**
   ```bash
   # SSH to management server
   ssh -i ~/.ssh/vpn-keypair.pem ubuntu@MANAGEMENT_SERVER_IP
   
   # Check recent logs
   sudo journalctl --since "1 hour ago" --no-pager
   
   # Check fail2ban status
   sudo fail2ban-client status
   ```

### End of Day Checklist

1. **Review Connection Statistics**
2. **Check for Failed Authentication Attempts**
3. **Verify Backup Completion**
4. **Review Security Alerts**

## User Management

### Creating a New User

#### Via Web Interface

1. Access management interface: `https://vpn-mgmt.your-domain.com`
2. Authenticate with admin credentials
3. Navigate to "Users" section
4. Click "Create New User"
5. Fill in user details:
   - Username
   - Email
   - IP allocation (optional)
6. Click "Create"
7. Download configuration or generate QR code

#### Via API

```bash
# Create new user
curl -X POST "https://vpn-mgmt.your-domain.com/api/users" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "john.doe",
    "email": "john.doe@company.com"
  }'

# Get user configuration
curl -X GET "https://vpn-mgmt.your-domain.com/api/users/{user_id}/config" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Disabling a User

1. **Via Web Interface:**
   - Navigate to user list
   - Find user
   - Click "Disable" or toggle status

2. **Via API:**
   ```bash
   curl -X PUT "https://vpn-mgmt.your-domain.com/api/users/{user_id}" \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"is_active": false}'
   ```

### Removing a User

1. **Via Web Interface:**
   - Navigate to user list
   - Find user
   - Click "Delete"
   - Confirm deletion

2. **Via API:**
   ```bash
   curl -X DELETE "https://vpn-mgmt.your-domain.com/api/users/{user_id}" \
     -H "Authorization: Bearer YOUR_TOKEN"
   ```

### Bulk User Operations

```bash
# List all users
curl -X GET "https://vpn-mgmt.your-domain.com/api/users" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Disable all inactive users (example script)
#!/bin/bash
API_URL="https://vpn-mgmt.your-domain.com/api"
TOKEN="YOUR_TOKEN"

# Get list of users inactive for 30+ days
# Implement logic based on your tracking system
```

## Troubleshooting

### Common Issues

#### 1. VPN Connection Fails

**Symptoms:** Client cannot establish connection

**Diagnosis:**
```bash
# Check server status
sudo wg show

# Check firewall
sudo ufw status

# Check logs
sudo journalctl -u wg-quick@wg0 -f

# Test connectivity
nc -z -v VPN_SERVER_IP 51820
```

**Resolution:**
1. Verify server configuration
2. Check firewall rules
3. Restart WireGuard service if needed:
   ```bash
   sudo systemctl restart wg-quick@wg0
   ```

#### 2. Management Interface Unreachable

**Symptoms:** Cannot access web interface

**Diagnosis:**
```bash
# Check nginx status
sudo systemctl status nginx

# Check docker services
sudo docker-compose -f /opt/vpn-management/docker-compose.yml ps

# Check SSL certificate
openssl s_client -connect vpn-mgmt.your-domain.com:443 -servername vpn-mgmt.your-domain.com
```

**Resolution:**
1. Restart nginx: `sudo systemctl restart nginx`
2. Restart docker services:
   ```bash
   cd /opt/vpn-management
   sudo docker-compose restart
   ```

#### 3. High CPU/Memory Usage

**Symptoms:** System performance issues

**Diagnosis:**
```bash
# Check system resources
htop
iostat -x 1

# Check WireGuard stats
sudo wg show all

# Check docker resource usage
docker stats
```

**Resolution:**
1. Identify resource-intensive processes
2. Scale infrastructure if needed
3. Optimize configurations

#### 4. DNS Resolution Issues

**Symptoms:** Client can connect but cannot resolve domains

**Diagnosis:**
```bash
# Check unbound service
sudo systemctl status unbound

# Test DNS resolution
nslookup google.com 127.0.0.1

# Check unbound logs
sudo journalctl -u unbound -f
```

**Resolution:**
1. Restart unbound: `sudo systemctl restart unbound`
2. Check unbound configuration
3. Verify DNS forwarding rules

### Log Analysis

#### Key Log Files

```bash
# System logs
/var/log/syslog
/var/log/auth.log
/var/log/kern.log

# Application logs
/var/log/wireguard-setup.log
/var/log/management-setup.log
/var/log/nginx/access.log
/var/log/nginx/error.log

# Docker logs
docker-compose -f /opt/vpn-management/docker-compose.yml logs
```

#### Common Log Patterns

```bash
# Failed VPN connections
sudo grep "Invalid handshake" /var/log/kern.log

# Failed SSH attempts
sudo grep "Failed password" /var/log/auth.log

# Nginx errors
sudo grep "error" /var/log/nginx/error.log

# Database connection issues
docker-compose -f /opt/vpn-management/docker-compose.yml logs db | grep ERROR
```

## Monitoring and Alerts

### Key Metrics to Monitor

1. **VPN Server Health**
   - Active connections
   - Handshake success rate
   - Bandwidth utilization
   - CPU/Memory usage

2. **Management Interface**
   - API response times
   - Error rates
   - Authentication failures
   - Database connections

3. **System Health**
   - Disk usage
   - Network throughput
   - Load average
   - Certificate expiration

### Setting Up Alerts

#### Grafana Alerts

1. Navigate to Grafana dashboard
2. Create alert rules for:
   - High CPU usage (>80%)
   - High memory usage (>90%)
   - VPN server down
   - Certificate expiration (30 days)
   - Failed authentication spike

#### Prometheus Alerts

Edit `/opt/vpn-management/config/prometheus/alert_rules.yml`:

```yaml
groups:
  - name: custom_alerts
    rules:
      - alert: HighConnectionFailures
        expr: rate(wireguard_handshake_failures[5m]) > 0.1
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High WireGuard connection failure rate"
```

### Dashboard Customization

#### Key Dashboards

1. **VPN Overview**
   - Total users
   - Active connections
   - Bandwidth usage
   - Geographic distribution

2. **System Health**
   - CPU/Memory/Disk usage
   - Network statistics
   - Service uptime
   - Error rates

3. **Security Monitoring**
   - Failed login attempts
   - Blocked IPs (fail2ban)
   - Certificate status
   - Unusual traffic patterns

## Maintenance Procedures

### Weekly Maintenance

#### System Updates

```bash
# Update packages
sudo apt update && sudo apt upgrade -y

# Update Docker images
cd /opt/vpn-management
sudo docker-compose pull
sudo docker-compose up -d

# Restart services if needed
sudo systemctl restart nginx
sudo systemctl restart wg-quick@wg0
```

#### Security Review

```bash
# Check fail2ban status
sudo fail2ban-client status

# Review blocked IPs
sudo fail2ban-client status sshd

# Check for unusual connections
sudo wg show all

# Review authentication logs
sudo grep "authentication failure" /var/log/auth.log | tail -20
```

### Monthly Maintenance

#### Certificate Management

```bash
# Check certificate expiration
openssl x509 -in /etc/letsencrypt/live/your-domain.com/cert.pem -text -noout | grep "Not After"

# Renew certificates (if needed)
sudo certbot renew --dry-run
```

#### Database Maintenance

```bash
# Database cleanup (if applicable)
cd /opt/vpn-management
docker-compose exec db psql -U postgres -d vpn_management -c "
  DELETE FROM audit_logs WHERE timestamp < NOW() - INTERVAL '7 days';
"

# Vacuum database
docker-compose exec db psql -U postgres -d vpn_management -c "VACUUM ANALYZE;"
```

#### Configuration Backup

```bash
# Backup configurations
sudo tar -czf /tmp/vpn-config-backup-$(date +%Y%m%d).tar.gz \
  /etc/wireguard/ \
  /opt/vpn-management/config/ \
  /etc/nginx/sites-available/

# Store backup securely (implement your backup strategy)
```

### Quarterly Maintenance

#### Security Audit

1. Review access logs
2. Update security configurations
3. Test incident response procedures
4. Review and update documentation

#### Performance Optimization

1. Analyze performance metrics
2. Optimize configurations
3. Plan capacity upgrades
4. Review cost optimization

## Emergency Procedures

### Service Outage

#### Immediate Response

1. **Assess Impact**
   ```bash
   # Check service status
   sudo systemctl status wg-quick@wg0
   sudo docker-compose -f /opt/vpn-management/docker-compose.yml ps
   
   # Check system resources
   df -h
   free -m
   ```

2. **Notify Stakeholders**
   - Update status page
   - Send notifications to users
   - Escalate if needed

3. **Investigate Root Cause**
   - Check logs
   - Review monitoring data
   - Identify failure point

#### Recovery Procedures

1. **Service Recovery**
   ```bash
   # Restart failed services
   sudo systemctl restart wg-quick@wg0
   cd /opt/vpn-management && sudo docker-compose restart
   
   # Verify recovery
   curl -s https://vpn-mgmt.your-domain.com/health
   ```

2. **Verify Full Functionality**
   - Test VPN connections
   - Verify management interface
   - Check monitoring systems

### Security Incident

#### Immediate Response

1. **Isolate Affected Systems**
   ```bash
   # If server compromise suspected
   sudo ufw deny in
   sudo systemctl stop nginx
   ```

2. **Preserve Evidence**
   - Take memory dumps if needed
   - Copy relevant logs
   - Document timeline

3. **Assess Damage**
   - Check for unauthorized access
   - Review user accounts
   - Analyze network traffic

#### Recovery

1. **Clean and Rebuild**
   - Rebuild compromised systems
   - Rotate all keys and certificates
   - Reset all user passwords

2. **Strengthen Security**
   - Update security configurations
   - Implement additional monitoring
   - Review access controls

### Data Breach Response

#### Immediate Actions

1. **Contain the Breach**
2. **Assess Data Exposure**
3. **Document Everything**
4. **Notify Authorities** (if required by regulation)

#### User Communication

1. **Prepare Communication**
2. **Notify Affected Users**
3. **Provide Remediation Steps**
4. **Offer Support**

## Backup and Recovery

### Backup Strategy

#### Daily Backups

```bash
#!/bin/bash
# Daily backup script

BACKUP_DIR="/opt/backups/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# Configuration files
tar -czf "$BACKUP_DIR/configs.tar.gz" \
  /etc/wireguard/ \
  /opt/vpn-management/config/

# Database backup
cd /opt/vpn-management
docker-compose exec -T db pg_dump -U postgres vpn_management > "$BACKUP_DIR/database.sql"

# Upload to S3 (example)
aws s3 sync /opt/backups/ s3://your-backup-bucket/vpn-backups/
```

#### Weekly Backups

- Full system snapshots
- AMI creation
- Cross-region replication

### Recovery Procedures

#### Database Recovery

```bash
# Restore database from backup
cd /opt/vpn-management
docker-compose exec -T db psql -U postgres -d vpn_management < backup/database.sql
```

#### Full System Recovery

1. **Launch New Infrastructure**
   ```bash
   cd terraform/
   terraform apply
   ```

2. **Restore Configurations**
   ```bash
   # Copy backup files to new servers
   scp -i ~/.ssh/vpn-keypair.pem backup/configs.tar.gz ubuntu@NEW_SERVER_IP:~/
   
   # Extract and apply
   ssh -i ~/.ssh/vpn-keypair.pem ubuntu@NEW_SERVER_IP
   sudo tar -xzf configs.tar.gz -C /
   ```

3. **Verify Recovery**
   - Test all services
   - Verify user access
   - Check monitoring

### Disaster Recovery Testing

#### Monthly Tests

- Backup restoration
- Service recovery
- Communication procedures

#### Quarterly Tests

- Full disaster recovery
- Cross-region failover
- Complete system rebuild

---

## Contact Information

**Primary Support:** support@your-company.com
**Emergency Line:** +1-XXX-XXX-XXXX
**Documentation:** https://docs.your-company.com/vpn

---

*This runbook should be kept up-to-date and reviewed regularly. All operators should be familiar with these procedures.*