# Node Exporter Installer

Simple Bash installer for Prometheus Node Exporter on systemd-based Linux distributions.

The script downloads the latest official `node_exporter` release from the Prometheus GitHub repository, installs the binary, creates a dedicated system user, configures a systemd service, and optionally opens port `9100/tcp` using firewalld.

## Features

* Installs the latest official Prometheus Node Exporter release
* Uses upstream prebuilt `linux-amd64` binary
* Creates a dedicated system user: `node_exporter`
* Creates and enables a systemd service
* Supports install, remove, uninstall, status and help actions
* Supports non-interactive mode with `-y` / `--yes`
* Supports Debian, Ubuntu, RHEL, Rocky Linux, AlmaLinux, Fedora and similar systemd-based distributions
* Automatically detects available `nologin` shell
* Handles existing `node_exporter` group correctly
* Optionally configures firewalld
* Adds basic systemd hardening options

## Supported systems

This script is intended for systemd-based Linux distributions.

Tested / expected to work on:

* Debian
* Ubuntu
* RHEL
* Rocky Linux
* AlmaLinux
* Fedora
* Oracle Linux
* Other similar systemd-based Linux distributions

The script currently installs the `linux-amd64` build of Node Exporter.

## Requirements

Required commands:

```bash
curl
wget
tar
systemctl
grep
cut
awk
getent
useradd
```

Optional:

```bash
firewall-cmd
```

If firewalld is not installed or not active, firewall configuration will be skipped automatically.

## Installation

Clone the repository or download the script:

```bash
chmod +x install_node_exporter.sh
sudo ./install_node_exporter.sh install
```

The default action is `install`, so this also works:

```bash
sudo ./install_node_exporter.sh
```

## Non-interactive installation

For automation, CI, Ansible, cloud-init or remote provisioning, use:

```bash
sudo ./install_node_exporter.sh install -y
```

Aliases for non-interactive mode:

```bash
-y
--yes
--auto
--non-interactive
```

Example:

```bash
sudo ./install_node_exporter.sh install --yes
```

## Usage

```bash
sudo ./install_node_exporter.sh install
sudo ./install_node_exporter.sh install -y
sudo ./install_node_exporter.sh status
sudo ./install_node_exporter.sh remove
sudo ./install_node_exporter.sh remove -y
sudo ./install_node_exporter.sh uninstall
sudo ./install_node_exporter.sh help
```

## Actions

### Install

Installs Node Exporter:

```bash
sudo ./install_node_exporter.sh install
```

Or in non-interactive mode:

```bash
sudo ./install_node_exporter.sh install -y
```

### Status

Shows installed binary version, systemd unit status and service state:

```bash
sudo ./install_node_exporter.sh status
```

### Remove

Removes Node Exporter:

```bash
sudo ./install_node_exporter.sh remove
```

Non-interactive removal:

```bash
sudo ./install_node_exporter.sh remove -y
```

The following alias is also supported:

```bash
sudo ./install_node_exporter.sh uninstall
```

During removal, the script will:

* Stop and disable the `node_exporter` service
* Remove the systemd service file
* Remove `/usr/local/bin/node_exporter`
* Remove firewalld rules for port `9100/tcp`, if found
* Optionally remove the `node_exporter` system user

In non-interactive mode, user removal is also confirmed automatically.

## What the installer does

The install action performs the following steps:

1. Checks root privileges
2. Checks required commands
3. Downloads the latest Node Exporter release from GitHub
4. Extracts the archive
5. Installs the binary to:

```text
/usr/local/bin/node_exporter
```

6. Creates a dedicated system user:

```text
node_exporter
```

7. Creates a systemd service:

```text
/etc/systemd/system/node_exporter.service
```

8. Enables and starts the service
9. Optionally opens port `9100/tcp` using firewalld
10. Prints a Prometheus scrape configuration example

## Service management

Check service status:

```bash
systemctl status node_exporter
```

Restart Node Exporter:

```bash
sudo systemctl restart node_exporter
```

Stop Node Exporter:

```bash
sudo systemctl stop node_exporter
```

Start Node Exporter:

```bash
sudo systemctl start node_exporter
```

Enable autostart:

```bash
sudo systemctl enable node_exporter
```

Disable autostart:

```bash
sudo systemctl disable node_exporter
```

## Default port

Node Exporter listens on:

```text
9100/tcp
```

Check listening port:

```bash
ss -lntp | grep 9100
```

Test metrics endpoint locally:

```bash
curl http://localhost:9100/metrics
```

## Prometheus configuration

Add the following job to your Prometheus configuration file.

Usually the file is located at:

```text
/etc/prometheus/prometheus.yml
```

Example for local scraping:

```yaml
- job_name: 'node_exporter'
  scrape_interval: 5s
  static_configs:
    - targets:
        - 'localhost:9100'
```

Example for remote scraping:

```yaml
- job_name: 'node_exporter'
  scrape_interval: 5s
  static_configs:
    - targets:
        - 'SERVER_IP:9100'
```

Then restart Prometheus:

```bash
sudo systemctl restart prometheus
```

## Firewall

If `firewalld` is installed and active, the script can open port `9100/tcp`.

Interactive install will ask:

```text
Setup firewalld port 9100/tcp in internal zone? [y/N]
```

If you answer `yes`, the port will be added to the `internal` zone:

```bash
sudo firewall-cmd --permanent --zone=internal --add-port=9100/tcp
sudo firewall-cmd --reload
```

If you answer `no`, the port will be added to the default zone:

```bash
sudo firewall-cmd --permanent --add-port=9100/tcp
sudo firewall-cmd --reload
```

Important: in non-interactive mode with `-y`, the script automatically answers `yes`, so the port is added to the `internal` zone.

Example:

```bash
sudo ./install_node_exporter.sh install -y
```

This will use the `internal` firewalld zone if firewalld is installed and active.

## Security notes

Node Exporter runs under a dedicated unprivileged system user:

```text
node_exporter
```

The generated systemd service includes basic hardening options:

```ini
NoNewPrivileges=true
ProtectHome=true
ProtectSystem=full
PrivateTmp=true
```

Generated service file:

```ini
[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network-online.target
Wants=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure
RestartSec=5s

NoNewPrivileges=true
ProtectHome=true
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

## Troubleshooting

### Node Exporter is already installed

If the service already exists, the installer will stop with:

```text
Node Exporter service already exists.
```

Remove it first:

```bash
sudo ./install_node_exporter.sh remove
```

Then install again:

```bash
sudo ./install_node_exporter.sh install
```

### Group `node_exporter` already exists

The script handles this case automatically.

If the group exists but the user does not, the script creates the user using the existing group.

### firewalld is not installed

This is not an error.

The script will print:

```text
firewall-cmd not found. Skipping firewalld configuration.
```

You can configure your firewall manually if needed.

### firewalld is not active

This is not an error.

The script will print:

```text
firewalld is not active. Skipping firewall configuration.
```

### Check logs

Use journalctl:

```bash
journalctl -u node_exporter -f
```

Or show recent logs:

```bash
journalctl -u node_exporter --no-pager -n 100
```

## Repository structure

Recommended repository structure:

```text
node-exporter-installer/
├── README.md
├── install_node_exporter.sh
└── LICENSE
```

## License

This project is licensed under the MIT License.

Copyright (c) 2026 Yevgeniy G.

https://sys-adm.in
