#!/bin/bash
set -e

# Enhanced logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /tmp/polybot.log
}

# Function to cleanup on exit
cleanup() {
    log "🧹 Cleaning up processes..."
    pkill -f "ngrok http" || true
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Function to check if ngrok is installed
check_ngrok_installation() {
    if ! command -v ngrok &> /dev/null; then
        log "❌ ngrok is not installed. Installing ngrok..."
        
        # Download and install ngrok
        curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
        echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
        sudo apt update
        sudo apt install ngrok
        
        log "✓ ngrok installed successfully"
    else
        log "✓ ngrok is already installed"
    fi
}

# Function to authenticate ngrok
authenticate_ngrok() {
    local token="$1"
    if [ -z "$token" ]; then
        log "❌ NGROK_TOKEN is not set!"
        return 1
    fi
    
    log "→ Configuring ngrok authentication..."
    ngrok config add-authtoken "$token"
    log "✓ ngrok authenticated successfully"
}

# Function to start ngrok with better error handling
start_ngrok_if_needed() {
    # Kill any existing ngrok processes
    pkill -f "ngrok http" || true
    sleep 2
    
    log "→ Starting ngrok on port 8443..."
    
    # Start ngrok in background with explicit config
    nohup ngrok http 8443 --log stdout > /tmp/ngrok.log 2>&1 &
    local ngrok_pid=$!
    
    log "→ ngrok started with PID: $ngrok_pid"
    
    # Wait for ngrok to initialize
    local max_wait=30
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if pgrep -f "ngrok http" > /dev/null; then
            log "✓ ngrok process is running"
            break
        fi
        log "→ Waiting for ngrok to start... ($wait_time/$max_wait)"
        sleep 2
        wait_time=$((wait_time + 2))
    done
    
    if ! pgrep -f "ngrok http" > /dev/null; then
        log "❌ ngrok failed to start within timeout"
        log "→ ngrok log output:"
        cat /tmp/ngrok.log || true
        return 1
    fi
    
    # Additional wait for API to be ready
    sleep 5
}

# Function to get ngrok public URL with better error handling
fetch_ngrok_url() {
    local max_attempts=15
    local attempt=1
    
    log "→ Fetching ngrok public URL..."
    
    while [ $attempt -le $max_attempts ]; do
        log "→ Attempt $attempt/$max_attempts: Checking ngrok API..."
        
        # Check if ngrok API is responding
        if ! curl -s http://127.0.0.1:4040/api/tunnels > /dev/null 2>&1; then
            log "→ ngrok API not ready yet, waiting..."
            sleep 3
            ((attempt++))
            continue
        fi
        
        # Try to get the URL
        local response=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null)
        if [ $? -ne 0 ]; then
            log "→ Failed to query ngrok API"
            sleep 3
            ((attempt++))
            continue
        fi
        
        # Parse the URL
        local url=$(echo "$response" | jq -r '.tunnels[0].public_url' 2>/dev/null)
        
        if [ "$url" != "null" ] && [ -n "$url" ] && [[ "$url" == https://* ]]; then
            log "✓ Got ngrok URL: $url"
            echo "$url"
            return 0
        fi
        
        log "→ URL not ready yet (got: $url), retrying..."
        sleep 3
        ((attempt++))
    done
    
    log "❌ Failed to get ngrok URL after $max_attempts attempts"
    log "→ Final ngrok API response:"
    curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | jq . || echo "Failed to get API response"
    log "→ ngrok log:"
    tail -20 /tmp/ngrok.log || true
    return 1
}

# Function to update .env with BOT_APP_URL - FIXED VERSION
update_env_file_with_url() {
    local env_file="$1"
    local url="$2"
    
    log "→ Updating .env file with URL: $url"
    
    # Create a temporary file to avoid corrupting the original
    local temp_file=$(mktemp)
    
    # Copy only valid environment variables (KEY=VALUE format)
    # This automatically removes any corrupted log entries
    grep -E '^[A-Z_][A-Z0-9_]*=' "$env_file" > "$temp_file" 2>/dev/null || true
    
    # Remove any existing BOT_APP_URL
    grep -v "^BOT_APP_URL=" "$temp_file" > "${temp_file}.clean" 2>/dev/null || true
    mv "${temp_file}.clean" "$temp_file"
    
    # Add the new BOT_APP_URL
    echo "BOT_APP_URL=$url" >> "$temp_file"
    
    # Replace the original file
    mv "$temp_file" "$env_file"
    
    export BOT_APP_URL="$url"
    log "✓ .env file automatically cleaned and updated successfully"
}

# Function to validate environment - FIXED VERSION
validate_environment() {
    local project_path="$1"
    local env_file="$project_path/polybot/.env"
    
    log "→ Validating environment..."
    
    if [ ! -f "$env_file" ]; then
        log "❌ .env file not found at: $env_file"
        return 1
    fi
    
    # Load environment variables without executing them as commands
    # Use a safer method to read the .env file
    while IFS='=' read -r key value; do
        # Skip empty lines and comments
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        
        # Remove any quotes from the value
        value=$(echo "$value" | sed 's/^"//;s/"$//')
        
        # Export the variable
        export "$key"="$value"
    done < <(grep -E '^[^#]*=' "$env_file")
    
    if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
        log "❌ TELEGRAM_BOT_TOKEN not set in .env"
        return 1
    fi
    
    if [ -z "$YOUR_NGROK_TOKEN" ]; then
        log "❌ YOUR_NGROK_TOKEN not set in .env"
        return 1
    fi
    
    if [ -z "$YOLO_URL" ]; then
        log "❌ YOLO_URL not set in .env"
        return 1
    fi
    
    log "✓ Environment validation passed"
    return 0
}

# === Main Script ===
main() {
    local project_path="$1"
    
    log "🚀 Starting Polybot Enhanced..."
    log "Project path: $project_path"
    
    if [ -z "$project_path" ]; then
        log "❌ Usage: $0 <project_path>"
        exit 1
    fi

    ENV_FILE="$project_path/polybot/.env"
    VENV_PATH="$project_path/venv"
    
    # Validate environment first
    if ! validate_environment "$project_path"; then
        log "❌ Environment validation failed"
        exit 1
    fi
    
    # Export ngrok token for authentication
    export NGROK_TOKEN="${YOUR_NGROK_TOKEN}"
    
    # Check ngrok installation
    check_ngrok_installation
    
    # Authenticate ngrok
    if ! authenticate_ngrok "$NGROK_TOKEN"; then
        log "❌ ngrok authentication failed"
        exit 1
    fi
    
    # Start ngrok
    if ! start_ngrok_if_needed; then
        log "❌ Failed to start ngrok"
        exit 1
    fi
    
    # Get ngrok URL
    bot_url=$(fetch_ngrok_url)
    if [ -z "$bot_url" ]; then
        log "❌ Failed to retrieve ngrok public URL"
        exit 1
    fi
    
    # Update .env and export URL
    update_env_file_with_url "$ENV_FILE" "$bot_url"
    
    # Activate virtual environment
    if [ ! -f "$VENV_PATH/bin/activate" ]; then
        log "❌ Virtual environment not found at: $VENV_PATH"
        exit 1
    fi
    
    log "→ Activating virtual environment..."
    source "$VENV_PATH/bin/activate"
    log "✓ Virtual environment activated"
    
    # Change to project root directory
    cd "$project_path"
    
    log "🤖 Launching bot with URL: $bot_url"
    
    # Set Python path and start the bot
    export PYTHONPATH="$project_path"
    exec python3 -m polybot.app
}

main "$1"