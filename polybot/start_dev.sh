#!/bin/bash
set -e

# If vars not passed, try loading from ENV_FILE
REPO_DIR="$1"
TELEGRAM_BOT_TOKEN="$2"
YOLO_URL="$3"
NGROK_TOKEN="$4"

# If CLI args are empty, load from .runtime_env
if [[ -z "$REPO_DIR" || -z "$TELEGRAM_BOT_TOKEN" || -z "$YOLO_URL" ]]; then
    ENV_FILE="$(dirname "$0")/.runtime_env"
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
        REPO_DIR=${REPO_DIR:-/home/ubuntu/TelegramPhotoBot}  # fallback if missing
        # Map the env file variables to script variables
        TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-$TELEGRAM_BOT_TOKEN}
        YOLO_URL=${YOLO_URL:-$YOLO_SERVICE_URL}
    fi
fi

# Validate again
if [[ -z "$REPO_DIR" || -z "$TELEGRAM_BOT_TOKEN" || -z "$YOLO_URL" ]]; then
    echo "Usage: $0 <REPO_DIR> <TELEGRAM_BOT_TOKEN> <YOLO_URL> [NGROK_TOKEN]"
    echo "Or make sure .runtime_env file contains required variables."
    exit 1
fi

SERVICE_NAME="telegrambot"
ENV_FILE="${REPO_DIR}/polybot/.runtime_env"

echo "🚀 Starting Telegram Bot Deployment"
echo "Using REPO_DIR=$REPO_DIR"
echo "Using TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN"
echo "Using YOLO_URL=$YOLO_URL"
echo "Env file will be: $ENV_FILE"

# Stop the service if it's running
echo "🛑 Stopping bot service if running..."
sudo systemctl stop $SERVICE_NAME 2>/dev/null || echo "Service was not running"

# --- Write runtime env file ---
echo "📝 Writing environment variables..."
cat > "$ENV_FILE" <<EOF
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
YOLO_SERVICE_URL=${YOLO_URL}
EOF

echo "✅ Wrote environment variables to $ENV_FILE"

# --- Verify virtual environment and dependencies ---
echo "🐍 Checking virtual environment..."
VENV_PYTHON="$REPO_DIR/venv/bin/python3"
if [[ ! -f "$VENV_PYTHON" ]]; then
    echo "❌ Virtual environment not found at $VENV_PYTHON"
    exit 1
fi

# Test critical imports
echo "🧪 Testing Python dependencies..."
if ! "$VENV_PYTHON" -c "import flask, requests; print('✅ Dependencies OK')" 2>/dev/null; then
    echo "❌ Missing dependencies. Installing..."
    "$REPO_DIR/venv/bin/pip" install flask requests pillow python-telegram-bot python-dotenv
fi

# --- Setup systemd service ---
echo "🛠️ Setting up systemd service..."
SCRIPT_DIR="$(dirname "$0")"
if [[ -f "$SCRIPT_DIR/setup_service.sh" ]]; then
    chmod +x "$SCRIPT_DIR/setup_service.sh"
    "$SCRIPT_DIR/setup_service.sh" "$REPO_DIR"
else
    echo "⚠️ setup_service.sh not found, creating service manually..."
    # Fallback service creation (same as in setup_service.sh)
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Telegram Photo Bot
After=network.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$VENV_PYTHON $REPO_DIR/polybot/app.py
WorkingDirectory=$REPO_DIR/polybot
Restart=always
RestartSec=10
User=ubuntu
Group=ubuntu
EnvironmentFile=$ENV_FILE
StandardOutput=journal
StandardError=journal
SyslogIdentifier=telegrambot
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
fi

# --- Install and setup ngrok ---
echo "🔧 Setting up ngrok..."

# Check if ngrok is installed
if ! command -v ngrok &> /dev/null; then
    echo "Installing ngrok..."
    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
    sudo apt update && sudo apt install -y ngrok
    echo "✅ ngrok installed"
else
    echo "✅ ngrok already installed"
fi

# Configure ngrok auth token if provided
if [[ -n "$NGROK_TOKEN" ]]; then
    echo "Configuring ngrok auth token..."
    ngrok config add-authtoken "$NGROK_TOKEN"
    echo "✅ ngrok auth token configured"
else
    echo "⚠️ No ngrok token provided - may hit rate limits"
fi

# Check if jq is installed (needed for parsing ngrok API)
if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    sudo apt update && sudo apt install -y jq
    echo "✅ jq installed"
fi

# --- Start ngrok if not running ---
echo "🌐 Setting up ngrok tunnel..."
NGROK_PID=$(pgrep -f 'ngrok http 8443' || true)
if [ -n "$NGROK_PID" ]; then
    echo "Stopping existing ngrok process (PID $NGROK_PID)..."
    kill $NGROK_PID || true
    sleep 2
fi

# Start ngrok in background
echo "Starting ngrok on port 8443..."
ngrok http 8443 > /tmp/ngrok.log 2>&1 &
NGROK_PID=$!
echo "Started ngrok with PID: $NGROK_PID"

# Wait for ngrok to be ready
echo "⏳ Waiting for ngrok to initialize..."
sleep 5

# --- Get ngrok public HTTPS URL ---
NGROK_URL=""
for i in {1..10}; do
    # Check if ngrok process is still running
    if ! kill -0 $NGROK_PID 2>/dev/null; then
        echo "❌ ngrok process died. Check /tmp/ngrok.log for errors:"
        cat /tmp/ngrok.log
        exit 1
    fi
    
    NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | jq -r '.tunnels[]? | select(.proto == "https") | .public_url' 2>/dev/null || true)
    if [[ -n "$NGROK_URL" && "$NGROK_URL" != "null" ]]; then
        break
    fi
    echo "Waiting for ngrok to be ready... (attempt $i/10)"
    sleep 2
done

if [[ -z "$NGROK_URL" || "$NGROK_URL" == "null" ]]; then
    echo "❌ Failed to get ngrok URL after 10 attempts"
    echo "ngrok log:"
    cat /tmp/ngrok.log 2>/dev/null || echo "No log file found"
    exit 1
fi

echo "🌍 Ngrok public URL: $NGROK_URL"

# --- Update BOT_APP_URL in the env file ---
sed -i '/^BOT_APP_URL=/d' "$ENV_FILE"
echo "BOT_APP_URL=$NGROK_URL" >> "$ENV_FILE"
echo "✅ Updated BOT_APP_URL in $ENV_FILE"

# --- Set Telegram webhook ---
echo "🔗 Setting up Telegram webhook..."
WEBHOOK_RESPONSE=$(curl -s -f -X POST \
    -d "url=${NGROK_URL}/${TELEGRAM_BOT_TOKEN}/" \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" || echo '{"ok":false}')

if echo "$WEBHOOK_RESPONSE" | jq -e '.ok' >/dev/null 2>&1; then
    echo "✅ Telegram webhook set to ${NGROK_URL}/${TELEGRAM_BOT_TOKEN}/"
else
    echo "❌ Failed to set webhook. Response: $WEBHOOK_RESPONSE"
fi

# --- Test the app before starting service ---
echo "🧪 Testing app before starting service..."
cd "$REPO_DIR/polybot"
if ! timeout 5s "$VENV_PYTHON" -c "
import sys
sys.path.insert(0, '.')
import os
# Load environment variables
with open('.runtime_env', 'r') as f:
    for line in f:
        if '=' in line and not line.startswith('#'):
            key, value = line.strip().split('=', 1)
            os.environ[key] = value
# Test imports
import flask
print('✅ App imports successful')
"; then
    echo "❌ App test failed"
    exit 1
fi

# --- Start the systemd service ---
echo "🚀 Starting bot service..."
sudo systemctl daemon-reload
sudo systemctl start $SERVICE_NAME

# Wait a moment and check if it started successfully
sleep 3
if sudo systemctl is-active --quiet $SERVICE_NAME; then
    echo "✅ Service $SERVICE_NAME started successfully"
    echo "📊 Service status:"
    sudo systemctl status $SERVICE_NAME --no-pager -l
else
    echo "❌ Service failed to start. Checking logs..."
    sudo journalctl -u $SERVICE_NAME -n 20 --no-pager
    exit 1
fi

echo ""
echo "🎉 Deployment completed successfully!"
echo "📝 To monitor logs: sudo journalctl -u $SERVICE_NAME -f"
echo "🔧 To restart: sudo systemctl restart $SERVICE_NAME"
echo "🛑 To stop: sudo systemctl stop $SERVICE_NAME"