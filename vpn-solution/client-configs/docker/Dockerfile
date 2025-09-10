# WireGuard VPN Client Docker Container
# Headless VPN client for containerized environments

FROM alpine:latest

# Install WireGuard and dependencies
RUN apk add --no-cache \
    wireguard-tools \
    iptables \
    ip6tables \
    curl \
    bind-tools \
    openresolv \
    procps \
    shadow

# Create wireguard user
RUN addgroup -g 1000 wireguard && \
    adduser -D -u 1000 -G wireguard -s /bin/sh wireguard

# Create necessary directories
RUN mkdir -p /etc/wireguard /var/log/wireguard && \
    chown -R wireguard:wireguard /etc/wireguard /var/log/wireguard && \
    chmod 700 /etc/wireguard

# Install health check script
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/healthcheck.sh

# Install entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Install connection monitor
COPY monitor.sh /usr/local/bin/monitor.sh
RUN chmod +x /usr/local/bin/monitor.sh

# Create configuration template
RUN cat > /etc/wireguard/wg0.conf.template << 'EOF'
[Interface]
PrivateKey = ${WG_PRIVATE_KEY}
Address = ${WG_ADDRESS}
DNS = ${WG_DNS:-1.1.1.1,1.0.0.1}
Table = ${WG_TABLE:-auto}

# Optional: Custom MTU
${WG_MTU:+MTU = ${WG_MTU}}

# Pre/Post connection scripts
PostUp = echo "$(date): VPN connected" >> /var/log/wireguard/connection.log
PostUp = iptables -A OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT && ip6tables -A OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
PreDown = iptables -D OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT && ip6tables -D OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
PreDown = echo "$(date): VPN disconnected" >> /var/log/wireguard/connection.log

[Peer]
PublicKey = ${WG_SERVER_PUBLIC_KEY}
Endpoint = ${WG_ENDPOINT}
AllowedIPs = ${WG_ALLOWED_IPS:-0.0.0.0/0,::/0}
PersistentKeepalive = ${WG_KEEPALIVE:-25}
EOF

# Set environment variables
ENV WG_INTERFACE=wg0
ENV WG_DNS=1.1.1.1,1.0.0.1
ENV WG_ALLOWED_IPS=0.0.0.0/0,::/0
ENV WG_KEEPALIVE=25
ENV WG_TABLE=auto
ENV HEALTH_CHECK_INTERVAL=30
ENV LOG_LEVEL=INFO

# Expose health check port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

# Use non-root user by default
USER wireguard

# Set working directory
WORKDIR /home/wireguard

# Volume for configuration
VOLUME ["/etc/wireguard"]

# Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Default command
CMD ["wg0"]

# Labels
LABEL maintainer="VPN Operations Team"
LABEL description="WireGuard VPN Client Container"
LABEL version="1.0.0"
LABEL org.opencontainers.image.title="WireGuard VPN Client"
LABEL org.opencontainers.image.description="Headless WireGuard VPN client for containerized environments"
LABEL org.opencontainers.image.vendor="VPN Solution"
LABEL org.opencontainers.image.licenses="MIT"