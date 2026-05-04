# Spoof Tunnel Manager

A simple interactive manager for [`ParsaKSH/spoof-tunnel`](https://github.com/ParsaKSH/spoof-tunnel), pinned to **spoof-tunnel v1.0.3**.

The goal is to make installation, offline deployment, configuration, systemd service setup, logs, health checks, and X-UI integration easier without requiring users to manually edit large JSON files.

> Use this only on servers and networks you own or are authorized to operate. Spoof Tunnel requires raw sockets and IP spoofing capability on both sides.

## Features

- English interactive menu
- Targets **spoof-tunnel v1.0.3** only
- Fully offline install mode
- Online GitHub release install mode
- No package manager usage by default
- Does not update existing packages
- Reuses existing binaries unless you explicitly replace them
- Generates client/server JSON configs
- Generates or reuses key pairs through the installed `spoof keygen`
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
/etc/spoof-tunnel/backups/
/var/log/spoof-tunnel/
/etc/systemd/system/spoof-client.service
/etc/systemd/system/spoof-server.service
```

## Typical setup flow

### On the server side

```bash
sudo st-manager
```

Choose:

```text
5) Configure as Server
```

Enter:

- transport: `udp` or `icmp`
- tunnel listen address, usually `0.0.0.0`
- tunnel port, usually `8080`
- server spoof source IP
- expected client spoof source IP
- client real IP
- client public key

The manager prints server pairing information. Send that to the client side.

### On the client side

```bash
sudo st-manager
```

Choose:

```text
4) Configure as Client
```

Enter:

- transport: must match the server
- local SOCKS listen address, usually `127.0.0.1`
- local SOCKS port, usually `1080`
- server real IP
- server tunnel port
- client spoof source IP
- expected server spoof source IP
- server public key

The client creates a local SOCKS5 endpoint such as:

```text
127.0.0.1:1080
```

Use this endpoint in X-UI as a SOCKS5 outbound/proxy target.

## Managing services

```bash
sudo st-manager
```

Useful menu options:

```text
6) Start service
7) Stop service
8) Restart service
9) Service status
10) Live logs
11) Health check
12) X-UI helper
```

Manual commands also work:

```bash
sudo systemctl restart spoof-client
sudo systemctl status spoof-client --no-pager
sudo journalctl -u spoof-client -f
```

Server side:

```bash
sudo systemctl restart spoof-server
sudo systemctl status spoof-server --no-pager
sudo journalctl -u spoof-server -f
```

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

## License

MIT
