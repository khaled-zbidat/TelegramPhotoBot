#!/bin/bash

# Enhanced Polybot Startup Script with ngrok integration
# Usage: ./start_polybot.sh [project_path]

set -e  # Exit on any error

# Configuration
PROJECT_PATH="${1:-$(pwd)}"
POLYBOT_DIR="$PROJECT_PATH/polybot"
VENV_PATH="$PROJECT_PATH/venv"
NGROK_PORT=8443
MAX_RETRIES=15
RETRY_DELAY=1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Redirect all log() output to stderr
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

# Error handling
error_exit() {
    log "❌ ERROR: $1"
    exit 1
}

# Success message
success() {
    log "✓ $1"
}

# Warning message
warning() {
    log "⚠️  $1"
}

# Function to stop all ngrok processes
stop_all_ngrok() {
    log "→ Stopping all ngrok processes..."
    
    # Kill all ngrok processes
    pkill -f "ngrok" 2>/dev/null || true
    
    # Wait a bit for processes to terminate
    sleep 3
    
    # Force kill if any remain
    pkill -9 -f "ngrok" 2>/dev/null || true
    
    # Also try to stop via API if available
    curl -s -X DELETE http://localhost:4040/api/tunnels 2>/dev/null || true
    
    success "All ngrok processes stopped"
}

# Function to get ngrok URL (without logging mixed in)
get_ngrok_url() {
    local retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
        retries=$((retries + 1))

        local ngrok_url=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | \
             python3 -c "import sys,json; data=json.load(sys.stdin); print(data['tunnels'][0]['public_url'] if data.get('tunnels') else '')" 2>/dev/null || echo "")

        if [ -n "$ngrok_url" ] && [[ "$ngrok_url" == https://* ]]; then
            echo "$ngrok_url"
            return 0
        fi

        sleep $RETRY_DELAY
    done
    return 1
}

# Function to clean and update .env file
update_env_file() {
    local new_url="$1"
    local env_file="$POLYBOT_DIR/.env"
    
    # Create a temporary file
    local temp_file=$(mktemp)
    
    # Read the current .env file and clean it
    while IFS='=' read -r key value; do
        # Skip empty lines and comments
        [[ -z "$key" || "$key" =~ ^#.*$ ]] && continue
        
        # Clean the key (remove whitespace)
        key=$(echo "$key" | xargs)
        
        # Skip lines that don't look like proper env vars
        [[ ! "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] && continue
        
        if [ "$key" = "BOT_APP_URL" ]; then
            echo "BOT_APP_URL=$new_url" >> "$temp_file"
        else
            # Clean the value (remove any log messages or timestamps)
            if [[ "$value" =~ ^https?:// ]]; then
                # If it's a URL, extract just the URL part
                clean_value=$(echo "$value" | grep -o 'https\?://[^[:space:]]*' | head -1)
                echo "$key=$clean_value" >> "$temp_file"
            elif [[ ! "$value" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
                # If it doesn't contain timestamps, keep it
                clean_value=$(echo "$value" | xargs)
                echo "$key=$clean_value" >> "$temp_file"
            fi
        fi
    done < "$env_file"
    
    # Replace the original file
    mv "$temp_file" "$env_file"
}

# Function to check if ngrok is already running
check_existing_ngrok() {
    if curl -s http://localhost:4040/api/tunnels >/dev/null 2>&1; then
        local existing_url=$(curl -s http://localhost:4040/api/tunnels | \
             python3 -c "import sys,json; data=json.load(sys.stdin); tunnels=[t for t in data.get('tunnels', []) if t.get('config', {}).get('addr') == 'http://localhost:$NGROK_PORT']; print(tunnels[0]['public_url'] if tunnels else '')" 2>/dev/null || echo "")
        
        if [ -n "$existing_url" ] && [[ "$existing_url" == https://* ]]; then
            log "✓ Found existing ngrok tunnel: $existing_url"
            echo "$existing_url"
            return 0
        fi
    fi
    return 1
}

# Main script starts here
log "🚀 Starting Polybot Enhanced..."
log "Project path: $PROJECT_PATH"

# Validate environment
log "→ Validating environment..."
cd "$PROJECT_PATH" || error_exit "Cannot access project directory: $PROJECT_PATH"

if [ ! -f "$POLYBOT_DIR/.env" ]; then
    error_exit ".env file not found in $POLYBOT_DIR"
fi

if [ ! -d "$VENV_PATH" ]; then
    error_exit "Virtual environment not found at $VENV_PATH"
fi

success "Environment validation passed"

# Load environment variables
set -a  # automatically export all variables
source "$POLYBOT_DIR/.env"
set +a

# Validate required environment variables
[ -z "$TELEGRAM_BOT_TOKEN" ] && error_exit "TELEGRAM_BOT_TOKEN not set in .env"
[ -z "$YOUR_NGROK_TOKEN" ] && error_exit "YOUR_NGROK_TOKEN not set in .env"

# Check if ngrok is installed
if ! command -v ngrok &> /dev/null; then
    log "→ Installing ngrok..."
    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
    sudo apt update && sudo apt install ngrok -y
    success "ngrok installed"
else
    success "ngrok is already installed"
fi

# Configure ngrok authentication
log "→ Configuring ngrok authentication..."
ngrok config add-authtoken "$YOUR_NGROK_TOKEN"
success "ngrok authenticated successfully"

# Check for existing ngrok tunnel first
log "→ Checking for existing ngrok tunnels..."
NGROK_URL=""
if NGROK_URL=$(check_existing_ngrok); then
    log "✓ Using existing ngrok tunnel: $NGROK_URL"
else
    # Stop all existing ngrok processes to avoid conflicts
    stop_all_ngrok
    
    # Wait a moment before starting new ngrok
    sleep 2
    
    # Start ngrok
    log "→ Starting ngrok on port $NGROK_PORT..."
    ngrok http $NGROK_PORT --log=stdout > /tmp/ngrok.log 2>&1 &
    NGROK_PID=$!
    sleep 3
    
    # Verify ngrok is running
    if ! kill -0 $NGROK_PID 2>/dev/null; then
        log "❌ ngrok process died, checking logs..."
        cat /tmp/ngrok.log >&2
        error_exit "Failed to start ngrok"
    fi
    
    log "→ ngrok started with PID: $NGROK_PID"
    success "ngrok process is running"
    
    # Wait for ngrok to be ready and get URL
    log "→ Fetching ngrok public URL..."
    sleep 5
    
    NGROK_URL=$(get_ngrok_url)
    if [ -z "$NGROK_URL" ]; then
        log "❌ Failed to get ngrok URL, checking logs..."
        cat /tmp/ngrok.log >&2
        error_exit "Failed to get ngrok URL after $MAX_RETRIES attempts"
    fi
    
    log "✓ Got ngrok URL: $NGROK_URL"
fi

# Update .env file with clean URL
log "→ Updating .env file with URL: $NGROK_URL"
update_env_file "$NGROK_URL"
success ".env file automatically cleaned and updated successfully"

# Reload environment variables
set -a
source "$POLYBOT_DIR/.env"
set +a

# Activate virtual environment
log "→ Activating virtual environment..."
source "$VENV_PATH/bin/activate"
success "Virtual environment activated"

# Launch the bot
log "🤖 Launching bot with URL: $NGROK_URL"
cd "$POLYBOT_DIR"

# Export the clean URL for the Python script
export BOT_APP_URL="$NGROK_URL"

# Start the bot
python -m polybot.app