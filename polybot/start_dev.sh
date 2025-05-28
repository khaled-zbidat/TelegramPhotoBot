#!/bin/bash
set -x

# If vars not passed, try loading from ENV_FILE
REPO_DIR="$1"
TELEGRAM_BOT_TOKEN="$2"
YOLO_URL="$3"

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
    echo "Usage: $0 <REPO_DIR> <TELEGRAM_BOT_TOKEN> <YOLO_URL>"
    echo "Or make sure .runtime_env file contains required variables."
    exit 1
fi

SERVICE_NAME="telegrambot"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
ENV_FILE="${REPO_DIR}/polybot/.runtime_env"

echo "Using REPO_DIR=$REPO_DIR"
echo "Using TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN"
echo "Using YOLO_URL=$YOLO_URL"
echo "Env file will be: $ENV_FILE"

# --- Write runtime env file ---
cat > "$ENV_FILE" <<EOF
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
YOLO_SERVICE_URL=${YOLO_URL}
EOF

echo "✅ Wrote environment variables to $ENV_FILE"

# --- Activate python venv (skip if doesn't exist) ---
if [ -f "/home/ubuntu/TelegramPhotoBot/venv/bin/activate" ]; then
    source /home/ubuntu/TelegramPhotoBot/venv/bin/activate
    echo "✅ Activated virtual environment"
else
    echo "⚠️ Virtual environment not found, using system Python"
fi

# --- Ensure the systemd service exists ---
echo "🛠️ Updating systemd service: $SERVICE_NAME"
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Telegram Photo Bot
After=network.target

[Service]
ExecStart=/usr/bin/python3 /home/ubuntu/TelegramPhotoBot/polybot/app.py
WorkingDirectory=/home/ubuntu/TelegramPhotoBot/polybot
Restart=always
User=ubuntu
EnvironmentFile=${ENV_FILE}

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable the service (no restart yet)
sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
echo "✅ Systemd service $SERVICE_NAME updated and enabled"

# --- Start ngrok if not running ---
NGROK_PID=$(pgrep -f 'ngrok http 8443')
if [ -z "$NGROK_PID" ]; then
    echo "Starting ngrok on port 8443..."
    nohup ngrok http 8443 > /dev/null 2>&1 &
    sleep 3
else
    echo "ngrok already running (PID $NGROK_PID)"
fi

# --- Get ngrok public HTTPS URL ---
NGROK_URL=""
for i in {1..5}; do
    NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[] | select(.proto == "https") | .public_url' 2>/dev/null)
    if [[ -n "$NGROK_URL" && "$NGROK_URL" != "null" ]]; then
        break
    fi
    echo "Waiting for ngrok to be ready... (attempt $i/5)"
    sleep 2
done

if [[ -z "$NGROK_URL" || "$NGROK_URL" == "null" ]]; then
    echo "❌ Failed to get ngrok URL"
    exit 1
fi

echo "Ngrok public URL: $NGROK_URL"

# --- Update BOT_APP_URL in the env file ---
# Remove old BOT_APP_URL line and append new one
sed -i '/^BOT_APP_URL=/d' "$ENV_FILE"
echo "BOT_APP_URL=$NGROK_URL" >> "$ENV_FILE"
echo "✅ Updated BOT_APP_URL in $ENV_FILE"

# --- Reload env vars for this script run ---
set -a
source "$ENV_FILE"
set +a

# --- Set Telegram webhook ---
if [[ -n "$NGROK_URL" && "$NGROK_URL" != "null" ]]; then
    WEBHOOK_RESPONSE=$(curl -s -F "url=${NGROK_URL}/${TELEGRAM_BOT_TOKEN}/" \
         https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook)
    echo "Webhook response: $WEBHOOK_RESPONSE"
    echo "✅ Telegram webhook set to ${NGROK_URL}/${TELEGRAM_BOT_TOKEN}/"
else
    echo "❌ Cannot set webhook - invalid ngrok URL"
fi

# --- Now Restart the systemd service ---
echo "Restarting bot service..."
sudo systemctl daemon-reload
sudo systemctl restart $SERVICE_NAME
echo "✅ Service $SERVICE_NAME restarted"