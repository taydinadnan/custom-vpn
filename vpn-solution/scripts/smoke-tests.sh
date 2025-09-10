#!/bin/bash
# Smoke Tests for VPN Solution
# Quick validation tests for production deployment

set -euo pipefail

# Configuration
ENVIRONMENT="${1:-production}"
TIMEOUT=10

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
pass() { 
    echo -e "${GREEN}✓ $1${NC}"
    ((TESTS_PASSED++))
}

fail() { 
    echo -e "${RED}✗ $1${NC}"
    ((TESTS_FAILED++))
}

warn() { 
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Load configuration
if [[ -f "terraform-outputs.json" ]]; then
    VPN_ENDPOINT=$(jq -r '.wireguard_server_endpoint.value' terraform-outputs.json)
    MGMT_URL=$(jq -r '.management_interface_url.value' terraform-outputs.json)
else
    fail "Terraform outputs not found"
    exit 1
fi

echo "🔍 Running smoke tests for $ENVIRONMENT environment"
echo "🎯 VPN Endpoint: $VPN_ENDPOINT"
echo "🎯 Management URL: $MGMT_URL"
echo

# Test 1: VPN server reachability
echo "Testing VPN server reachability..."
VPN_HOST=$(echo "$VPN_ENDPOINT" | cut -d: -f1)
VPN_PORT=$(echo "$VPN_ENDPOINT" | cut -d: -f2)

if nc -z -w$TIMEOUT "$VPN_HOST" "$VPN_PORT" 2>/dev/null; then
    pass "VPN server port $VPN_PORT is accessible"
else
    fail "VPN server port $VPN_PORT is not accessible"
fi

# Test 2: Management interface health
echo "Testing management interface health..."
if curl -k -s --max-time $TIMEOUT "$MGMT_URL/health" | grep -q "healthy"; then
    pass "Management interface is healthy"
else
    fail "Management interface health check failed"
fi

# Test 3: API documentation accessibility
echo "Testing API documentation..."
if curl -k -s --max-time $TIMEOUT "$MGMT_URL/api/docs" | grep -q "FastAPI\|OpenAPI"; then
    pass "API documentation is accessible"
else
    fail "API documentation is not accessible"
fi

# Test 4: SSL certificate validity
echo "Testing SSL certificate..."
CERT_DAYS=$(echo | openssl s_client -connect "$(echo "$MGMT_URL" | sed 's/https:\/\///')":443 -servername "$(echo "$MGMT_URL" | sed 's/https:\/\///')" 2>/dev/null | openssl x509 -noout -checkend 2592000 2>/dev/null && echo "valid" || echo "invalid")

if [[ "$CERT_DAYS" == "valid" ]]; then
    pass "SSL certificate is valid for next 30 days"
else
    fail "SSL certificate expires within 30 days or is invalid"
fi

# Test 5: Monitoring endpoints
echo "Testing monitoring endpoints..."
if curl -k -s --max-time $TIMEOUT "$MGMT_URL/prometheus/api/v1/query?query=up" | grep -q "success"; then
    pass "Prometheus is responding"
else
    fail "Prometheus is not responding"
fi

if curl -k -s --max-time $TIMEOUT "$MGMT_URL/grafana/api/health" | grep -q "ok"; then
    pass "Grafana is responding"
else
    warn "Grafana health check failed (may not be critical)"
fi

# Results
echo
echo "📊 Test Results:"
echo "   Passed: $TESTS_PASSED"
echo "   Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}🎉 All smoke tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ $TESTS_FAILED test(s) failed${NC}"
    exit 1
fi