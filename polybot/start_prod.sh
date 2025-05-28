#!/bin/bash
set -x

# Parse args
REPO_DIR="$1"
TELEGRAM_TOKEN="$2"
YOLO_URL="$3"

# Fail fast if required envs are missing
if [[ -z "$TELEGRAM_TOKEN" || -z "$YOLO_URL" ]]; then
    echo "❌ TELEGRAM_TOKEN and YOLO_URL are required."
    exit 1
fi

SERVICE_NAME="telegrambot"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
ENV_FILE="${REPO_DIR}/polybot/.runtime_env"

# Generate runtime env file
cat > "$ENV_FILE" <<EOF
TELEGRAM_BOT_TOKEN=${TELEGRAM_TOKEN}
YOLO_SERVICE_URL=${YOLO_URL}
EOF

# Start ngrok if not running
NGROK_PID=$(pgrep -f 'ngrok http 8443')
if [ -z "$NGROK_PID" ]; then
    echo "Starting ngrok on port 8443..."
    nohup ngrok http 8443 > /dev/null 2>&1 &
    sleep 3
else
    echo "ngrok already running (PID $NGROK_PID)"
fi

# Get ngrok public HTTPS URL
NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[] | select(.proto == "https") | .public_url')
echo "Ngrok public URL: $NGROK_URL"
echo "BOT_APP_URL=$NGROK_URL" >> "$ENV_FILE"

# Load env vars into current session
set -a
source "$ENV_FILE"
set +a

# Activate virtual environment
source /home/ubuntu/TelegramPhotoBot/venv/bin/activate

# Create systemd service if not already present
if [ ! -f "$SERVICE_FILE" ]; then
    echo "Creating systemd service: $SERVICE_NAME"
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Telegram Photo Bot
After=network.target

[Service]
ExecStart=/home/ubuntu/TelegramPhotoBot/polybot/start_prod.sh
WorkingDirectory=/home/ubuntu/TelegramPhotoBot
Restart=always
User=ubuntu
EnvironmentFile=${ENV_FILE}

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
fi

# Set webhook
curl -s -F "url=${BOT_APP_URL}/${TELEGRAM_BOT_TOKEN}/" \
     https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook

# Restart service
echo "Restarting bot service..."
sudo systemctl restart $SERVICE_NAME
