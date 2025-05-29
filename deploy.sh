#!/bin/bash
set -e

# === 1. Fetch parameters from script arguments ===
PROJECT_DIR="$1"
TELEGRAM_TOKEN="$2"
YOLO_URL="$3"

cd "$PROJECT_DIR"

# === Auto-setup: Make scripts executable ===
echo "→ Setting up deployment files..."
chmod +x deploy.sh 2>/dev/null || true
chmod +x polybot/start_polybot.sh 2>/dev/null || true

# Create .github/workflows directory if needed
mkdir -p .github/workflows

# Create .env.template automatically if it doesn't exist
ENV_TEMPLATE="$PROJECT_DIR/.env.template"
if [ ! -f "$ENV_TEMPLATE" ]; then
    echo "→ Creating .env.template..."
    cat > "$ENV_TEMPLATE" << 'EOF'
# Telegram Bot Configuration
TELEGRAM_BOT_TOKEN=your_telegram_bot_token_here

# YOLO Service URL
YOLO_URL=your_yolo_service_url_here

# Bot Application URL (auto-updated by ngrok)
BOT_APP_URL=

# Ngrok Token
YOUR_NGROK_TOKEN=your_ngrok_token_here
EOF
    echo "✓ .env.template created automatically"
fi

# Copy the service file
sudo cp polyservice.service /etc/systemd/system/

VENV_DIR="$PROJECT_DIR/venv"  # Using your existing venv directory
ENV_FILE="$PROJECT_DIR/polybot/.env"
SERVICE_FILE="polyservice.service"

echo "==> Using project directory: $PROJECT_DIR"

# === 2. Check/create virtual environment ===
if [ -d "$VENV_DIR" ]; then
    echo "✓ Virtual environment exists."
else
    echo "→ Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

# === 3. Activate the virtual environment ===
source "$VENV_DIR/bin/activate"

pip install --upgrade pip
pip install -r "$PROJECT_DIR/polybot/requirements.txt"
echo "✓ Python requirements installed."

# === 4. Ensure .env file contains correct secrets ===
if [ ! -f "$ENV_FILE" ]; then
    echo "→ .env file does NOT exist — creating it..."
    touch "$ENV_FILE"
fi

# Function to set environment variables
set_env_var() {
    KEY="$1"
    VALUE="$2"
    if grep -q "^$KEY=" "$ENV_FILE"; then
        echo "→ Updating $KEY in .env"
        sed -i "s|^$KEY=.*|$KEY=$VALUE|" "$ENV_FILE"
    else
        echo "→ Adding $KEY to .env"
        echo "$KEY=$VALUE" >> "$ENV_FILE"
    fi
}

set_env_var "TELEGRAM_BOT_TOKEN" "$TELEGRAM_TOKEN"
set_env_var "YOLO_URL" "$YOLO_URL"
echo "✓ .env file is up to date."

# === 5. Restart the service ===
if [ -f "/etc/systemd/system/$SERVICE_FILE" ]; then
    echo "→ Installing systemd service..."
    sudo systemctl daemon-reload
    sudo systemctl restart "$SERVICE_FILE"
    sudo systemctl enable "$SERVICE_FILE"
    echo "✓ Service reloaded and restarted."
    
    # Check if service is running
    if ! systemctl is-active --quiet polyservice.service; then
        echo "❌ polyservice.service is not running yet."
        sudo systemctl status polyservice.service --no-pager
        exit 1
    else
        echo "✅ polyservice.service is running successfully!"
    fi
fi

echo "🎉 Deployment completed successfully!"
