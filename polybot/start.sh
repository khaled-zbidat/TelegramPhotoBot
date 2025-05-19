#!/bin/bash
exec > /home/ubuntu/TelegramPhotoBot/polybot/bot.log 2>&1
set -x
set -a
source /etc/telegram_bot_env
set +a

# Activate virtual environment
source /home/ubuntu/TelegramPhotoBot/venv/bin/activate

# Check if ngrok is running on port 8443
NGROK_PID=$(pgrep -f "ngrok http 8443")

if [ -z "$NGROK_PID" ]; then
    echo "Starting ngrok on port 8443 with static domain..."
    nohup ngrok http --url=koi-suitable-closely.ngrok-free.app 8443 > /dev/null 2>&1 &
    sleep 5  # give ngrok some time to start
else
    echo "ngrok already running (PID $NGROK_PID)"
fi

# Update .env file with static ngrok url
ENV_FILE="/home/ubuntu/TelegramPhotoBot/polybot/.env"
sed -i '/^BOT_APP_URL=/d' "$ENV_FILE"
echo "BOT_APP_URL=https://koi-suitable-closely.ngrok-free.app" >> "$ENV_FILE"

echo "Starting bot..."
cd /home/ubuntu/TelegramPhotoBot/polybot
python3 -m polybot.app



# Start ngrok tunnel with your static domain, forwarding port 80

#ngrok http --url=koi-suitable-closely.ngrok-free.app 8443
# Wait a bit for ngrok to initialize
#sleep 5

# Start your bot container using Docker Compose in detached mode


# Load environment variables from secure file
# set -a
# source /etc/telegram_bot_env
# set +a

# # Activate virtual environment
# source /home/ubuntu/TelegramPhotoBot/venv/bin/activate
# ngrok http --url=koi-suitable-closely.ngrok-free.app 8443
# #ngrok http 8443
# # Run the app
# python3 -m polybot.app
# #ok