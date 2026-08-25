#!/bin/bash

# Default to the 30B coder model unless specified otherwise
#MODEL_NAME=${1:-qwen3-coder:30b}
#MODEL_NAME=${1:-deepseek-r1:32b}
MODEL_NAME=${1:-qwen3.6:latest}

# Configuration
SERVICE_NAME="ollama"
SERVICE_FILE="/etc/systemd/system/ollama.service"
LOG_DIR="/var/log/ollama"

echo "--- Preparing Local Ollama Installation ---"
sudo mkdir -p "$LOG_DIR"
sudo chown ollama:ollama "$LOG_DIR"

# 1. Download and run official installer
echo "Downloading and installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh
rm -f install.sh

# 2. Configure Environment Variables
echo "Configuring environment variables in $SERVICE_FILE..."

# Backup existing service file
sudo cp "$SERVICE_FILE" "${SERVICE_FILE}.bak"

# Use a temporary file to construct the new service configuration
cat <<EOF | sudo tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=60
Environment="PATH=$PATH"
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_NUM_GPU=99"
Environment="OLLAMA_LOAD_TIMEOUT=180"
Environment="OLLAMA_GPU_LAYERS=-1"
Environment="OLLAMA_KEEP_ALIVE=-1"
Environment="OLLAMA_NUM_PARALLEL=3"
Environment="OLLAMA_NUM_PREDICT=8192"
Environment="OLLAMA_NUM_BATCH=2048"
Environment="OLLAMA_MAX_QUEUE=64"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
Environment="OLLAMA_CONTEXT_LENGTH=65536"


# OLLAMA_MAX_VRAM is commented out. 5368709120 bytes is only 5GB.
# This would force the 30B model onto the CPU. Let Ollama auto-detect the 64GB unified memory.
#Environment="OLLAMA_MAX_VRAM=5368709120"
StandardOutput=append:$LOG_DIR/ollama.log
StandardError=append:$LOG_DIR/ollama.log

[Install]
WantedBy=default.target
EOF

# 3. Reload and Restart
echo "Reloading systemd and restarting Ollama..."
sudo systemctl daemon-reload
sudo systemctl restart ollama

# 4. Model Management
echo "Waiting 10 seconds for Ollama service to start..."
sleep 10

echo "--- Model Check ---"
# Check if model is installed using the local CLI
if ollama list | grep -q "$(echo $MODEL_NAME | cut -d: -f1)"; then
    echo "✔️ Model $MODEL_NAME is already installed. Skipping pull."
else
    echo "⬇️ Model $MODEL_NAME not found. Pulling model..."
    ollama pull "$MODEL_NAME"
fi
