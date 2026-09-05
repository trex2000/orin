#!/bin/bash
set -eo pipefail

# ==========================================
# REPOSITORY CONFIGURATION
# ==========================================
REPO_URL="https://github.com/trex2000/orin.git"
REPO_DIR=$(basename -s .git "$REPO_URL")
INSTALL_DIR="/usr/local/bin"
SWAP_FILE="/swapfile"
SWAP_SIZE="64G"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
# ==========================================

# 1. Swap Configuration
if [ ! -f "$SWAP_FILE" ] && ! swapon --show | grep -q "$SWAP_FILE"; then
    echo "==> Creating a ${SWAP_SIZE} swap file at ${SWAP_FILE}..."
    sudo fallocate -l "$SWAP_SIZE" "$SWAP_FILE" || sudo dd if=/dev/zero of="$SWAP_FILE" bs=1G count=64 status=progress
    sudo chmod 600 "$SWAP_FILE"
    sudo mkswap "$SWAP_FILE"
    sudo swapon "$SWAP_FILE"
    
    if ! sudo grep -q "$SWAP_FILE" /etc/fstab; then
        echo "==> Adding swap file to /etc/fstab..."
        echo "$SWAP_FILE none swap sw 0 0" | sudo tee -a /etc/fstab
    fi
    echo "==> Swap successfully created, enabled, and registered."
else
    echo "==> Swap file already exists or is active. Skipping creation."
fi

# 2. System Updates & JetPack 6 Stack
echo ">>> Updating repository indexes..."
sudo apt update

PACKAGES_TO_INSTALL=""

# Core JetPack stack for CUDA, cuDNN, TensorRT
if ! dpkg -s nvidia-jetpack >/dev/null 2>&1; then
    PACKAGES_TO_INSTALL+=" nvidia-jetpack"
fi

if ! command -v mc >/dev/null 2>&1; then
    PACKAGES_TO_INSTALL+=" mc"
fi

if ! command -v pip3 >/dev/null 2>&1; then
    PACKAGES_TO_INSTALL+=" python3-pip"
fi

# Install required apt packages
if [ -n "$PACKAGES_TO_INSTALL" ]; then
    echo ">>> Installing required packages:$PACKAGES_TO_INSTALL"
    sudo DEBIAN_FRONTEND=noninteractive apt install -y $PACKAGES_TO_INSTALL
fi

# 3. Global CUDA Environment Paths
echo ">>> Configuring global CUDA environment paths..."
if [ ! -f /etc/profile.d/cuda.sh ]; then
    sudo tee /etc/profile.d/cuda.sh >/dev/null << 'EOF'
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
EOF
    sudo chmod +x /etc/profile.d/cuda.sh
    [ -f /usr/local/cuda/bin/nvcc ] && sudo ln -sf /usr/local/cuda/bin/nvcc /usr/local/bin/nvcc
    echo "CUDA environment profile created."
fi
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# 4. Jetson Stats (jtop)
echo ">>> Checking jtop (jetson-stats)..."
if ! command -v jtop >/dev/null 2>&1; then
    echo "Installing JTOP..."
    sudo -H pip3 install -U jetson-stats
    sudo jtop --install-service
    sudo systemctl restart jtop.service
else
    echo "jtop is already installed."
fi

# 5. Docker, Docker-Compose & NVIDIA Container Runtime
echo ">>> Checking Docker and docker-compose..."
if ! command -v docker >/dev/null 2>&1 || ! command -v docker-compose >/dev/null 2>&1; then
    echo "Installing Docker, docker-compose, and NVIDIA Container Toolkit..."
    sudo apt install -y docker.io docker-compose docker-compose-plugin nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$TARGET_USER"
    echo "Docker and docker-compose installed and configured for user $TARGET_USER."
else
    echo "Docker and docker-compose are already installed."
fi

# 6. XRDP with Native GNOME
echo ">>> Configuring XRDP for GNOME..."
if ! command -v xrdp >/dev/null 2>&1; then
    sudo apt install -y xrdp
    sudo usermod -a -G ssl-cert xrdp
    sudo ufw allow 3389/tcp >/dev/null 2>&1 || true
fi

# Fix /etc/xrdp/startwm.sh to launch GNOME under X11 without black screens
cat << 'EOF' | sudo tee /etc/xrdp/startwm.sh > /dev/null
#!/bin/sh
if [ -r /etc/default/locale ]; then
    . /etc/default/locale
    export LANG LANGUAGE
fi

unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
unset WAYLAND_DISPLAY
export XDG_SESSION_TYPE=x11
export GNOME_SHELL_SESSION_MODE=ubuntu
export DESKTOP_SESSION=ubuntu
export XDG_CURRENT_DESKTOP=ubuntu:GNOME

exec /usr/bin/gnome-session --session=ubuntu
EOF

sudo chmod +x /etc/xrdp/startwm.sh

# Remove XFCE overrides in the target home directory
sudo rm -f "$TARGET_HOME/.xsession" "$TARGET_HOME/.xsessionrc"
sudo systemctl restart xrdp xrdp-sesman
echo "XRDP configured to launch GNOME session."

# 7. Repository & Updater Sync
cd "$INSTALL_DIR"
sudo git config --global --add safe.directory "$INSTALL_DIR/orin"

echo ">>> Syncing repository: $REPO_URL"
if [ -d "$REPO_DIR/.git" ]; then
    echo "Repository exists. Updating..."
    cd "$REPO_DIR"
    sudo chown -R "$TARGET_USER:$TARGET_USER" "$INSTALL_DIR/$REPO_DIR"
    git fetch --all
    CURRENT_BRANCH=$(git branch --show-current || echo "main")
    git reset --hard "origin/$CURRENT_BRANCH"
    git clean -fd
    cd ..
else
    echo "Cloning repository..."
    sudo git clone "$REPO_URL"
    sudo chown -R "$TARGET_USER:$TARGET_USER" "$INSTALL_DIR/$REPO_DIR"
fi

cd "$REPO_DIR"

if [ -d "Updater" ]; then
    echo ">>> Syncing Updater folder to $INSTALL_DIR..."
    sudo cp -ru "Updater" "$INSTALL_DIR/"
fi

# 8. Scheduled Cron Job
echo ">>> Configuring root cron job..."
CRON_CMD="$INSTALL_DIR/Updater/runUpdates.sh"
CRON_SCHEDULE="0 3 * * 6"
CRON_JOB="$CRON_SCHEDULE $CRON_CMD"

if sudo crontab -l 2>/dev/null | grep -F -q "$CRON_CMD"; then
    echo "Cron job for runUpdates.sh already exists. Skipping."
else
    echo "Registering weekly cron job..."
    (sudo crontab -l 2>/dev/null || true; echo "$CRON_JOB") | sudo crontab -
fi

sudo find "$INSTALL_DIR" -type f -name "*.sh" -exec sudo chmod +x {} +

#set clocks to max
sudo nvpmodel -m 0

echo ">>> Setup completed successfully. Please reboot to finalize display and group permissions."
