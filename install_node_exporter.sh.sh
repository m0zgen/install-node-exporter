#!/usr/bin/env bash
# Author: Yevgeniy Goncharov aka xck, https://sys-adm.in
# Install / remove Prometheus Node Exporter on Debian-based distributions

set -euo pipefail

PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

SERVICE_NAME="node_exporter"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
NODE_EXPORTER_BIN="/usr/local/bin/node_exporter"
NODE_EXPORTER_USER="node_exporter"
NODE_EXPORTER_PORT="9100"

SERVER_IP="$(hostname -I | awk '{print $1}')"

ACTION="${1:-install}"

confirm() {
    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
        [yY][eE][sS]|[yY]) true ;;
        *) false ;;
    esac
}

usage() {
    cat <<EOF
Usage:
  sudo $0 install      Install Node Exporter
  sudo $0 remove       Remove Node Exporter
  sudo $0 uninstall    Remove Node Exporter
  sudo $0 status       Show Node Exporter status
  sudo $0 help         Show this help

Default action:
  install

Examples:
  sudo $0
  sudo $0 install
  sudo $0 remove
  sudo $0 status
EOF
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "Error: this script must be run as root."
        echo "Try: sudo $0 $ACTION"
        exit 1
    fi
}

check_dependencies() {
    local deps=("curl" "wget" "tar" "systemctl" "grep" "cut")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo "Error: required command not found: $dep"
            echo "Install it and run this script again."
            exit 1
        fi
    done
}

check_existing_installation() {
    if [[ -f "$SERVICE_FILE" ]] || [[ -x "$NODE_EXPORTER_BIN" ]]; then
        echo "Node Exporter already appears to be installed."
        echo "Service file: $SERVICE_FILE"
        echo "Binary: $NODE_EXPORTER_BIN"
        echo
        echo "Use the following command to remove it:"
        echo "  sudo $0 remove"
        exit 1
    fi
}

download_node_exporter() {
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    echo "Using temporary directory: $tmp_dir"
    cd "$tmp_dir"

    echo "Downloading latest Node Exporter release..."

    local download_url
    download_url="$(
        curl -fsSL https://api.github.com/repos/prometheus/node_exporter/releases/latest \
        | grep browser_download_url \
        | grep linux-amd64 \
        | cut -d '"' -f 4
    )"

    if [[ -z "$download_url" ]]; then
        echo "Error: could not find Node Exporter linux-amd64 download URL."
        exit 1
    fi

    wget -q "$download_url"

    echo "Extracting Node Exporter..."
    tar -xzf node_exporter-*.linux-amd64.tar.gz

    echo "Installing binary to $NODE_EXPORTER_BIN..."
    install -m 0755 node_exporter-*.linux-amd64/node_exporter "$NODE_EXPORTER_BIN"

    cd /
    rm -rf "$tmp_dir"
}

detect_nologin_shell() {
    if [[ -x /usr/sbin/nologin ]]; then
        echo "/usr/sbin/nologin"
    elif [[ -x /sbin/nologin ]]; then
        echo "/sbin/nologin"
    else
        echo "/bin/false"
    fi
}

NOLOGIN_SHELL="$(detect_nologin_shell)"

create_node_exporter_user() {
    if id "$NODE_EXPORTER_USER" >/dev/null 2>&1; then
        echo "User $NODE_EXPORTER_USER already exists."
    else
        if getent group "$NODE_EXPORTER_USER" >/dev/null 2>&1; then
            echo "Group $NODE_EXPORTER_USER already exists. Creating user with existing group..."
            useradd --system \
                --no-create-home \
                --shell "$NOLOGIN_SHELL" \
                --gid "$NODE_EXPORTER_USER" \
                "$NODE_EXPORTER_USER"
        else
            echo "Creating system user and group: $NODE_EXPORTER_USER"
            useradd --system \
                --no-create-home \
                --shell "$NOLOGIN_SHELL" \
                --user-group \
                "$NODE_EXPORTER_USER"
        fi
    fi

    chown "$NODE_EXPORTER_USER:$NODE_EXPORTER_USER" "$NODE_EXPORTER_BIN"
}

setup_systemd_service() {
    echo "Creating systemd service: $SERVICE_FILE"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network-online.target
Wants=network-online.target

[Service]
User=${NODE_EXPORTER_USER}
Group=${NODE_EXPORTER_USER}
Type=simple
ExecStart=${NODE_EXPORTER_BIN}
Restart=on-failure
RestartSec=5s

NoNewPrivileges=true
ProtectHome=true
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME"
}

setup_firewall() {
    if ! command -v firewall-cmd >/dev/null 2>&1; then
        echo "firewall-cmd not found. Skipping firewalld configuration."
        return
    fi

    if ! systemctl is-active --quiet firewalld; then
        echo "firewalld is not active. Skipping firewall configuration."
        return
    fi

    if confirm "Setup firewalld port ${NODE_EXPORTER_PORT}/tcp in internal zone? [y/N]"; then
        firewall-cmd --permanent --zone=internal --add-port="${NODE_EXPORTER_PORT}/tcp"
    else
        firewall-cmd --permanent --add-port="${NODE_EXPORTER_PORT}/tcp"
    fi

    firewall-cmd --reload
}

remove_firewall_rule() {
    if ! command -v firewall-cmd >/dev/null 2>&1; then
        echo "firewall-cmd not found. Skipping firewalld cleanup."
        return
    fi

    if ! systemctl is-active --quiet firewalld; then
        echo "firewalld is not active. Skipping firewall cleanup."
        return
    fi

    echo "Checking firewalld rules..."

    if firewall-cmd --permanent --query-port="${NODE_EXPORTER_PORT}/tcp" >/dev/null 2>&1; then
        echo "Removing ${NODE_EXPORTER_PORT}/tcp from default zone..."
        firewall-cmd --permanent --remove-port="${NODE_EXPORTER_PORT}/tcp" || true
    fi

    if firewall-cmd --permanent --zone=internal --query-port="${NODE_EXPORTER_PORT}/tcp" >/dev/null 2>&1; then
        echo "Removing ${NODE_EXPORTER_PORT}/tcp from internal zone..."
        firewall-cmd --permanent --zone=internal --remove-port="${NODE_EXPORTER_PORT}/tcp" || true
    fi

    firewall-cmd --reload || true
}

show_suggestion() {
    echo
    echo "Node Exporter is installed!"
    echo
    echo "Service status:"
    systemctl --no-pager --full status "$SERVICE_NAME" || true

    echo
    echo "Prometheus scrape config example:"
    cat <<EOF

- job_name: 'node_exporter'
  scrape_interval: 5s
  static_configs:
    - targets:
        - 'localhost:${NODE_EXPORTER_PORT}'

Or add this server:

    - targets:
        - '${SERVER_IP}:${NODE_EXPORTER_PORT}'

EOF
}

install_node_exporter() {
    require_root
    check_dependencies
    check_existing_installation

    download_node_exporter
    create_node_exporter_user
    setup_systemd_service
    setup_firewall
    show_suggestion
}

remove_node_exporter() {
    require_root

    echo "This will remove Node Exporter from this system."
    echo
    echo "Service file: $SERVICE_FILE"
    echo "Binary:       $NODE_EXPORTER_BIN"
    echo "User:         $NODE_EXPORTER_USER"
    echo

    if ! confirm "Continue with removal? [y/N]"; then
        echo "Removal cancelled."
        exit 0
    fi

    echo "Stopping and disabling service..."

    if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
        systemctl disable --now "$SERVICE_NAME" || true
    else
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    fi

    if [[ -f "$SERVICE_FILE" ]]; then
        echo "Removing systemd service file..."
        rm -f "$SERVICE_FILE"
    fi

    systemctl daemon-reload
    systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true

    if [[ -f "$NODE_EXPORTER_BIN" ]]; then
        echo "Removing Node Exporter binary..."
        rm -f "$NODE_EXPORTER_BIN"
    fi

    remove_firewall_rule

    if id "$NODE_EXPORTER_USER" >/dev/null 2>&1; then
        if confirm "Remove system user ${NODE_EXPORTER_USER}? [y/N]"; then
            echo "Removing user $NODE_EXPORTER_USER..."
            userdel "$NODE_EXPORTER_USER" || true
        else
            echo "Keeping user $NODE_EXPORTER_USER."
        fi
    fi

    echo
    echo "Node Exporter has been removed."
}

show_status() {
    if [[ -x "$NODE_EXPORTER_BIN" ]]; then
        echo "Binary: $NODE_EXPORTER_BIN"
        "$NODE_EXPORTER_BIN" --version || true
    else
        echo "Binary not found: $NODE_EXPORTER_BIN"
    fi

    echo

    if [[ -f "$SERVICE_FILE" ]]; then
        echo "Service file exists: $SERVICE_FILE"
    else
        echo "Service file not found: $SERVICE_FILE"
    fi

    echo
    systemctl --no-pager --full status "$SERVICE_NAME" || true
}

case "$ACTION" in
    install)
        install_node_exporter
        ;;
    remove|uninstall)
        remove_node_exporter
        ;;
    status)
        show_status
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        echo "Unknown action: $ACTION"
        echo
        usage
        exit 1
        ;;
esac