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

# --- Activate python venv ---
source /home/ubuntu/TelegramPhotoBot/venv/bin/activate
echo "✅ Activated virtual environment"

# --- Ensure the systemd service exists ---
echo "🛠️ Updating systemd service: $SERVICE_NAME"
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Telegram Photo Bot
After=network.target

[Service]
ExecStart=/home/ubuntu/TelegramPhotoBot/venv/bin/python /home/ubuntu/TelegramPhotoBot/polybot/app.py
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
NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[] | select(.proto == "https") | .public_url')
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
curl -s -F "url=${BOT_APP_URL}/${TELEGRAM_BOT_TOKEN}/" \
     https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook
echo "✅ Telegram webhook set to ${BOT_APP_URL}/${TELEGRAM_BOT_TOKEN}/"

# --- Now Restart the systemd service ---
echo "Restarting bot service..."
sudo systemctl daemon-reload
sudo systemctl restart $SERVICE_NAME
echo "✅ Service $SERVICE_NAME restarted"