#!/bin/bash
set -e

REPO_URL="https://github.com/NorskHelsenett/ollama-metrics.git"
TARGET_DIR="/usr/local/bin/Updater/updateScripts/ollama-metrics"
COMPOSE_DIR="$TARGET_DIR/prometheus"

# Docker internal host gateway IP for Linux
DOCKER_HOST_IP="172.17.0.1"

# 1. Safely clone or reset to pristine tracked files
mkdir -p "$(dirname "$TARGET_DIR")"

if [ ! -d "$TARGET_DIR/.git" ]; then
    echo "Repository not found. Cloning..."
    git clone "$REPO_URL" "$TARGET_DIR"
else
    echo "Repository exists. Resetting tracked files to pristine state..."
    cd "$TARGET_DIR"
    git fetch --all
    git reset --hard origin/main
fi

# Ensure correct local directory ownership
sudo chown -R $(whoami):$(whoami) "$TARGET_DIR"

cd "$COMPOSE_DIR"

# 2. Configure standard environment variables
echo "Configuring environment variables (.env)..."
cat << EOF > .env
METRICS_TARGET_IP=$DOCKER_HOST_IP:8080
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
EOF

# 3. Patch prometheus.yml
echo "Patching prometheus.yml for native Linux Docker routing and 1s scrape..."
sed -i 's/\xC2\xA0/ /g' prometheus.yml
sed -i "s/host.docker.internal:8080/$DOCKER_HOST_IP:8080/g" prometheus.yml
sed -i 's/scrape_interval: 15s/scrape_interval: 1s/g' prometheus.yml

# 4. Set up native provisioning structures
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

# 5. Copy the dashboard
echo "Provisioning dashboard.json..."
cp dashboard.json provisioning/dashboards/dashboard.json

# 6. Generate docker-compose.override.yml
echo "Generating docker-compose.override.yml..."
cat << 'EOF' > docker-compose.override.yml
services:
  prometheus:
    ports:
      - "9090:9090"
    extra_hosts:
      - "host.docker.internal:host-gateway"
  grafana:
    volumes:
      - ./provisioning/datasources:/etc/grafana/provisioning/datasources
      - ./provisioning/dashboards:/etc/grafana/provisioning/dashboards
      - ./provisioning/dashboards/dashboard.json:/var/lib/grafana/dashboards/dashboard.json:ro
EOF

# 7. Restart stack (preserves volumes)
echo "Restarting Grafana and Prometheus stack..."
docker-compose down
docker-compose up -d

# 8. Start the Ollama proxy sidecar
echo "Ensuring Ollama metrics proxy sidecar is running on port 8080..."
docker rm -f ollama-metrics-proxy 2>/dev/null || true
docker run -d --name ollama-metrics-proxy \
  -e OLLAMA_HOST=http://host.docker.internal:11434 \
  -p 8080:8080 \
  --add-host=host.docker.internal:host-gateway \
  --restart unless-stopped \
  ghcr.io/norskhelsenett/ollama-metrics:latest

echo "Deployment complete."
