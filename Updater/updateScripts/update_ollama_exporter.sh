#!/bin/bash

# Define paths
TARGET_DIR="/usr/local/bin/Updater/updateScripts/ollama-exporter"

echo "Setting up Ollama Exporter (Dual-Path Mode) in $TARGET_DIR..."

# 1. Clean up old dangling files
rm -f "$TARGET_DIR/provisioning/dashboards_json/dashboard.json" 2>/dev/null

# 2. Create directory structure
mkdir -p "$TARGET_DIR/prometheus"
mkdir -p "$TARGET_DIR/provisioning/datasources"
mkdir -p "$TARGET_DIR/provisioning/dashboards"
mkdir -p "$TARGET_DIR/provisioning/dashboards_json"

# Ensure correct local directory ownership
sudo chown -R $(whoami):$(whoami) "$TARGET_DIR"

cd "$TARGET_DIR"

# 3. Generate Prometheus configuration
echo "Configuring prometheus.yml for 5s scrape..."
cat << EOF > prometheus/prometheus.yml
global:
  scrape_interval: 5s

scrape_configs:
  - job_name: 'ollama'
    static_configs:
      - targets: ['ollama-exporter:9400']
EOF

# 4. Set up Grafana automatic provisioning
echo "Configuring Grafana datasources and dashboards..."
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

# 5. Download the official Maravexa Grafana Dashboard
echo "Downloading Grafana dashboard.json..."
curl -sL https://grafana.com/api/dashboards/25086/revisions/1/download > provisioning/dashboards_json/dashboard.json

# 6. Generate a unified docker-compose.yml with Proxy Enabled
echo "Generating unified docker-compose.yml..."
cat << EOF > docker-compose.yml
services:
  ollama-exporter:
    image: ghcr.io/maravexa/ollama-exporter:latest
    container_name: ollama-exporter
    restart: unless-stopped
    ports:
      - "9400:9400"
      - "9401:9401" # Exposing the proxy port
    environment:
      - OLLAMA_URL=http://host.docker.internal:11434
      - LISTEN_ADDR=:9400
      - PROXY_ENABLED=true
      - GPU_ENABLED=false
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - ollama_metrics_net

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    networks:
      - ollama_metrics_net

  grafana:
    image: grafana/grafana-oss:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - ./provisioning/datasources:/etc/grafana/provisioning/datasources:ro
      - ./provisioning/dashboards:/etc/grafana/provisioning/dashboards:ro
      - ./provisioning/dashboards_json:/var/lib/grafana/dashboards:ro
      - grafana_data:/var/lib/grafana
    networks:
      - ollama_metrics_net

volumes:
  prometheus_data:
  grafana_data:

networks:
  ollama_metrics_net:
    driver: bridge
EOF

# 7. Start the stack with force-recreate to apply changes
echo "Starting the metrics stack..."
if docker compose version >/dev/null 2>&1; then
    docker compose down
    docker compose up -d --force-recreate
else
    docker-compose down
    docker-compose up -d --force-recreate
fi

echo "Deployment complete. Dashboards available on port 3000."
