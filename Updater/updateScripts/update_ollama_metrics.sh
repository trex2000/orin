#!/bin/bash
REPO_URL="https://github.com/NorskHelsenett/ollama-metrics.git"
TARGET_DIR="/usr/local/bin/Updater/updateScripts/ollama-metrics"
COMPOSE_DIR="$TARGET_DIR/prometheus"

# Ensure target directory parent exists
mkdir -p "$(dirname "$TARGET_DIR")"

# Ensure correct local directory ownership to prevent Git dubious ownership errors
if [ -d "$TARGET_DIR" ]; then
    sudo chown -R $(whoami):$(whoami) "$TARGET_DIR"
fi

if [ ! -d "$TARGET_DIR" ]; then
    echo "Directory '$TARGET_DIR' not found. Cloning repository..."
    git clone "$REPO_URL" "$TARGET_DIR"
    cd "$COMPOSE_DIR" || exit 1
else
    echo "Directory '$TARGET_DIR' exists. Tearing down containers..."
    cd "$COMPOSE_DIR" || exit 1
    docker-compose down
    
    echo "Pulling latest repository updates..."
    cd "$TARGET_DIR" || exit 1
    git pull
    cd prometheus || exit 1
fi

# Automatically configure all parameters cleanly in the .env file
echo "Configuring environment variables (.env)..."
cat << 'EOF' > .env
METRICS_TARGET_IP=192.168.1.6:8080
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
EOF

echo "Starting/Restarting Grafana and Prometheus stack..."
docker-compose up -d

echo "Ensuring Ollama metrics proxy sidecar is running on port 8080..."
docker rm -f ollama-metrics-proxy 2>/dev/null || true
docker run -d --name ollama-metrics-proxy \
  -e OLLAMA_HOST=http://host.docker.internal:11434 \
  -p 8080:8080 \
  --add-host=host.docker.internal:host-gateway \
  --restart unless-stopped \
  ghcr.io/norskhelsenett/ollama-metrics:latest

echo "All systems live! Environment configured via .env and metrics stack is fully running."
