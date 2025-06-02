#!/bin/bash
set -e

PROJECT_DIR="$1"
TELEGRAM_TOKEN="$2"
YOLO_URL="$3"

if [[ -z "$PROJECT_DIR" || -z "$TELEGRAM_TOKEN" || -z "$YOLO_URL" ]]; then
    echo "Usage: $0 <PROJECT_DIR> <TELEGRAM_TOKEN> <YOLO_URL>"
    exit 1
fi

cd "$PROJECT_DIR"

echo "→ Setting up deployment files..."
chmod +x deploy_prod.sh
chmod +x polybot/start_prod.sh

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
echo "→ Writing environment file: $ENV_FILE"
cat > "$ENV_FILE" << EOF
TELEGRAM_BOT_TOKEN=$TELEGRAM_TOKEN
YOLO_URL=$YOLO_URL
EOF

echo "✓ Environment file created with:"
echo "  - TELEGRAM_BOT_TOKEN: ${TELEGRAM_TOKEN:0:10}..."
echo "  - YOLO_URL: $YOLO_URL"

# Stop existing service if running
sudo systemctl stop polyservice_prod.service 2>/dev/null || echo "Service was not running"

# Copy and reload systemd service
echo "→ Installing systemd service..."
sudo cp polyservice_prod.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable polyservice_prod.service
sudo systemctl start polyservice_prod.service

# Wait a moment for service to start
sleep 3

# Final check
if systemctl is-active --quiet polyservice_prod.service; then
    echo "✅ Service is running successfully!"
    echo "→ Checking service status:"
    sudo systemctl status polyservice_prod.service --no-pager -l
else
    echo "❌ Service failed to start:"
    sudo journalctl -u polyservice_prod.service -n 20 --no-pager
    exit 1
fi

echo "🎉 Deployment completed!"