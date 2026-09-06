#!/bin/bash
set -eo pipefail

# Configuration: defaults can be overridden via environment variables
# e.g.: OLLAMA_USER=myuser OLLAMA_GROUP=mygroup ./update_ollama_native.sh
OLLAMA_USER="${OLLAMA_USER:-ollama}"
OLLAMA_GROUP="${OLLAMA_GROUP:-ollama}"

# Default model: lowercase tag is mandatory
MODEL_NAME="${1:-qwen3.8:27b}"

# Service paths
SERVICE_NAME="ollama"
SERVICE_DIR="/etc/systemd/system/ollama.service.d"
SERVICE_FILE="${SERVICE_DIR}/override.conf"
LOG_DIR="/var/log/ollama"
MODELS_DIR="/mnt/nvme/ollama_models"

echo "=== 1. Installing / Updating Ollama Native ==="
curl -fsSL https://ollama.com/install.sh | sh
rm -f install.sh

echo "=== 2. Setting Up User, Group, and Permissions ==="
# Ensure target group exists
if ! getent group "$OLLAMA_GROUP" >/dev/null 2>&1; then
    echo "Creating group: $OLLAMA_GROUP"
    groupadd -r "$OLLAMA_GROUP"
fi

# Ensure target user exists
if ! id -u "$OLLAMA_USER" >/dev/null 2>&1; then
    echo "Creating service user: $OLLAMA_USER"
    useradd -r -s /bin/false -g "$OLLAMA_GROUP" -m -d /usr/share/ollama "$OLLAMA_USER"
fi

# Attach user to JetPack GPU access groups if not running as root
if [ "$OLLAMA_USER" != "root" ]; then
    usermod -aG video,render "$OLLAMA_USER" || true
fi

# Ensure device node access
chmod 666 /dev/dri/card* /dev/dri/renderD* /dev/nvhost* /dev/nvmap 2>/dev/null || true

# Prepare directories and assign ownership
mkdir -p "$LOG_DIR" "$MODELS_DIR" "$SERVICE_DIR"
chown -R "${OLLAMA_USER}:${OLLAMA_GROUP}" "$LOG_DIR"
chown -R "${OLLAMA_USER}:${OLLAMA_GROUP}" "$MODELS_DIR"

# Backup existing service override if it exists
if [ -f "$SERVICE_FILE" ]; then
    cp "$SERVICE_FILE" "${SERVICE_FILE}.bak"
fi

echo "=== 3. Writing Systemd Override Configuration ==="
cat <<EOF | tee "$SERVICE_FILE" > /dev/null
[Service]
ExecStart=
ExecStart=/usr/local/bin/ollama serve
User=${OLLAMA_USER}
Group=${OLLAMA_GROUP}
SupplementaryGroups=video render
Restart=always
RestartSec=10

# Hardware & Storage
Environment="OLLAMA_MODELS=${MODELS_DIR}"
Environment="OLLAMA_LLM_LIBRARY=cuda_jetpack6"
Environment="OLLAMA_DEBUG=1"
Environment="OLLAMA_HOST=0.0.0.0:11434"

# Memory & KV Cache Tuning for AGX Orin 64GB
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
Environment="OLLAMA_CONTEXT_LENGTH=32768"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_KEEP_ALIVE=-1"
Environment="OLLAMA_LOAD_TIMEOUT=3600"
Environment="OLLAMA_MAX_QUEUE=64"

# Logging
StandardOutput=append:${LOG_DIR}/ollama.log
StandardError=append:${LOG_DIR}/ollama.log
EOF

echo "=== 4. Reloading and Restarting Ollama ==="
systemctl daemon-reload
systemctl restart ollama

echo "Waiting for Ollama API endpoint to become responsive..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:11434/api/tags >/dev/null; then
        echo "Ollama is live!"
        break
    fi
    sleep 1
    if [ "$i" -eq 30 ]; then
        echo "Error: Timed out waiting for Ollama service. Check ${LOG_DIR}/ollama.log"
        exit 1
    fi
done

echo "=== 5. Model Verification & Pull ==="
if ollama list | awk '{print $1}' | grep -Fxq "$MODEL_NAME"; then
    echo "✔️ Model '$MODEL_NAME' is already present. Skipping pull."
else
    echo "⬇️ Model '$MODEL_NAME' not found in local library. Pulling..."
    ollama pull "$MODEL_NAME"
fi

echo "=== Setup Completed Successfully ==="
