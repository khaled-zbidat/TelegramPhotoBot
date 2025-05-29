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

# === Install system dependencies ===
echo "→ Installing system dependencies..."
sudo apt update
sudo apt install -y curl jq

# === Install ngrok ===
echo "→ Setting up ngrok..."
if ! command -v ngrok &> /dev/null; then
    echo "→ Installing ngrok..."
    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
    sudo apt update
    sudo apt install -y ngrok
    echo "✓ ngrok installed successfully"
else
    echo "✓ ngrok is already installed"
fi

# Copy the service file
sudo cp polyservice.service /etc/systemd/system/

VENV_DIR="$PROJECT_DIR/venv"
ENV_FILE="$PROJECT_DIR/polybot/.env"
SERVICE_FILE="polyservice.service"

echo "==> Using project directory: $PROJECT_DIR"

# === 2. Check/create virtual environment ===
if [ -f "$VENV_DIR/bin/activate" ]; then
    echo "✓ Virtual environment exists and is properly configured."
else
    echo "→ Creating virtual environment..."
    # Remove existing directory if it exists but is incomplete
    if [ -d "$VENV_DIR" ]; then
        echo "→ Removing incomplete virtual environment..."
        rm -rf "$VENV_DIR"
    fi
    python3 -m venv "$VENV_DIR"
    echo "✓ Virtual environment created successfully."
fi

# === 3. Activate the virtual environment ===
echo "→ Activating virtual environment..."
source "$VENV_DIR/bin/activate"
echo "✓ Virtual environment activated."

echo "→ Installing/updating Python packages..."
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

# Add ngrok token if it's provided via environment variable
if [ -n "$NGROK_TOKEN" ]; then
    set_env_var "YOUR_NGROK_TOKEN" "$NGROK_TOKEN"
    echo "✓ ngrok token added to .env"
fi

echo "✓ .env file is up to date."

# === 5. Create log directory ===
sudo mkdir -p /var/log/polybot
sudo chown ubuntu:ubuntu /var/log/polybot

# === 6. Test ngrok authentication (if token is available) ===
if [ -n "$NGROK_TOKEN" ]; then
    echo "→ Testing ngrok authentication..."
    ngrok config add-authtoken "$NGROK_TOKEN" || echo "⚠️  ngrok auth test failed - will retry at runtime"
fi

# === 7. Restart the service ===
if [ -f "/etc/systemd/system/$SERVICE_FILE" ]; then
    echo "→ Installing systemd service..."
    sudo systemctl daemon-reload
    sudo systemctl stop "$SERVICE_FILE" 2>/dev/null || true
    sleep 2
    sudo systemctl start "$SERVICE_FILE"
    sudo systemctl enable "$SERVICE_FILE"
    echo "✓ Service reloaded and restarted."
    
    # Give service time to start
    sleep 10
    
    # Check if service is running
    if ! systemctl is-active --quiet polyservice.service; then
        echo "❌ polyservice.service is not running yet."
        echo "→ Service status:"
        sudo systemctl status polyservice.service --no-pager
        echo "→ Recent logs:"
        sudo journalctl -u polyservice.service -n 20 --no-pager
        exit 1
    else
        echo "✅ polyservice.service is running successfully!"
        echo "→ Service status:"
        sudo systemctl status polyservice.service --no-pager
    fi
fi

echo "🎉 Deployment completed successfully!"