#!/bin/bash
set -e

TELEGRAM_TOKEN="$1"
YOLO_URL="$2"

if [[ -z "$TELEGRAM_TOKEN" || -z "$YOLO_URL" ]]; then
    echo "Usage: $0 <TELEGRAM_TOKEN> <YOLO_URL>"
    exit 1
fi

echo "🚀 Starting Telegram Bot..."

# Stop old service if running
sudo systemctl stop telegrambot 2>/dev/null || true

# Write .env
cat > "$(dirname "$0")/.env" <<EOF
TELEGRAM_BOT_TOKEN=$TELEGRAM_TOKEN
YOLO_URL=$YOLO_URL
EOF

# Set webhook — assumes NGINX is already exposing the bot properly
curl -s -X POST \
    "https://api.telegram.org/bot${TELEGRAM_TOKEN}/setWebhook" \
    -d "url=https://your-nginx-domain.com/${TELEGRAM_TOKEN}/" > /dev/null

# Start service
sudo systemctl start telegrambot

sleep 3
if sudo systemctl is-active --quiet telegrambot; then
    echo "✅ Bot started successfully!"
else
    echo "❌ Bot failed to start"
    sudo journalctl -u telegrambot -n 10 --no-pager
    exit 1
fi
