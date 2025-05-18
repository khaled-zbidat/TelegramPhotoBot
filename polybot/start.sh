#!/bin/bash

# Start ngrok tunnel with your static domain, forwarding port 80

#ngrok http --url=koi-suitable-closely.ngrok-free.app 8443
# Wait a bit for ngrok to initialize
#sleep 5

# Start your bot container using Docker Compose in detached mode


# Load environment variables from secure file
set -a
source /etc/telegram_bot_env
set +a

# Activate virtual environment
source /home/ubuntu/TelegramPhotoBot/venv/bin/activate

# Run the app
python3 -m polybot.app
