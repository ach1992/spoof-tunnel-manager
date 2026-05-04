# Spoof Tunnel Manager

A simple interactive manager for [`ParsaKSH/spoof-tunnel`](https://github.com/ParsaKSH/spoof-tunnel), pinned to **spoof-tunnel v1.0.3**.

The goal is to make installation, offline deployment, configuration, key exchange, systemd service setup, logs, health checks, and X-UI integration easier without requiring users to manually edit large JSON files.

> Use this only on servers and networks you own or are authorized to operate. Spoof Tunnel requires raw sockets and IP spoofing capability on both sides.

## Features

- English interactive menu
- Targets **spoof-tunnel v1.0.3** only
- Fully offline install mode
- Online GitHub release install mode
- No package manager usage by default
- Does not update existing packages
- Reuses existing binaries unless you explicitly replace them
- Automatic server/client key generation through the installed `spoof keygen`
- Copy/paste pairing blocks for easier two-server setup
- Generates client/server JSON configs
- Creates systemd services:
  - `spoof-client`
  - `spoof-server`
- Live logs through `journalctl`
- Basic health check
- X-UI SOCKS5 helper
- Config backup and restore
- Clean uninstall option

## Repository name suggestion

Recommended GitHub repository:

```bash
github.com/ach1992/spoof-tunnel-manager
```

## Files

```text
st-manager.sh   Main manager script
README.md       English documentation
README-fa.md    Persian documentation
assets/         Optional offline assets folder
examples/       Optional example files
```

## Quick online usage

After you publish this repository under your GitHub account:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ach1992/spoof-tunnel-manager/main/st-manager.sh)
```

Then choose:

```text
3) Install spoof v1.0.3 from GitHub release (online)
```

The manager tries to discover the correct v1.0.3 release asset for your architecture. If release discovery fails, it can fall back to source build only when `go` already exists on the server. It will not install Go or update packages.

## Offline usage

This is the recommended mode for servers without GitHub access.

1. On a machine with internet access, download this manager repository.
2. Download a compatible **spoof-tunnel v1.0.3** binary or release archive manually.
3. Create a folder, for example:

```bash
mkdir spoof-script
```

4. Put these files inside that folder:

```text
spoof-script/
├── st-manager.sh
└── spoof                 # or spoof-linux-amd64 / spoof-linux-arm64 / .tar.gz / .zip
```

You may also use:

```text
spoof-script/assets/spoof
```

5. Copy the folder to the server.
6. Run:

```bash
cd spoof-script
sudo bash st-manager.sh --install-offline
```

Or run the interactive menu:

```bash
sudo bash st-manager.sh
```

Then choose:

```text
2) Install spoof v1.0.3 from local files (offline)
```

## Installed paths

```text
/usr/local/bin/st-manager
/usr/local/bin/spoof
/etc/spoof-tunnel/client.json
/etc/spoof-tunnel/server.json
/etc/spoof-tunnel/client.keys
/etc/spoof-tunnel/server.keys
/etc/spoof-tunnel/server.pending
/etc/spoof-tunnel/server.pairing
/etc/spoof-tunnel/client.pairing
/etc/spoof-tunnel/backups/
/var/log/spoof-tunnel/
/etc/systemd/system/spoof-client.service
/etc/systemd/system/spoof-server.service
```

## Recommended three-step setup flow

This is the easiest flow and avoids manually entering public keys.

### 1) Foreign/server side: generate SERVER pairing

Run:

```bash
sudo st-manager
```

Choose:

```text
4) Server Step 1: generate SERVER pairing
```

The manager automatically generates or reuses the server key pair, asks for server-side values, and prints a block like:

```text
-----BEGIN SPOOF-TUNNEL SERVER PAIRING-----
VERSION=v1.0.3
ROLE=server
TRANSPORT=udp
SERVER_REAL_IP=1.2.3.4
SERVER_PORT=8080
SERVER_SPOOF_IP=185.143.233.151
SERVER_PUBLIC_KEY=...
-----END SPOOF-TUNNEL SERVER PAIRING-----
```

Copy this full block to the Iran/client server.

### 2) Iran/client side: configure from SERVER pairing

Run:

```bash
sudo st-manager
```

Choose:

```text
5) Client Step 2: configure from SERVER pairing
```

Paste the SERVER pairing block. The manager automatically fills the server IP, tunnel port, server spoof IP, and server public key. It then generates the client key pair, writes `client.json`, creates the `spoof-client` service, and prints a block like:

```text
-----BEGIN SPOOF-TUNNEL CLIENT PAIRING-----
VERSION=v1.0.3
ROLE=client
TRANSPORT=udp
CLIENT_REAL_IP=91.223.116.96
CLIENT_SPOOF_IP=2.188.21.151
CLIENT_PUBLIC_KEY=...
LOCAL_SOCKS=127.0.0.1:1080
-----END SPOOF-TUNNEL CLIENT PAIRING-----
```

Copy this full block back to the foreign/server side.

### 3) Foreign/server side: finalize from CLIENT pairing

Run:

```bash
sudo st-manager
```

Choose:

```text
6) Server Step 3: finalize from CLIENT pairing
```

Paste the CLIENT pairing block. The manager writes `server.json`, creates the `spoof-server` service, and the tunnel is ready to start.

### 4) Start services

On the foreign/server side:

```bash
sudo systemctl restart spoof-server
sudo systemctl status spoof-server --no-pager
```

On the Iran/client side:

```bash
sudo systemctl restart spoof-client
sudo systemctl status spoof-client --no-pager
```

Or use the menu:

```text
9) Start service
12) Service status
13) Live logs
14) Health check
```

## Manual setup mode

Manual mode still exists for advanced users:

```text
7) Manual configure as Client
8) Manual configure as Server
```

In manual mode you must already have the peer public key. For most users, use the three-step pairing flow instead.

## X-UI integration

On the source/client server, configure X-UI to use the local SOCKS5 endpoint created by spoof-tunnel:

```text
Protocol: SOCKS5
Address : 127.0.0.1
Port    : 1080
Username: empty
Password: empty
```

You can check the current endpoint with:

```bash
sudo st-manager --xui-helper
```

## Notes and limitations

- The script intentionally avoids `apt update`, `apt install`, package upgrades, and forced dependency installation.
- Online installation requires either `curl` or `wget` to already exist.
- Source build fallback requires `go` to already exist.
- Offline installation is the safest mode for restricted environments.
- Raw sockets require root or suitable capabilities.
- Both servers must be able to send spoofed packets, otherwise the tunnel will not work.

## Publish to GitHub

From the project folder:

```bash
git init
git add .
git commit -m "Initial Spoof Tunnel Manager"
git branch -M main
git remote add origin https://github.com/ach1992/spoof-tunnel-manager.git
git push -u origin main
```

Or, if you use GitHub CLI:

```bash
gh repo create ach1992/spoof-tunnel-manager --public --source=. --remote=origin --push
```
