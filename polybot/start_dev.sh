#!/bin/bash
set -e

TELEGRAM_TOKEN="$1"
YOLO_URL="$2"
NGROK_TOKEN="$3"

if [[ -z "$TELEGRAM_TOKEN" || -z "$YOLO_URL" ]]; then
    echo "Usage: $0 <TELEGRAM_TOKEN> <YOLO_URL> [NGROK_TOKEN]"
    exit 1
fi

echo "🚀 Starting Telegram Bot..."

# Stop service if running
sudo systemctl stop telegrambot 2>/dev/null || true

# Stop any existing ngrok
pkill -f 'ngrok http' || true
sleep 2

# Create environment file in main directory (not polybot)
cat > .env <<EOF
TELEGRAM_BOT_TOKEN=$TELEGRAM_TOKEN
YOLO_SERVICE_URL=$YOLO_URL
EOF

# Setup ngrok auth if provided
if [[ -n "$NGROK_TOKEN" ]]; then
    ngrok config add-authtoken "$NGROK_TOKEN"
fi

# Start ngrok
echo "🌐 Starting ngrok tunnel..."
ngrok http 8443 > /tmp/ngrok.log 2>&1 &
sleep 5

# Get ngrok URL
NGROK_URL=""
for i in {1..10}; do
    NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | jq -r '.tunnels[]? | select(.proto == "https") | .public_url' 2>/dev/null || true)
    if [[ -n "$NGROK_URL" && "$NGROK_URL" != "null" ]]; then
        break
    fi
    echo "⏳ Waiting for ngrok... ($i/10)"
    sleep 2
done

if [[ -z "$NGROK_URL" || "$NGROK_URL" == "null" ]]; then
    echo "❌ Failed to get ngrok URL"
    cat /tmp/ngrok.log
    exit 1
fi

echo "🌍 Ngrok URL: $NGROK_URL"

# Add ngrok URL to env file in main directory
echo "BOT_APP_URL=$NGROK_URL" >> .env

# Set Telegram webhook
echo "🔗 Setting webhook..."
curl -s -X POST \
    "https://api.telegram.org/bot${TELEGRAM_TOKEN}/setWebhook" \
    -d "url=${NGROK_URL}/${TELEGRAM_TOKEN}/" > /dev/null

# Start the service
echo "🚀 Starting bot service..."
sudo systemctl start telegrambot

# Check if it started
sleep 3
if sudo systemctl is-active --quiet telegrambot; then
    echo "✅ Bot started successfully!"
    echo "📊 Status:"
    sudo systemctl status telegrambot --no-pager -l
else
    echo "❌ Bot failed to start"
    sudo journalctl -u telegrambot -n 10 --no-pager
    exit 1
fi

echo ""
echo "🎉 Deployment complete!"
echo "📝 Monitor logs: sudo journalctl -u telegrambot -f"