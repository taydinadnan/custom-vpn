# Android WireGuard Setup Guide

This guide explains how to set up WireGuard VPN on Android devices.

## Prerequisites

- Android 5.0 (API level 21) or later
- WireGuard app from Google Play Store
- VPN configuration from your administrator

## Installation Steps

### Step 1: Install WireGuard App

1. Open **Google Play Store**
2. Search for **"WireGuard"**
3. Install the official WireGuard app (by WireGuard Development Team)
4. Open the app once installed

### Step 2: Import Configuration

You can import your VPN configuration using one of these methods:

#### Method A: QR Code (Recommended)

1. Open the **WireGuard app**
2. Tap the **"+"** (plus) button in the bottom-right corner
3. Select **"Scan from QR code"**
4. Grant camera permission if prompted
5. Point your camera at the QR code provided by your administrator
6. Enter a name for your tunnel (e.g., "Company VPN")
7. Tap **"Create Tunnel"**

#### Method B: Configuration File

1. Download the `.conf` file from your administrator
2. Open the **WireGuard app**
3. Tap the **"+"** button
4. Select **"Import from file or archive"**
5. Navigate to and select your configuration file
6. Enter a name for your tunnel
7. Tap **"Create Tunnel"**

#### Method C: Manual Entry

1. Open the **WireGuard app**
2. Tap the **"+"** button
3. Select **"Create from scratch"**
4. Fill in the configuration details:

**Interface Section:**
- **Name**: Choose a name for your VPN
- **Private key**: Your unique private key
- **Addresses**: Your VPN IP address (e.g., 10.8.0.2/32)
- **DNS servers**: 1.1.1.1, 1.0.0.1
- **MTU**: Leave empty (optional)

**Peer Section:**
- **Public key**: Server's public key
- **Endpoint**: Server address and port (e.g., vpn.example.com:51820)
- **Allowed IPs**: 0.0.0.0/0, ::/0 (for full tunnel)
- **Persistent keepalive**: 25

5. Tap **"Save"** (diskette icon)

## Connecting to VPN

### Connect

1. Open the **WireGuard app**
2. Find your VPN configuration in the list
3. Tap the **toggle switch** next to your VPN name
4. The first time you connect, Android will ask for VPN permission
5. Tap **"OK"** to grant permission
6. Once connected, you'll see a key icon in your notification bar

### Disconnect

1. Open the **WireGuard app**
2. Tap the **toggle switch** next to your VPN name to turn it off
3. Alternatively, tap the VPN notification and select "Disconnect"

## Managing VPN Connection

### Quick Settings Tile (Android 7+)

Add WireGuard to your Quick Settings for easy access:

1. Pull down the notification shade twice to access Quick Settings
2. Tap the **edit/pencil** icon
3. Drag the **WireGuard** tile to your active tiles
4. Now you can toggle VPN from Quick Settings

### Always-On VPN (Android 7+)

Configure WireGuard to connect automatically:

1. Go to **Settings > Network & Internet > VPN**
2. Tap the **gear icon** next to WireGuard
3. Enable **"Always-on VPN"**
4. Enable **"Block connections without VPN"** for maximum security

### Per-App VPN (Android 5+)

Route only specific apps through the VPN:

1. In the WireGuard app, tap your tunnel name
2. Tap the **edit** (pencil) icon
3. In the Interface section, tap **"Applications"**
4. Choose either:
   - **Include only**: Only selected apps use VPN
   - **Exclude**: All apps except selected ones use VPN
5. Select your desired apps
6. Save the configuration

## Advanced Configuration

### Split Tunneling

To route only specific traffic through VPN:

1. Edit your tunnel configuration
2. In the Peer section, change **"Allowed IPs"** from `0.0.0.0/0, ::/0` to specific networks
3. Examples:
   - `10.0.0.0/8` - Private networks only
   - `192.168.1.0/24` - Specific subnet
   - `8.8.8.8/32` - Specific server

### Custom DNS

To use different DNS servers:

1. Edit your tunnel configuration
2. In the Interface section, modify **"DNS servers"**
3. Examples:
   - `8.8.8.8, 8.8.4.4` - Google DNS
   - `1.1.1.1, 1.0.0.1` - Cloudflare DNS
   - `9.9.9.9` - Quad9 DNS

### On-Demand Rules

Some Android versions support on-demand activation:

1. Edit tunnel configuration
2. Look for **"On-demand rules"** or similar option
3. Configure rules for:
   - Specific WiFi networks
   - Cellular connections
   - Roaming status

## Troubleshooting

### Connection Issues

**Problem**: Cannot connect to VPN
**Solutions**:
- Check internet connection
- Verify server endpoint is reachable
- Ensure configuration is correct
- Try toggling airplane mode on/off
- Restart the app

**Problem**: VPN connects but no internet
**Solutions**:
- Check DNS settings (try 1.1.1.1, 1.0.0.1)
- Verify "Allowed IPs" includes 0.0.0.0/0
- Check if your ISP blocks VPN traffic
- Try different server endpoint if available

**Problem**: Frequent disconnections
**Solutions**:
- Enable "Always-on VPN" in Android settings
- Check "Persistent keepalive" is set to 25
- Disable battery optimization for WireGuard app
- Check for aggressive power management settings

### Performance Issues

**Problem**: Slow speeds
**Solutions**:
- Test speed without VPN for comparison
- Try different server locations
- Check MTU settings (try 1280 if having issues)
- Disable QoS or traffic shaping on your router

**Problem**: High battery usage
**Solutions**:
- This is normal with VPN usage
- Use per-app VPN to limit which apps use VPN
- Consider using on-demand activation
- Optimize other battery-draining apps

### App-Specific Issues

**Problem**: Some apps don't work with VPN
**Solutions**:
- Use "Exclude" option in per-app VPN settings
- Some banking/streaming apps detect VPN usage
- Try split tunneling for problematic apps
- Contact app developer about VPN compatibility

**Problem**: VPN permission denied
**Solutions**:
- Go to Settings > Apps > WireGuard > Permissions
- Ensure all necessary permissions are granted
- Clear app data and reconfigure if needed

## Security Best Practices

### Configuration Security

- **Never share** your private key or configuration
- **Use unique configurations** for each device
- **Delete old configurations** when changing servers
- **Report lost devices** to administrator immediately

### Network Security

- **Always verify** you're connected before transmitting sensitive data
- **Check your IP address** periodically: https://whatismyipaddress.com
- **Be cautious** on public WiFi even with VPN
- **Keep the app updated** for latest security fixes

### Privacy Settings

1. In WireGuard app, tap **"..."** menu
2. Go to **Settings**
3. Consider these privacy options:
   - **Log level**: Set to "Silent" for privacy
   - **Kernel module**: Use if available for better performance
   - **Allow remote control intents**: Disable for security

## Battery Optimization

### Disable Battery Optimization

To prevent Android from killing the VPN:

1. Go to **Settings > Battery > Battery Optimization**
2. Find **WireGuard** in the list
3. Select **"Don't optimize"**
4. Confirm the change

### Doze Mode Whitelist

For Android 6+:

1. Go to **Settings > Battery > Battery Optimization**
2. Tap **"All apps"** dropdown
3. Find and select **WireGuard**
4. Choose **"Don't optimize"**

## Backup and Restore

### Export Configurations

1. Open WireGuard app
2. Tap **"..."** menu
3. Select **"Export tunnels to zip file"**
4. Save the backup file securely

### Import Backup

1. Open WireGuard app
2. Tap **"+"** button
3. Select **"Import from file or archive"**
4. Choose your backup zip file
5. Select which tunnels to import

## Automation

### Tasker Integration

If you use Tasker, you can automate VPN connections:

1. Create new Tasker profile
2. Add action: **Plugin > WireGuard**
3. Configure tunnel name and desired state
4. Set up triggers (location, time, WiFi network, etc.)

### IFTTT Integration

Some third-party apps may support WireGuard automation through IFTTT.

## Uninstalling

To completely remove WireGuard:

1. Disconnect from all VPN tunnels
2. Delete all tunnel configurations
3. Go to **Settings > Network & Internet > VPN**
4. Remove any remaining WireGuard profiles
5. Uninstall the WireGuard app

## Getting Help

### View Connection Statistics

1. Open WireGuard app
2. Tap your active tunnel name
3. View details:
   - **Status**: Connection state
   - **Latest handshake**: Last server communication
   - **Transfer**: Data sent/received
   - **Peer**: Server information

### Export Logs

1. In WireGuard app, tap **"..."** menu
2. Select **"Export log file"**
3. Choose how to share (email, messaging, etc.)
4. Send to your administrator or support team

### Common Log Entries

- **Handshake did not complete**: Server communication issues
- **Peer did not respond**: Server may be down
- **Permission denied**: Android VPN permission issue
- **Network unreachable**: Internet connectivity problem

### Contact Support

When contacting support, provide:
- Android version and device model
- WireGuard app version
- Configuration details (without private keys)
- Log files if requested
- Steps to reproduce the issue

---

*This guide is based on WireGuard Android app version 1.0+. Some features may vary based on Android version and device manufacturer.*