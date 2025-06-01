#!/bin/bash
set -e

PROJECT_DIR="$1"
TELEGRAM_TOKEN="$2"
YOLO_URL="$3"

cd "$PROJECT_DIR"

echo "→ Setting up deployment files..."
chmod +x deploy.sh
chmod +x polybot/start_polybot.sh

# Create virtual environment
VENV_DIR="$PROJECT_DIR/venv"
if [ ! -f "$VENV_DIR/bin/activate" ]; then
    echo "→ Creating virtual environment..."
    python3.12 -m venv "$VENV_DIR"
fi

# Activate and install dependencies
echo "→ Activating virtual environment and installing requirements..."
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install -r "$PROJECT_DIR/polybot/requirements.txt"

# Write environment file
ENV_FILE="$PROJECT_DIR/polybot/.env"
echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_TOKEN" > "$ENV_FILE"
echo "YOLO_URL=$YOLO_URL" >> "$ENV_FILE"

# Copy and reload systemd service
sudo cp polyservice.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart polyservice.service
sudo systemctl enable polyservice.service

# Final check
if systemctl is-active --quiet polyservice.service; then
    echo "✅ Service is running."
else
    echo "❌ Service failed to start:"
    sudo journalctl -u polyservice.service -n 20 --no-pager
    exit 1
fi

echo "🎉 Deployment completed!"
