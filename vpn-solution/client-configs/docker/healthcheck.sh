#!/bin/sh
# WireGuard Docker Container Health Check Script

# Check if health check server is responding
if curl -f -s http://localhost:8080/health > /dev/null 2>&1; then
    exit 0
else
    exit 1
fi