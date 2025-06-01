#!/bin/bash
set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🚀 Starting Polybot Enhanced..."
echo "Script directory: $SCRIPT_DIR"
echo "Project root: $PROJECT_ROOT"

# Load environment variables from .env file
ENV_FILE="$SCRIPT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ ERROR: .env file not found at $ENV_FILE"
    exit 1
fi

# Source the .env file
set -a
source "$ENV_FILE"
set +a

# Validate required environment variables
if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
    echo "❌ ERROR: TELEGRAM_BOT_TOKEN not found in .env file"
    exit 1
fi

if [[ -z "$YOLO_URL" ]]; then
    echo "❌ ERROR: YOLO_URL not found in .env file"
    exit 1
fi

echo "✓ Environment variables loaded successfully"
echo "✓ TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN:0:10}..."
echo "✓ YOLO_URL: $YOLO_URL"

# Change to project root directory
cd "$PROJECT_ROOT"

# Activate virtual environment
VENV_PATH="$PROJECT_ROOT/venv"
if [ ! -f "$VENV_PATH/bin/activate" ]; then
    echo "❌ ERROR: Virtual environment not found at $VENV_PATH"
    exit 1
fi

echo "→ Activating virtual environment..."
source "$VENV_PATH/bin/activate"
echo "✓ Virtual environment activated"

# Set webhook URL (replace with your actual NGINX domain)
WEBHOOK_URL="https://your-nginx-domain.com/${TELEGRAM_BOT_TOKEN}/"
echo "→ Setting webhook URL: $WEBHOOK_URL"

curl -s -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
    -d "url=$WEBHOOK_URL" > /dev/null

if [ $? -eq 0 ]; then
    echo "✓ Webhook set successfully"
else
    echo "⚠️  Warning: Failed to set webhook, but continuing..."
fi

# Start the bot
echo "🤖 Launching bot..."
cd "$SCRIPT_DIR" || { echo "❌ Failed to cd into $SCRIPT_DIR"; exit 1; }

# Debugging path info
echo "=== DEBUG PATH INFO ==="
echo "Current path: $(pwd)"
echo "Script dir: $SCRIPT_DIR"
ls -l  # Show directory contents for verification
echo "PAAAAAAAAATHHHHHH"

# Launch the bot
python3 -m polybot.app