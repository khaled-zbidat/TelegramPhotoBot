#!/bin/bash
set -e

PROJECT_DIR="$1"
TELEGRAM_TOKEN="$2"
YOLO_URL="$3"

if [[ -z "$PROJECT_DIR" || -z "$TELEGRAM_TOKEN" || -z "$YOLO_URL" ]]; then
    echo "Usage: $0 <PROJECT_DIR> <TELEGRAM_TOKEN> <YOLO_URL>"
    exit 1
fi

cd "$PROJECT_DIR"

echo "→ Setting up OpenTelemetry Collector..."
# Check if OTC is already installed
if ! command -v otelcol &> /dev/null; then
    echo "→ Installing OpenTelemetry Collector..."
    sudo apt-get update
    sudo apt-get -y install wget
    wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.127.0/otelcol_0.127.0_linux_amd64.deb
    sudo dpkg -i otelcol_0.127.0_linux_amd64.deb
    rm -f otelcol_0.127.0_linux_amd64.deb
    echo "✓ OpenTelemetry Collector installed successfully"
else
    echo "✓ OpenTelemetry Collector already installed"
fi

# Configure OTC for prod environment
echo "→ Configuring OpenTelemetry Collector for PROD environment..."
sudo tee /etc/otelcol/config.yaml > /dev/null << 'EOF'
receivers:
  hostmetrics:
    collection_interval: 15s
    scrapers:
      cpu:
      memory:
      disk:
      filesystem:
      load:
      network:
      processes:

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"
    resource_to_telemetry_conversion:
      enabled: true
    add_metric_suffixes: false

service:
  pipelines:
    metrics:
      receivers: [hostmetrics]
      exporters: [prometheus]
  telemetry:
    logs:
      level: warn
EOF

# Enable and restart OTC service
sudo systemctl enable otelcol
sudo systemctl restart otelcol

# Verify OTC is running
if systemctl is-active --quiet otelcol; then
    echo "✓ OpenTelemetry Collector is running on port 8889"
else
    echo "⚠️  Warning: OpenTelemetry Collector failed to start"
    sudo journalctl -u otelcol -n 10 --no-pager
fi

echo "→ Setting up deployment files..."
chmod +x deploy_prod.sh
chmod +x polybot/start_prod.sh

# Create virtual environment
VENV_DIR="$PROJECT_DIR/venv"
if [ ! -f "$VENV_DIR/bin/activate" ]; then
    echo "→ Creating virtual environment..."
    python3.12 -m venv "$VENV_DIR"
fi

# Activate and install dependencies
echo "→ Activating virtual environment and installing requirements..."
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install -r "$PROJECT_DIR/polybot/requirements.txt"

# Write environment file
ENV_FILE="$PROJECT_DIR/polybot/.env"
echo "→ Writing environment file: $ENV_FILE"
cat > "$ENV_FILE" << EOF
TELEGRAM_BOT_TOKEN=$TELEGRAM_TOKEN
YOLO_URL=$YOLO_URL
EOF

echo "✓ Environment file created with:"
echo "  - TELEGRAM_BOT_TOKEN: ${TELEGRAM_TOKEN:0:10}..."
echo "  - YOLO_URL: $YOLO_URL"

# Stop existing service if running
sudo systemctl stop polyservice_prod.service 2>/dev/null || echo "Service was not running"

# Copy and reload systemd service
echo "→ Installing systemd service..."
sudo cp polyservice_prod.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable polyservice_prod.service
sudo systemctl start polyservice_prod.service

# Wait a moment for service to start
sleep 3

# Final check
if systemctl is-active --quiet polyservice_prod.service; then
    echo "✅ Service is running successfully!"
    echo "→ Checking service status:"
    sudo systemctl status polyservice_prod.service --no-pager -l
else
    echo "❌ Service failed to start:"
    sudo journalctl -u polyservice_prod.service -n 20 --no-pager
    exit 1
fi

echo "🎉 Deployment completed!"
echo "📊 Metrics available at: http://$(curl -s ifconfig.me):8889/metrics"