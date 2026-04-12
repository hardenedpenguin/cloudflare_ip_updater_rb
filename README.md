# Cloudflare IP Updater

A Ruby-based Debian package that monitors your external IP address and automatically updates your Cloudflare DNS records when it changes. Uses systemd timer for scheduling.

## Features

- ✅ Checks external IP every 3 hours via systemd timer
- ✅ Automatically updates Cloudflare DNS when IP changes
- ✅ Supports root domain (@) and subdomains
- ✅ Auto-detects Zone ID and DNS Record ID if not provided
- ✅ Uses multiple IP check services for reliability
- ✅ Stores last known IP to avoid unnecessary updates
- ✅ Systemd service integration with journal logging
- ✅ Uses only Ruby standard library (no gems required!)
- ✅ Proper Debian package structure

## Prerequisites

- Debian/Ubuntu system with systemd
- Ruby 2.0 or higher
- Cloudflare account with domain
- Cloudflare API token (see setup below)

## Getting Cloudflare API Token

1. Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Click "Create Token"
3. Use the "Edit zone DNS" template, or create a custom token with:
   - **Permissions**: Zone:Zone:Read, Zone:DNS:Edit
   - **Zone Resources**: Include - Specific zone - [your domain]
4. Copy the generated API token

⚠️ **Important**: Save the token immediately - it won't be shown again!

## Installation

1. **Download and install the package**:
   ```bash
   cd /tmp
   wget https://github.com/hardenedpenguin/cloudflare_ip_updater_rb/releases/download/v1.0.0/cloudflare-ip-updater_1.0.0-1_all.deb
   sudo apt install ./cloudflare-ip-updater_1.0.0-1_all.deb
   ```

   The `apt install` command will automatically handle dependencies and install `ruby` and `systemd` if they are not already installed.

## Configuration

Edit the configuration file with your Cloudflare API token:

```bash
sudo nano /etc/cloudflare-ip-updater/config
```

Set your API token and domain:
- `CLOUDFLARE_API_TOKEN` - Your Cloudflare API token (required)
- `DOMAIN` - Your domain name (e.g., example.com) (required)
- `DNS_RECORD_NAME` - DNS record name (@ for root, or subdomain)
- `DNS_RECORD_TYPE` - DNS record type (usually A)
- `CLOUDFLARE_ZONE_ID` - Zone ID (optional, auto-detected if not provided)
- `CLOUDFLARE_DNS_RECORD_ID` - DNS Record ID (optional, auto-detected if not provided)

## Usage

Enable and start the service:

```bash
sudo systemctl enable cloudflare-ip-updater.service
sudo systemctl enable --now cloudflare-ip-updater.timer
```

The timer will trigger every 3 hours automatically.

**Check status**: `sudo systemctl status cloudflare-ip-updater.timer`  
**View logs**: `sudo journalctl -u cloudflare-ip-updater.service -f`  
**Manual check**: `sudo systemctl start cloudflare-ip-updater.service`

## Troubleshooting

Check logs for errors: `sudo journalctl -u cloudflare-ip-updater.service`

Common issues:
- **Configuration file not found**: Ensure `/etc/cloudflare-ip-updater/config` exists
- **Unable to determine external IP**: Check internet connection and logs
- **Cloudflare API error**: Verify API token has correct permissions (Zone:Zone:Read, Zone:DNS:Edit)
- **Timer not running**: Check status with `sudo systemctl status cloudflare-ip-updater.timer`

## License

This script is provided as-is for personal use. Feel free to modify and adapt it to your needs.
