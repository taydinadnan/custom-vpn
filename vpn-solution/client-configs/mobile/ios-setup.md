# iOS WireGuard Setup Guide

This guide explains how to set up WireGuard VPN on iOS devices (iPhone and iPad).

## Prerequisites

- iOS 12.0 or later
- WireGuard app from the App Store
- VPN configuration from your administrator

## Installation Steps

### Step 1: Install WireGuard App

1. Open the **App Store** on your iOS device
2. Search for **"WireGuard"**
3. Install the official WireGuard app (by WireGuard Development Team)
4. Wait for installation to complete

### Step 2: Import Configuration

You can import your VPN configuration using one of these methods:

#### Method A: QR Code (Recommended)

1. Open the **WireGuard app**
2. Tap the **"+"** button in the top-right corner
3. Select **"Create from QR code"**
4. Point your camera at the QR code provided by your administrator
5. The configuration will be imported automatically
6. Give your tunnel a name (e.g., "Company VPN")
7. Tap **"Save"**

#### Method B: Configuration File

1. Receive the `.conf` file from your administrator (via email, AirDrop, etc.)
2. Open the configuration file
3. Select **"Copy to WireGuard"** when prompted
4. The WireGuard app will open with the configuration loaded
5. Give your tunnel a name
6. Tap **"Save"**

#### Method C: Manual Entry

1. Open the **WireGuard app**
2. Tap the **"+"** button
3. Select **"Create from scratch"**
4. Enter the configuration details provided by your administrator:
   - **Name**: Choose a name for your VPN
   - **Private Key**: Your unique private key
   - **Public Key**: (will be generated automatically)
   - **Addresses**: Your VPN IP address (e.g., 10.8.0.2/32)
   - **DNS Servers**: 1.1.1.1, 1.0.0.1
   - **MTU**: Leave empty (optional)
   - **Peer Public Key**: Server's public key
   - **Endpoint**: Server address and port
   - **Allowed IPs**: 0.0.0.0/0, ::/0 (for full tunnel)
   - **Persistent Keepalive**: 25
5. Tap **"Save"**

## Connecting to VPN

### Connect

1. Open the **WireGuard app**
2. Find your VPN configuration in the list
3. Toggle the switch next to your VPN name to **ON**
4. The first time you connect, iOS will ask for permission to add VPN configurations
5. Tap **"Allow"** and authenticate with Face ID, Touch ID, or passcode
6. Once connected, you'll see a VPN icon in your status bar

### Disconnect

1. Open the **WireGuard app**
2. Toggle the switch next to your VPN name to **OFF**
3. Alternatively, you can disconnect from **Settings > VPN**

## Managing VPN Connection

### Using iOS Settings

After setting up WireGuard, you can also manage the connection through iOS Settings:

1. Go to **Settings > VPN & Device Management > VPN**
2. You'll see your WireGuard configuration listed
3. Tap the **toggle switch** to connect/disconnect
4. Tap the **"i"** button for more options

### On-Demand Connection

You can configure WireGuard to connect automatically:

1. In the WireGuard app, tap your configuration name
2. Tap **"Edit"**
3. Scroll to **"On-Demand Activation"**
4. Configure rules for automatic connection:
   - **WiFi**: Connect when on specific WiFi networks
   - **Cellular**: Connect when using cellular data
   - **Ethernet**: Connect when using wired connection (iPad with adapter)

## Troubleshooting

### Connection Issues

**Problem**: Cannot connect to VPN
**Solutions**:
- Check your internet connection
- Verify the server endpoint is correct
- Ensure your configuration is up-to-date
- Try toggling the VPN off and on again

**Problem**: Connected but no internet access
**Solutions**:
- Check DNS settings (should be 1.1.1.1, 1.0.0.1)
- Verify "Allowed IPs" is set to 0.0.0.0/0, ::/0
- Restart the WireGuard app
- Contact your administrator

### Performance Issues

**Problem**: Slow connection speeds
**Solutions**:
- Try different server endpoints if available
- Check if other apps are consuming bandwidth
- Restart your device
- Move closer to your WiFi router

**Problem**: Battery drain
**Solutions**:
- This is normal when VPN is active
- Consider using on-demand activation
- Disconnect when not needed

### Configuration Issues

**Problem**: QR code won't scan
**Solutions**:
- Ensure good lighting
- Clean your camera lens
- Try holding the phone steadier
- Use configuration file method instead

**Problem**: Configuration file won't import
**Solutions**:
- Ensure file has .conf extension
- Try sending via different method (email, AirDrop)
- Check file isn't corrupted
- Contact administrator for new configuration

## Security Best Practices

### Keep Configuration Secure

- **Never share** your private key or configuration file
- **Delete old configurations** when no longer needed
- **Use unique configurations** for each device
- **Report lost devices** to your administrator immediately

### Monitor Connection

- Check the VPN icon in your status bar to ensure connection
- Verify your IP address occasionally: https://whatismyipaddress.com
- Be aware of which networks trigger automatic connection

### App Settings

1. Open **Settings > WireGuard**
2. Review privacy settings:
   - **Log Level**: Set to minimal for privacy
   - **Export Configuration**: Disable if not needed

## Advanced Features

### Multiple Configurations

You can have multiple VPN configurations:
- Different servers for different purposes
- Separate work and personal VPNs
- Backup configurations

### Shortcuts Integration

iOS 13+ supports Siri Shortcuts for WireGuard:
1. Go to **Settings > Siri & Search**
2. Find **WireGuard** in the app list
3. Set up voice commands for connecting/disconnecting

### Widget Support

Add WireGuard widget to your Today View:
1. Swipe right from home screen or lock screen
2. Scroll to bottom and tap **"Edit"**
3. Add **WireGuard** widget
4. Quickly toggle VPN from widget

## Limitations

### iOS Restrictions

- Only one VPN can be active at a time
- VPN may disconnect during calls (carrier dependent)
- Some apps may detect and block VPN usage
- Personal Hotspot may not work with VPN active

### Battery Impact

- VPN usage will impact battery life
- Effect varies based on usage patterns
- Consider using Low Power Mode when needed

## Getting Help

### Check Connection Status

1. Open WireGuard app
2. Tap your configuration name
3. View connection statistics:
   - **Status**: Connected/Disconnected
   - **Latest Handshake**: When last connected to server
   - **Transfer**: Data sent/received

### Export Logs (for troubleshooting)

1. Open WireGuard app
2. Tap **"..."** in top-right corner
3. Select **"Export log file"**
4. Send to your administrator or support team

### Contact Support

If you continue experiencing issues:
- Contact your VPN administrator
- Provide device model and iOS version
- Include any error messages
- Export and send log files if requested

## Uninstalling

To completely remove WireGuard VPN:

1. Open WireGuard app
2. Delete all configurations (swipe left and tap delete)
3. Go to **Settings > General > VPN & Device Management**
4. Remove any remaining VPN profiles
5. Delete the WireGuard app from your device

---

*This guide covers WireGuard app version 1.0+. Interface may vary slightly with updates.*