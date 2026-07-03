#!/bin/bash
# Author: Yevgeniy Goncharov aka xck, http://sys-adm.in
# Install Node Exporter to Debian

# Sys env / paths / etc
# -------------------------------------------------------------------------------------------\
PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
SCRIPT_PATH=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)
cd $SCRIPT_PATH

_install=$SCRIPT_PATH/installs
_serverIP=`hostname -I | awk '{print $1}'`

# ==

confirm() {
    # call with a prompt string or use a default
    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
        [yY][eE][sS]|[yY])
            true
            ;;
        *)
            false
            ;;
    esac
}

_exit() {
    echo "Bye bye!"
    exit 0
}

downloadNodeExporter() {
    curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest| grep browser_download_url|grep linux-amd64|cut -d '"' -f 4|wget -qi -
    tar -xvf node_exporter-*.linux-amd64.tar.gz
    sudo mv node_exporter-*.linux-amd64/node_exporter /usr/local/bin/
    sudo useradd -rs /bin/false node_exporter
    chown node_exporter:node_exporter /usr/local/bin/node_exporter
}

setupNodeExporter() {

    echo -e '[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target' > /etc/systemd/system/node_exporter.service

    systemctl daemon-reload
    systemctl enable --now node_exporter

    if confirm "Setup firewalld to Internal zone? (y/n or enter)"; then
        firewall-cmd --permanent --add-port=9100/tcp --zone=internal
    else
        firewall-cmd --permanent --add-port=9100/tcp
    fi

    firewall-cmd --reload

}

showSuggestion() {
    # User suggestion
    echo -e "Add the following lines to /etc/prometheus/prometheus.yml:
- job_name: 'node_exporter'
  scrape_interval: 5s
  static_configs:
  - targets: ['localhost:9100']

or just add to exist yml file to node_exporter section:
  - targets: ['$_serverIP:9100'] 
"
echo "node_exporter is installed!"
}

# ==

if [[ -f /etc/systemd/system/node_exporter.service ]]; then
    echo -e "Node Exporter already installed. Exit. Bye."
    exit 1
fi

# Temporary catalog
if [[ ! -d "$_install" ]]; then
    mkdir $_install
else
    rm -rf $_install; mkdir $_install
fi

cd $_install;

# ==

# Download binary
downloadNodeExporter

# Setup systemd unit
setupNodeExporter

showSuggestion

