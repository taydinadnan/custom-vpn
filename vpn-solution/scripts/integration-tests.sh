#!/bin/bash
# Integration Test Suite for VPN Solution
# Tests complete functionality across all components

set -euo pipefail

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_ENVIRONMENT="${1:-staging}"
LOG_FILE="/tmp/vpn-integration-tests-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}" | tee -a "$LOG_FILE"
}

# Test result functions
test_start() {
    local test_name="$1"
    info "Starting test: $test_name"
    ((TESTS_TOTAL++))
}

test_pass() {
    local test_name="$1"
    log "✓ PASSED: $test_name"
    ((TESTS_PASSED++))
}

test_fail() {
    local test_name="$1"
    local reason="$2"
    error "✗ FAILED: $test_name - $reason"
    ((TESTS_FAILED++))
}

# Load test configuration
load_config() {
    log "Loading test configuration for environment: $TEST_ENVIRONMENT"
    
    # Load Terraform outputs
    if [[ -f "$PROJECT_ROOT/terraform-outputs.json" ]]; then
        VPN_ENDPOINT=$(jq -r '.wireguard_server_endpoint.value' "$PROJECT_ROOT/terraform-outputs.json")
        MGMT_URL=$(jq -r '.management_interface_url.value' "$PROJECT_ROOT/terraform-outputs.json")
        MGMT_IP=$(jq -r '.management_public_ip.value' "$PROJECT_ROOT/terraform-outputs.json")
    else
        error "Terraform outputs not found. Run terraform output -json > terraform-outputs.json"
        exit 1
    fi
    
    # Test credentials (should be secure in production)
    API_TOKEN="demo-token"
    SSH_KEY="$HOME/.ssh/vpn-keypair.pem"
    
    log "Configuration loaded:"
    log "  VPN Endpoint: $VPN_ENDPOINT"
    log "  Management URL: $MGMT_URL"
    log "  Management IP: $MGMT_IP"
}

# Infrastructure tests
test_infrastructure() {
    log "Running infrastructure tests..."
    
    # Test 1: VPN server port accessibility
    test_start "VPN Server Port Accessibility"
    local vpn_host=$(echo "$VPN_ENDPOINT" | cut -d: -f1)
    local vpn_port=$(echo "$VPN_ENDPOINT" | cut -d: -f2)
    
    if nc -z -w5 "$vpn_host" "$vpn_port"; then
        test_pass "VPN Server Port Accessibility"
    else
        test_fail "VPN Server Port Accessibility" "Port $vpn_port not accessible on $vpn_host"
    fi
    
    # Test 2: Management server SSH accessibility
    test_start "Management Server SSH"
    if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$MGMT_IP" "echo 'SSH OK'" &>/dev/null; then
        test_pass "Management Server SSH"
    else
        test_fail "Management Server SSH" "Cannot connect via SSH to $MGMT_IP"
    fi
    
    # Test 3: Management interface HTTPS
    test_start "Management Interface HTTPS"
    if curl -k -s --max-time 10 "$MGMT_URL" | grep -q "VPN Management" || curl -k -s --max-time 10 "$MGMT_URL/health" &>/dev/null; then
        test_pass "Management Interface HTTPS"
    else
        test_fail "Management Interface HTTPS" "Management interface not responding on $MGMT_URL"
    fi
}

# API tests
test_api() {
    log "Running API tests..."
    
    # Test 1: Health endpoint
    test_start "API Health Endpoint"
    local health_response=$(curl -k -s --max-time 10 "$MGMT_URL/api/health" || echo "ERROR")
    
    if echo "$health_response" | grep -q "healthy"; then
        test_pass "API Health Endpoint"
    else
        test_fail "API Health Endpoint" "Health endpoint returned: $health_response"
    fi
    
    # Test 2: API Documentation
    test_start "API Documentation"
    if curl -k -s --max-time 10 "$MGMT_URL/api/docs" | grep -q "FastAPI" || curl -k -s --max-time 10 "$MGMT_URL/api/openapi.json" &>/dev/null; then
        test_pass "API Documentation"
    else
        test_fail "API Documentation" "API documentation not accessible"
    fi
    
    # Test 3: User creation
    test_start "User Creation API"
    local test_user_data='{"username":"testuser","email":"test@example.com"}'
    local create_response=$(curl -k -s --max-time 10 -X POST "$MGMT_URL/api/users" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$test_user_data" || echo "ERROR")
    
    if echo "$create_response" | grep -q "testuser"; then
        test_pass "User Creation API"
        # Store user ID for later tests
        TEST_USER_ID=$(echo "$create_response" | jq -r '.id' 2>/dev/null || echo "")
    else
        test_fail "User Creation API" "User creation failed: $create_response"
        TEST_USER_ID=""
    fi
    
    # Test 4: User listing
    test_start "User Listing API"
    local list_response=$(curl -k -s --max-time 10 "$MGMT_URL/api/users" \
        -H "Authorization: Bearer $API_TOKEN" || echo "ERROR")
    
    if echo "$list_response" | grep -q "testuser"; then
        test_pass "User Listing API"
    else
        test_fail "User Listing API" "User listing failed: $list_response"
    fi
    
    # Test 5: User configuration generation (if user was created)
    if [[ -n "$TEST_USER_ID" ]]; then
        test_start "User Configuration Generation"
        local config_response=$(curl -k -s --max-time 10 "$MGMT_URL/api/users/$TEST_USER_ID/config" \
            -H "Authorization: Bearer $API_TOKEN" || echo "ERROR")
        
        if echo "$config_response" | grep -q "Interface" && echo "$config_response" | grep -q "Peer"; then
            test_pass "User Configuration Generation"
        else
            test_fail "User Configuration Generation" "Configuration generation failed: $config_response"
        fi
    fi
}

# Monitoring tests
test_monitoring() {
    log "Running monitoring tests..."
    
    # Test 1: Prometheus metrics
    test_start "Prometheus Metrics"
    if curl -k -s --max-time 10 "$MGMT_URL/prometheus/api/v1/query?query=up" | grep -q "success"; then
        test_pass "Prometheus Metrics"
    else
        test_fail "Prometheus Metrics" "Prometheus not responding or no metrics available"
    fi
    
    # Test 2: Grafana interface
    test_start "Grafana Interface"
    if curl -k -s --max-time 10 "$MGMT_URL/grafana/api/health" | grep -q "ok" || curl -k -s --max-time 10 "$MGMT_URL/grafana/login" &>/dev/null; then
        test_pass "Grafana Interface"
    else
        test_fail "Grafana Interface" "Grafana not accessible"
    fi
    
    # Test 3: Node exporter metrics (on VPN servers)
    test_start "Node Exporter Metrics"
    # This is a simplified test - in practice, you'd query Prometheus for node metrics
    if curl -k -s --max-time 10 "$MGMT_URL/prometheus/api/v1/query?query=node_load1" | grep -q "success"; then
        test_pass "Node Exporter Metrics"
    else
        test_fail "Node Exporter Metrics" "Node exporter metrics not available"
    fi
}

# Security tests
test_security() {
    log "Running security tests..."
    
    # Test 1: SSL certificate validity
    test_start "SSL Certificate Validity"
    local cert_check=$(echo | openssl s_client -connect "$(echo "$MGMT_URL" | sed 's/https:\/\///')":443 -servername "$(echo "$MGMT_URL" | sed 's/https:\/\///')" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null || echo "ERROR")
    
    if echo "$cert_check" | grep -q "notAfter"; then
        test_pass "SSL Certificate Validity"
    else
        test_fail "SSL Certificate Validity" "SSL certificate check failed"
    fi
    
    # Test 2: API authentication
    test_start "API Authentication"
    local unauth_response=$(curl -k -s -o /dev/null -w "%{http_code}" "$MGMT_URL/api/users")
    
    if [[ "$unauth_response" == "401" ]] || [[ "$unauth_response" == "403" ]]; then
        test_pass "API Authentication"
    else
        test_fail "API Authentication" "API allows unauthenticated access (HTTP $unauth_response)"
    fi
    
    # Test 3: SSH key-based authentication
    test_start "SSH Key Authentication"
    if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o PasswordAuthentication=no ubuntu@"$MGMT_IP" "echo 'Key auth OK'" &>/dev/null; then
        test_pass "SSH Key Authentication"
    else
        test_fail "SSH Key Authentication" "SSH key authentication failed"
    fi
    
    # Test 4: Firewall configuration
    test_start "Firewall Configuration"
    local fw_status=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$MGMT_IP" "sudo ufw status" 2>/dev/null || echo "ERROR")
    
    if echo "$fw_status" | grep -q "Status: active"; then
        test_pass "Firewall Configuration"
    else
        test_fail "Firewall Configuration" "UFW firewall not active or accessible"
    fi
}

# Service tests
test_services() {
    log "Running service tests..."
    
    # Test 1: WireGuard service status
    test_start "WireGuard Service Status"
    local wg_status=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$MGMT_IP" "sudo systemctl is-active wg-quick@wg0" 2>/dev/null || echo "ERROR")
    
    if [[ "$wg_status" == "active" ]]; then
        test_pass "WireGuard Service Status"
    else
        test_fail "WireGuard Service Status" "WireGuard service not active: $wg_status"
    fi
    
    # Test 2: Docker services
    test_start "Docker Services"
    local docker_status=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$MGMT_IP" "sudo docker-compose -f /opt/vpn-management/docker-compose.yml ps --services --filter 'status=running' | wc -l" 2>/dev/null || echo "0")
    
    if [[ "$docker_status" -ge 3 ]]; then  # Expecting at least API, DB, Redis
        test_pass "Docker Services"
    else
        test_fail "Docker Services" "Expected running Docker services, found: $docker_status"
    fi
    
    # Test 3: Nginx service
    test_start "Nginx Service"
    local nginx_status=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$MGMT_IP" "sudo systemctl is-active nginx" 2>/dev/null || echo "ERROR")
    
    if [[ "$nginx_status" == "active" ]]; then
        test_pass "Nginx Service"
    else
        test_fail "Nginx Service" "Nginx service not active: $nginx_status"
    fi
    
    # Test 4: Fail2ban service
    test_start "Fail2ban Service"
    local fail2ban_status=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$MGMT_IP" "sudo systemctl is-active fail2ban" 2>/dev/null || echo "ERROR")
    
    if [[ "$fail2ban_status" == "active" ]]; then
        test_pass "Fail2ban Service"
    else
        test_fail "Fail2ban Service" "Fail2ban service not active: $fail2ban_status"
    fi
}

# Performance tests
test_performance() {
    log "Running performance tests..."
    
    # Test 1: API response time
    test_start "API Response Time"
    local response_time=$(curl -k -s -o /dev/null -w "%{time_total}" "$MGMT_URL/api/health")
    local response_time_ms=$(echo "$response_time * 1000" | bc)
    
    if (( $(echo "$response_time < 2.0" | bc -l) )); then
        test_pass "API Response Time (${response_time_ms}ms)"
    else
        test_fail "API Response Time" "Response time too slow: ${response_time_ms}ms"
    fi
    
    # Test 2: System resources
    test_start "System Resource Usage"
    local cpu_usage=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$MGMT_IP" "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1" 2>/dev/null || echo "100")
    
    if (( $(echo "$cpu_usage < 80" | bc -l) )); then
        test_pass "System Resource Usage (CPU: ${cpu_usage}%)"
    else
        test_fail "System Resource Usage" "High CPU usage: ${cpu_usage}%"
    fi
    
    # Test 3: Memory usage
    test_start "Memory Usage"
    local mem_usage=$(ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$MGMT_IP" "free | awk '/Mem:/ {printf \"%.2f\", \$3/\$2 * 100}'" 2>/dev/null || echo "100")
    
    if (( $(echo "$mem_usage < 85" | bc -l) )); then
        test_pass "Memory Usage (${mem_usage}%)"
    else
        test_fail "Memory Usage" "High memory usage: ${mem_usage}%"
    fi
}

# Cleanup test resources
cleanup_tests() {
    log "Cleaning up test resources..."
    
    # Delete test user if created
    if [[ -n "$TEST_USER_ID" ]]; then
        curl -k -s -X DELETE "$MGMT_URL/api/users/$TEST_USER_ID" \
            -H "Authorization: Bearer $API_TOKEN" &>/dev/null || true
        log "Test user deleted"
    fi
}

# Generate test report
generate_report() {
    log "Generating test report..."
    
    local success_rate=$((TESTS_PASSED * 100 / TESTS_TOTAL))
    
    cat > "/tmp/vpn-test-report-$(date +%Y%m%d-%H%M%S).json" << EOF
{
    "test_run": {
        "timestamp": "$(date -Iseconds)",
        "environment": "$TEST_ENVIRONMENT",
        "duration": "$(date -d@$(($(date +%s) - $(stat -c %Y "$LOG_FILE"))) -u +%H:%M:%S)"
    },
    "results": {
        "total_tests": $TESTS_TOTAL,
        "passed": $TESTS_PASSED,
        "failed": $TESTS_FAILED,
        "success_rate": $success_rate
    },
    "configuration": {
        "vpn_endpoint": "$VPN_ENDPOINT",
        "management_url": "$MGMT_URL",
        "management_ip": "$MGMT_IP"
    }
}
EOF
    
    log "Test Summary:"
    log "  Total Tests: $TESTS_TOTAL"
    log "  Passed: $TESTS_PASSED"
    log "  Failed: $TESTS_FAILED"
    log "  Success Rate: $success_rate%"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log "🎉 All tests passed! VPN solution is ready for production."
        return 0
    else
        error "❌ $TESTS_FAILED test(s) failed. Review issues before production deployment."
        return 1
    fi
}

# Main execution
main() {
    log "Starting VPN Solution Integration Tests"
    log "Environment: $TEST_ENVIRONMENT"
    log "Test log: $LOG_FILE"
    
    # Load configuration
    load_config
    
    # Run test suites
    test_infrastructure
    test_api
    test_monitoring
    test_security
    test_services
    test_performance
    
    # Cleanup and report
    cleanup_tests
    generate_report
}

# Execute main function
main "$@"