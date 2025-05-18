#!/bin/bash

# Load environment variables
set -a
source /etc/telegram_bot_env
set +a

# Activate virtual environment
source /home/ubuntu/TelegramPhotoBot/venv/bin/activate

# Start ngrok with custom domain
ngrok http --url="$NGROK_DOMAIN" 8443 &

# Optional: wait for ngrok to fully start
sleep 5

# Run the bot
python3 -m polybot.app
