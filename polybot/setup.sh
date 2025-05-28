#!/bin/bash
set -e

echo "🔧 Setting up TelegramPhotoBot environment..."

# Install system dependencies
sudo apt update
sudo apt install -y python3 python3-pip python3-venv curl jq

# Create virtual environment in main directory (not inside polybot)
if [ ! -d "venv" ]; then
    echo "🐍 Creating virtual environment..."
    python3 -m venv venv
fi

# Activate and install Python packages
source venv/bin/activate
pip install --upgrade pip
pip install flask requests pillow python-telegram-bot python-dotenv pyTelegramBotAPI

# Install ngrok if not present
if ! command -v ngrok &> /dev/null; then
    echo "🌐 Installing ngrok..."
    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
    sudo apt update && sudo apt install -y ngrok
fi

# Create systemd service
echo "🛠️ Creating systemd service..."
REPO_DIR=$(pwd)
sudo tee /etc/systemd/system/telegrambot.service > /dev/null <<EOF
[Unit]
Description=Telegram Photo Bot
After=network.target

[Service]
Type=simple
ExecStart=$REPO_DIR/venv/bin/python3 -m polybot.app
WorkingDirectory=$REPO_DIR
Restart=always
RestartSec=10
User=ubuntu
Group=ubuntu
EnvironmentFile=$REPO_DIR/polybot/.env
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable telegrambot

echo "✅ Setup complete!"