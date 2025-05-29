#!/bin/bash
set -e

# Function to start ngrok if it's not running
start_ngrok_if_needed() {
    if ! pgrep -f "ngrok http 8443" > /dev/null; then
        echo "→ Starting ngrok on port 8443..."
        nohup /usr/local/bin/ngrok http 8443 --authtoken $NGROK_TOKEN > /dev/null 2>&1 &    
        sleep 5  # Give ngrok more time to start
    else
        echo "✓ ngrok is already running."
    fi
}

# Function to get ngrok public URL
fetch_ngrok_url() {
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local url=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | jq -r '.tunnels[0].public_url' 2>/dev/null)
        if [ "$url" != "null" ] && [ -n "$url" ]; then
            echo "$url"
            return 0
        fi
        echo "→ Attempt $attempt: Waiting for ngrok to be ready..."
        sleep 2
        ((attempt++))
    done
    
    echo ""
    return 1
}

# Function to update .env with BOT_APP_URL
update_env_file_with_url() {
    local env_file="$1"
    local url="$2"
    
    if grep -q "^BOT_APP_URL=" "$env_file"; then
        sed -i "s|^BOT_APP_URL=.*|BOT_APP_URL=$url|" "$env_file"
    else
        echo "BOT_APP_URL=$url" >> "$env_file"
    fi
    export BOT_APP_URL="$url"
}

# === Main Script ===
main() {
    local project_path="$1"
    
    if [ -z "$project_path" ]; then
        echo "Usage: $0 <project_path>"
        exit 1
    fi

    ENV_FILE="$project_path/polybot/.env"
    VENV_PATH="$project_path/venv"
    
    echo "🚀 Starting Polybot..."
    echo "Project path: $project_path"
    
    # Load environment variables
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    fi
    
    # Set ngrok token from environment
    export NGROK_TOKEN="${YOUR_NGROK_TOKEN}"
    
    # Start ngrok
    start_ngrok_if_needed
    
    # Get ngrok URL
    echo "→ Fetching ngrok URL..."
    bot_url=$(fetch_ngrok_url)
    
    if [ -z "$bot_url" ]; then
        echo "❌ Failed to retrieve ngrok public URL"
        exit 1
    fi
    
    echo "✓ ngrok URL: $bot_url"
    
    # Update .env and export URL
    update_env_file_with_url "$ENV_FILE" "$bot_url"
    
    # Activate virtual environment
    source "$VENV_PATH/bin/activate"
    echo "✓ Virtual environment activated."
    
    # Change to project root directory
    cd "$project_path"

    echo "🤖 Launching bot..."
    PYTHONPATH="$project_path" python3 -m polybot.app
}

main "$1"
