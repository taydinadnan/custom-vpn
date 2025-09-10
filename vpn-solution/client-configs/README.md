# VPN Client Configuration Guide

This directory contains configuration templates and setup guides for connecting to the VPN service across different platforms.

## Supported Platforms

- **Linux** (Ubuntu, Debian, CentOS, Fedora, Arch)
- **macOS** (Homebrew, Mac App Store)
- **Windows** (Official WireGuard client)
- **Android** (WireGuard app from Play Store)
- **iOS** (WireGuard app from App Store)
- **Docker** (Headless container client)

## Quick Setup

1. **Get your configuration**: Contact your VPN administrator or use the management interface
2. **Choose your platform**: Follow the appropriate setup guide
3. **Import configuration**: Use the provided QR code or configuration file
4. **Connect**: Start your VPN connection

## Configuration Files

Each platform has specific configuration requirements:

- `linux/` - Linux-specific setup scripts and configurations
- `macos/` - macOS setup instructions and configurations
- `windows/` - Windows setup guide and batch scripts
- `mobile/` - Android and iOS setup instructions
- `docker/` - Containerized VPN client setup

## Security Notes

- **Keep your private key secure**: Never share your private key or configuration file
- **Use QR codes for mobile**: Safest way to import configurations on mobile devices
- **Verify server public key**: Ensure you're connecting to the correct server
- **Enable kill switch**: Prevent traffic leaks when VPN disconnects

## Troubleshooting

Common issues and solutions:

1. **Connection fails**: Check server endpoint and firewall settings
2. **No internet access**: Verify DNS settings and allowed IPs
3. **Slow speeds**: Check for QoS settings and server load
4. **Mobile issues**: Ensure battery optimization is disabled for WireGuard app

## Support

For technical support:
- Check the troubleshooting guides in each platform directory
- Review logs for error messages
- Contact your VPN administrator with specific error details