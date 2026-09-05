#!/bin/bash

# Default to the 30B coder model unless specified otherwise
#MODEL_NAME=${1:-qwen3-coder:30b}
#MODEL_NAME=${1:-deepseek-r1:32b}
MODEL_NAME=${1:-qwen3.8:27B}
#MODEL_NAME=${1:-qwen2.5:0.5b}
# Configuration
SERVICE_NAME="ollama"
SERVICE_FILE="/etc/systemd/system/ollama.service.d/override.conf"
LOG_DIR="/var/log/ollama"


# 1. Download and run official installer
echo "Downloading and installing Ollama..."
#For now use the custom ollama build as in R39 Jetpack native ollama is broken
curl -fsSL https://ollama.com/install.sh | sh
rm -f install.sh

# 2. Configure Environment Variables
echo "Configuring environment variables in $SERVICE_FILE..."

sudo mkdir -p /etc/systemd/system/ollama.service.d

# Backup existing service file
sudo cp "$SERVICE_FILE" "${SERVICE_FILE}.bak"

# Use a temporary file to construct the new service configuration
cat <<EOF | sudo tee "$SERVICE_FILE" > /dev/null

[Service]
ExecStart=
ExecStart=/usr/local/bin/ollama serve
User=root
Group=root
SupplementaryGroups=video render
Restart=always
RestartSec=60
Environment="OLLAMA_DEBUG=1"
Environment="OLLAMA_LLM_LIBRARY=cuda_jetpack6"
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_NUM_GPU=99"
Environment="OLLAMA_LOAD_TIMEOUT=3600"
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
StandardOutput=append:$LOG_DIR/ollama.log
StandardError=append:$LOG_DIR/ollama.log
EOF

echo "--- Preparing Local Ollama Installation ---"
sudo mkdir -p "$LOG_DIR"
sudo chown ollama:ollama "$LOG_DIR"

# Ensure the ollama user has hardware access to the new JetPack nodes
if id -u ollama >/dev/null 2>&1; then
    sudo usermod -aG video,render ollama
    sudo chmod 666 /dev/dri/card* /dev/dri/renderD* /dev/nvhost* /dev/nvmap 2>/dev/null
fi


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
