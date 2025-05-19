#!/bin/bash
exec > /home/ubuntu/TelegramPhotoBot/polybot/bot.log 2>&1
set -x

# Load environment variables from your actual env file
set -a
source /etc/telegram_bot_env
set +a

SERVICE_NAME="telegrambot"
# Activate virtual environment
source /home/ubuntu/TelegramPhotoBot/venv/bin/activate

# Start ngrok if not running
NGROK_PID=$(pgrep -f 'ngrok http 8443')
if [ -z "$NGROK_PID" ]; then
    echo "Starting ngrok on port 8443..."
    nohup ngrok http 8443 > /dev/null 2>&1 &
    sleep 3
else
    echo "ngrok already running (PID $NGROK_PID)"
fi

# Get the ngrok public HTTPS URL
NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[] | select(.proto == "https") | .public_url')
echo "Ngrok public URL: $NGROK_URL"

# Update /etc/telegram_bot_env with new BOT_APP_URL
sudo sed -i '/^BOT_APP_URL=/d' /etc/telegram_bot_env
echo "BOT_APP_URL=$NGROK_URL" | sudo tee -a /etc/telegram_bot_env

# Reload updated environment
set -a
source /etc/telegram_bot_env
set +a

# Optionally update the Telegram webhook
curl -s -F "url=${BOT_APP_URL}/${TELEGRAM_BOT_TOKEN}/" \
     https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook

echo "Starting bot..."
python3 -m polybot.app

echo "Restarting bot service..."
sudo systemctl restart $SERVICE_NAME