#!/bin/bash
REPO_URL="https://github.com/NorskHelsenett/ollama-metrics.git"
TARGET_DIR="ollama-metrics"
COMPOSE_DIR="$TARGET_DIR/prometheus"
if [ ! -d "$TARGET_DIR" ]; then
echo "Directory '$TARGET_DIR' not found. Cloning repository..."
git clone "$REPO_URL"
echo "Starting Grafana/Prometheus stack..."
cd "$COMPOSE_DIR" || exit 1
docker compose up -d
else
echo "Directory '$TARGET_DIR' exists. Tearing down containers..."
cd "$COMPOSE_DIR" || exit 1
docker compose down
echo "Pulling latest repository updates..."
cd ..
git pull
echo "Bringing containers back up..."
cd prometheus || exit 1
docker compose up -d
fi
echo "Update complete. Grafana is running."