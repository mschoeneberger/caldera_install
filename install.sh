#!/bin/bash

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Exiting."
    exit 1
fi

# Exit immediately if a command exits with a non-zero status
set -e

# Make apt operations non-interactive
export DEBIAN_FRONTEND=noninteractive

# Update the package lists and upgrade the installed packages
apt update -y || { echo "Failed to update package lists"; exit 1; }
apt upgrade -y || { echo "Failed to upgrade packages"; exit 1; }

# Check if curl is installed
command -v curl >/dev/null 2>&1 || { echo "curl is required but not installed. Exiting."; exit 1; }

# Install Node Version Manager (NVM)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash || { echo "Failed to install NVM"; exit 1; }

# Load NVM into the current shell session
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" || { echo "Failed to load NVM"; exit 1; }

# Install Node.js version 22 using NVM
nvm install 22 || { echo "Failed to install Node.js"; exit 1; }

# Check if Go is installed
command -v go >/dev/null 2>&1 || apt install -y golang || { echo "Failed to install Go"; exit 1; }

# Install Python3 virtual environment and pip
apt install -y python3-venv python3-pip || { echo "Failed to install Python3 venv and pip"; exit 1; }

# Clone the Caldera repository into /opt/caldera
# The --recursive option ensures submodules are cloned as well
if [ -d "/opt/caldera" ]; then
    echo "Directory /opt/caldera already exists. Skipping clone."
else
    git clone https://github.com/mitre/caldera.git --recursive /opt/caldera || { echo "Failed to clone Caldera repository"; exit 1; }
fi

# Create a Python virtual environment in /opt/caldera/.venv
if [ ! -d "/opt/caldera/.venv" ]; then
    python3 -m venv /opt/caldera/.venv || { echo "Failed to create virtual environment"; exit 1; }
else
    echo "Virtual environment already exists. Skipping creation."
fi

# Install the required Python packages from requirements.txt
/opt/caldera/.venv/bin/pip install -r /opt/caldera/requirements.txt || { echo "Failed to install Python requirements"; exit 1; }

# Define the service file path
SERVICE_FILE="/etc/systemd/system/caldera.service"
if [ -f "$SERVICE_FILE" ]; then
    echo "Service file $SERVICE_FILE already exists. Please remove or rename it before running the script."
    exit 1
fi

# Get the current Node.js version
NODE_VERSION=$(nvm current || echo "node")

# Create the service file with the specified configuration
cat <<EOL > $SERVICE_FILE
[Unit]
Description=Caldera Server
After=syslog.target network.target

[Service]
Environment="PATH=$NVM_DIR/versions/node/$NODE_VERSION/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
WorkingDirectory=/opt/caldera
ExecStart=/opt/caldera/.venv/bin/python3 server.py --build

Restart=always
RestartSec=120

[Install]
WantedBy=multi-user.target
EOL

# Set appropriate permissions for the service file
chmod 644 $SERVICE_FILE || { echo "Failed to set permissions for the service file"; exit 1; }

# Reload systemd to recognize the new service
systemctl daemon-reload || { echo "Failed to reload systemd"; exit 1; }

# Enable the Caldera service to start at system boot
systemctl enable caldera.service || { echo "Failed to enable Caldera service"; exit 1; }

# Start the Caldera service immediately
systemctl start caldera.service || { echo "Failed to start Caldera service"; exit 1; }
