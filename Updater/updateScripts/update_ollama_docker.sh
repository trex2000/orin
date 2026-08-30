#!/bin/bash

# Configuration Variables
MODEL_NAME=${1:-qwen2.5:0.5b}
CONFIG_USER=${2:-ollama}
CONFIG_GROUP=${3:-ollama}
HOST_LOG_DIR=${4:-/var/log/ollama}
BUILD_IMAGE=${5:-false}

CONTAINER_NAME="ollama"
HOST_MODELS_DIR="/usr/share/ollama/.ollama"
JETSON_CONTAINERS_DIR="/usr/local/bin/jetson-containers"

# Bypass Ubuntu 24.04 PEP 668 externally-managed-environment restriction
export PIP_BREAK_SYSTEM_PACKAGES=1

echo "--- Disabling Unsupported Native Ollama Service ---"
sudo systemctl stop ollama 2>/dev/null
sudo systemctl disable ollama 2>/dev/null

if [ "$BUILD_IMAGE" = "true" ]; then
    echo "--- Setting up jetson-containers ---"
    if [ ! -d "$JETSON_CONTAINERS_DIR" ]; then
        echo "Cloning jetson-containers repository..."
        sudo git clone https://github.com/dusty-nv/jetson-containers "$JETSON_CONTAINERS_DIR"
    fi

    cd "$JETSON_CONTAINERS_DIR" || exit 1

    echo "--- Applying PyPI Fallback Patches for JetPack 7 ---"
    sudo sed -i '/set -ex/a export UV_EXTRA_INDEX_URL=https://pypi.org/simple\nexport PIP_EXTRA_INDEX_URL=https://pypi.org/simple' packages/build/cmake/cmake_pip/install.sh
    sudo sed -i '/set -ex/a export UV_EXTRA_INDEX_URL=https://pypi.org/simple\nexport PIP_EXTRA_INDEX_URL=https://pypi.org/simple' packages/ml/numeric/numpy/install.sh
    sudo sed -i '/RUN set -ex \\/a \    && export UV_EXTRA_INDEX_URL=https://pypi.org/simple \\\n    && export PIP_EXTRA_INDEX_URL=https://pypi.org/simple \\' packages/llm/huggingface_hub/Dockerfile
    sudo sed -i '/RUN git clone.*sudonim/a \    export UV_EXTRA_INDEX_URL=https://pypi.org/simple && \\\n    export PIP_EXTRA_INDEX_URL=https://pypi.org/simple && \\' packages/llm/sudonim/Dockerfile
    sudo sed -i '/uv pip install --no-cache-dir ollama/i export UV_EXTRA_INDEX_URL=https://pypi.org/simple\nexport PIP_EXTRA_INDEX_URL=https://pypi.org/simple' packages/llm/ollama/docker_files/tmp/OLLAMA/build.sh
    sudo sed -i '/uv pip install ollama/i export UV_EXTRA_INDEX_URL=https://pypi.org/simple\nexport PIP_EXTRA_INDEX_URL=https://pypi.org/simple' packages/llm/ollama/docker_files/tmp/OLLAMA/install.sh

    echo "--- Building GPU-Accelerated Ollama Container ---"
    pip3 install -r requirements.txt || true

    if ! sudo -E python3 -m jetson_containers.build ollama; then
        echo "❌ Build failed. Please check the logs above."
        exit 1
    fi
else
    echo "--- Skipping Container Build Process ---"
    if [ ! -d "$JETSON_CONTAINERS_DIR" ]; then
        echo "❌ jetson-containers directory not found at $JETSON_CONTAINERS_DIR."
        echo "Cannot determine autotag. Please run the script with BUILD_IMAGE=true first."
        exit 1
    fi
    cd "$JETSON_CONTAINERS_DIR" || exit 1
fi

# Get the exact local image tag expected/generated for this JetPack version
OLLAMA_IMAGE=$(./autotag ollama)

echo "--- Preparing NVIDIA-Optimized Dockerized Deployment ---"
echo "Using Compiled Docker Image: $OLLAMA_IMAGE"
echo "Requested User:Group: $CONFIG_USER:$CONFIG_GROUP"
echo "Host Models Directory: $HOST_MODELS_DIR"
echo "Host Log Directory: $HOST_LOG_DIR"

# Resolve numeric UID and GID, fallback to current user if CONFIG_USER is invalid
if id -u "$CONFIG_USER" >/dev/null 2>&1; then
    TARGET_UID=$(id -u "$CONFIG_USER")
    TARGET_GID=$(id -g "$CONFIG_GROUP" 2>/dev/null || id -g "$CONFIG_USER")
    TARGET_USER_ARG="$TARGET_UID:$TARGET_GID"
    TARGET_CHOWN="$CONFIG_USER:$CONFIG_GROUP"
else
    echo "⚠️ User '$CONFIG_USER' not found on system. Falling back to current user ($(whoami))."
    TARGET_UID=$(id -u)
    TARGET_GID=$(id -g)
    TARGET_USER_ARG="$TARGET_UID:$TARGET_GID"
    TARGET_CHOWN="$TARGET_UID:$TARGET_GID"
fi

# Apply correct ownership on host directories (Models and Logs)
sudo mkdir -p "$HOST_MODELS_DIR" "$HOST_LOG_DIR"
sudo chown -R "$TARGET_CHOWN" "$HOST_MODELS_DIR" "$HOST_LOG_DIR"

# Clean up existing container
echo "Stopping and removing existing container if present..."
docker rm -f "$CONTAINER_NAME" 2>/dev/null

# Run container mapping host directories directly to the container's expected paths
echo "Starting Ollama container..."
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --runtime nvidia \
    --ipc=host \
    --network host \
    --user "$TARGET_USER_ARG" \
    --group-add video \
    --group-add render \
    --log-driver json-file \
    --log-opt max-size=50m \
    --log-opt max-file=3 \
    -v "${HOST_MODELS_DIR}:/data/models/ollama/models" \
    -v "${HOST_LOG_DIR}:/data/logs" \
    -e OLLAMA_MODELS=/data/models/ollama/models \
    -e OLLAMA_DEBUG=2 \
    -e OLLAMA_HOST=0.0.0.0:11434 \
    -e OLLAMA_NUM_GPU=99 \
    -e OLLAMA_LOAD_TIMEOUT=180 \
    -e OLLAMA_GPU_LAYERS=-1 \
    -e OLLAMA_KEEP_ALIVE=-1 \
    -e OLLAMA_NUM_PARALLEL=3 \
    -e OLLAMA_NUM_PREDICT=8192 \
    -e OLLAMA_NUM_BATCH=2048 \
    -e OLLAMA_MAX_QUEUE=64 \
    -e OLLAMA_MAX_LOADED_MODELS=1 \
    -e OLLAMA_FLASH_ATTENTION=1 \
    -e OLLAMA_KV_CACHE_TYPE=q8_0 \
    -e OLLAMA_CONTEXT_LENGTH=65536 \
    "$OLLAMA_IMAGE" \
    /bin/sh -c "/start_ollama && tail -f /data/logs/ollama.log"

# Model Management
echo "Waiting 15 seconds for Ollama container to initialize..."
sleep 15

echo "--- Model Check ---"
if docker exec "$CONTAINER_NAME" ollama list | grep -q "$(echo "$MODEL_NAME" | cut -d: -f1)"; then
    echo "✔️ Model $MODEL_NAME is already installed. Skipping pull."
else
    echo "⬇️ Model $MODEL_NAME not found. Pulling model inside container..."
    docker exec -d "$CONTAINER_NAME" ollama pull "$MODEL_NAME"
    echo "Pull initiated in background. You can monitor progress with: docker logs -f $CONTAINER_NAME"
fi