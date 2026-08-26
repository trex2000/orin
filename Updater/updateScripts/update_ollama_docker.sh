#!/bin/bash

# Configuration Variables
MODEL_NAME=${1:-qwen3.6:latest}
DOCKER_REPO=${2:-ghcr.io/nvidia-ai-iot/ollama:r38.2.arm64-sbsa-cu130-24.04}
CONFIG_USER=${3:-root}
CONFIG_GROUP=${4:-root}

CONTAINER_NAME="ollama"
HOST_MODELS_DIR="/usr/share/ollama/.ollama"

echo "--- Preparing NVIDIA-Optimized Dockerized Ollama for Jetson Orin ---"
echo "Using Docker Image: $DOCKER_REPO"
echo "Requested User:Group: $CONFIG_USER:$CONFIG_GROUP"
echo "Reusing Models Directory: $HOST_MODELS_DIR"

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

# Apply correct ownership on host models directory
sudo mkdir -p "$HOST_MODELS_DIR"
sudo chown -R "$TARGET_CHOWN" "$HOST_MODELS_DIR"

# Pull image
echo "Pulling Docker image: $DOCKER_REPO..."
docker pull "$DOCKER_REPO"

# Clean up existing container
echo "Stopping and removing existing container if present..."
docker stop "$CONTAINER_NAME" 2>/dev/null
docker rm "$CONTAINER_NAME" 2>/dev/null

# Run container mapping host models directly to the container's expected path
echo "Starting Ollama container..."
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --runtime nvidia \
    --ipc=host \
    --network host \
    --user "$TARGET_USER_ARG" \
    --entrypoint /bin/ollama \
    --log-driver json-file \
    --log-opt max-size=50m \
    --log-opt max-file=3 \
    -v "${HOST_MODELS_DIR}:/data/models/ollama/models" \
    -e OLLAMA_MODELS=/data/models/ollama/models \
    -e OLLAMA_DEBUG=2 \
    -e OLLAMA_IGPU_ENABLE=1 \
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
    "$DOCKER_REPO" \
    serve

# Model Management
echo "Waiting 15 seconds for Ollama container to initialize..."
sleep 15

echo "--- Model Check ---"
if docker exec "$CONTAINER_NAME" ollama list | grep -q "$(echo $MODEL_NAME | cut -d: -f1)"; then
    echo "✔️ Model $MODEL_NAME is already installed. Skipping pull."
else
    echo "⬇️ Model $MODEL_NAME not found. Pulling model inside container..."
    docker exec -d "$CONTAINER_NAME" ollama pull "$MODEL_NAME"
    echo "Pull initiated in background."
fi