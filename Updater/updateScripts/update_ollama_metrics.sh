#!/bin/bash
set -e

REPO_URL="https://github.com/NorskHelsenett/ollama-metrics.git"
TARGET_DIR="/usr/local/bin/Updater/updateScripts/ollama-metrics"
COMPOSE_DIR="$TARGET_DIR/prometheus"

# Docker internal host gateway IP
DOCKER_HOST_IP="172.17.0.1"

# Ensure target directory parent exists
mkdir -p "$(dirname "$TARGET_DIR")"

# Ensure correct local directory ownership
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
    docker-compose down || true

    echo "Pulling latest repository updates..."
    cd "$TARGET_DIR" || exit 1
    git fetch --all
    git reset --hard origin/main
    cd "$COMPOSE_DIR" || exit 1
fi

# 1. Configure standard environment variables
echo "Configuring environment variables (.env)..."
cat << EOF > .env
METRICS_TARGET_IP=$DOCKER_HOST_IP:8080
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
EOF

# 2. Set up native provisioning structures and enforce dashboard/datasource mapping
echo "Configuring Grafana automatic provisioning..."
mkdir -p provisioning/datasources provisioning/dashboards

cat << 'EOF' > provisioning/datasources/ds.yml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    uid: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOF

cat << 'EOF' > provisioning/dashboards/dashboards.yml
apiVersion: 1
providers:
  - name: 'Ollama Metrics Native'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
EOF

# Copy repository's dashboard.json straight into the provisioning folder
if [ -f "dashboard.json" ]; then
    cp dashboard.json provisioning/dashboards/dashboard.json
fi

# 3. Generate docker-compose.override.yml to mount provisioning files directly into Grafana
echo "Generating docker-compose.override.yml..."
cat << 'EOF' > docker-compose.override.yml
services:
  prometheus:
    ports:
      - "9090:9090"
  grafana:
    volumes:
      - ./provisioning/datasources:/etc/grafana/provisioning/datasources
      - ./provisioning/dashboards:/etc/grafana/provisioning/dashboards
      - ./provisioning/dashboards/dashboard.json:/var/lib/grafana/dashboards/dashboard.json:ro
EOF

# 4. Start Prometheus and Grafana stack (purging container state to clear any volume conflicts)
echo "Starting Grafana and Prometheus stack..."
docker-compose down --volumes --remove-orphans || true
docker-compose up -d

# 5. Start the Ollama proxy sidecar
echo "Ensuring Ollama metrics proxy sidecar is running on port 8080..."
docker rm -f ollama-metrics-proxy 2>/dev/null || true
docker run -d --name ollama-metrics-proxy \
  -e OLLAMA_HOST=http://host.docker.internal:11434 \
  -p 8080:8080 \
  --add-host=host.docker.internal:host-gateway \
  --restart unless-stopped \
  ghcr.io/norskhelsenett/ollama-metrics:latest

echo "All systems live! Dashboard is automatically provisioned and loaded."
