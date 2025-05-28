#!/bin/bash
#exec > /home/ubuntu/TelegramPhotoBot/polybot/bot.log 2>&1
set -x

# Load environment variables
set -a
source /etc/telegram_bot_env
set +a

SERVICE_NAME="telegrambot"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# Activate virtual environment
source /home/ubuntu/TelegramPhotoBot/venv/bin/activate

# Ensure the systemd service exists
if [ ! -f "$SERVICE_FILE" ]; then
    echo "Creating systemd service: $SERVICE_NAME"
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Telegram Photo Bot
After=network.target

[Service]
ExecStart=/home/ubuntu/TelegramPhotoBot/polybot/start.sh
WorkingDirectory=/home/ubuntu/TelegramPhotoBot
Restart=always
User=ubuntu
EnvironmentFile=/etc/telegram_bot_env

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    echo "✅ Systemd service $SERVICE_NAME created and enabled"
else
    echo "✅ Systemd service $SERVICE_NAME already exists"
fi

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

# Update BOT_APP_URL in the env file
sudo sed -i '/^BOT_APP_URL=/d' /etc/telegram_bot_env
echo "BOT_APP_URL=$NGROK_URL" | sudo tee -a /etc/telegram_bot_env

# Reload updated env vars
set -a
source /etc/telegram_bot_env
set +a

# Set webhook
curl -s -F "url=${BOT_APP_URL}/${TELEGRAM_BOT_TOKEN}/" \
     https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook

# Restart the service to apply changes
echo "Restarting bot service..."
sudo systemctl restart $SERVICE_NAME
