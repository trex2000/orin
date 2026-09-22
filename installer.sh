#!/bin/bash

# ==========================================
# COLOR CONFIGURATION
# ==========================================
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ==========================================
# REPOSITORY CONFIGURATION
# ==========================================
REPO_URL="https://github.com/trex2000/orin.git"
REPO_DIR=$(basename -s .git "$REPO_URL")
INSTALL_DIR="/usr/local/bin"
SWAP_FILE="/swapfile"
SWAP_SIZE="64G"
# ==========================================

if [ ! -f "$SWAP_FILE" ] && ! swapon --show | grep -q "$SWAP_FILE"; then
    echo "==> Creating a ${SWAP_SIZE} swap file at ${SWAP_FILE}..."
    sudo fallocate -l "$SWAP_SIZE" "$SWAP_FILE"
    sudo chmod 600 "$SWAP_FILE"
    sudo mkswap "$SWAP_FILE"
    sudo swapon "$SWAP_FILE"

    if ! sudo grep -q "$SWAP_FILE" /etc/fstab; then
        echo "==> Adding swap file to /etc/fstab..."
        echo "$SWAP_FILE none swap sw 0 0" | sudo tee -a /etc/fstab
    fi
    echo -e "${GREEN}==> 64GB swap successfully created, enabled, and registered.${NC}"
else
    echo "==> Swap file already exists or is active. Skipping creation."
fi

echo ">>> Checking for system upgrades..."
sudo apt update
# Perform a dry run to extract the exact number of pending upgrades
UPGRADES=$(apt-get -s upgrade | awk '/^[0-9]+ upgraded,/ {print $1}')

if [[ "$UPGRADES" =~ ^[1-9][0-9]*$ ]]; then
    echo "Found $UPGRADES package(s) to upgrade"
    echo -e -n "${BLUE}Would you like to perform update? [y/N]: ${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        sudo apt upgrade -y
        echo -e "${GREEN}✔ System update completed${NC}"
    else
        echo "Skipped system update"
    fi

else
    echo "System is already up-to-date. Skipping upgrade."
fi


echo ">>> Checking base system packages..."
PACKAGES_TO_INSTALL=""

# Check if nvidia-jetpack is installed
#if ! dpkg -s nvidia-jetpack >/dev/null 2>&1; then
    #PACKAGES_TO_INSTALL+=" nvidia-jetpack"
#fi

# Check if midnight commander is installed
if ! command -v mc >/dev/null 2>&1; then
    PACKAGES_TO_INSTALL+=" mc"
fi

# Check if python3-pip is installed
if ! command -v pip3 >/dev/null 2>&1; then
    PACKAGES_TO_INSTALL+=" python3-pip"
fi

# Check if xfce4 is installed
if ! command -v xfce4-session >/dev/null 2>&1; then
    PACKAGES_TO_INSTALL+=" xfce4 xfce4-goodies dbus-x11"
fi


echo ">>> Configuring global CUDA environment paths..."
if [ ! -f /etc/profile.d/cuda.sh ]; then
    #echo 'export PATH=/usr/local/cuda/bin:$PATH' | sudo tee /etc/profile.d/cuda.sh >/dev/null
    #echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' | sudo tee -a /etc/profile.d/cuda.sh >/dev/null
    #sudo ln -sf /usr/local/cuda/bin/nvcc /usr/local/bin/nvcc
    echo -e "${GREEN}CUDA environment profile created.${NC}"
else
    echo "CUDA environment profile already exists."
fi
# Source it for the current execution context
#export PATH=/usr/local/cuda/bin:$PATH
#export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH


# Install missing apt packages if any were found
if [ -n "$PACKAGES_TO_INSTALL" ]; then
    echo "Installing missing packages:$PACKAGES_TO_INSTALL"
    sudo apt update
    sudo apt install $PACKAGES_TO_INSTALL -y
else
    echo "Base system packages are already installed."
fi

echo ">>> Checking jtop (jetson-stats)..."
if ! command -v jtop >/dev/null 2>&1; then
    echo "Installing JTOP"
    sudo -H pip3 install -U jetson-stats --break-system-packages
    sudo jtop --install-service
    sudo systemctl restart jtop.service
else
    echo "jtop is already installed."
fi


echo ">>> Checking if Docker is installed..."
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker not found. Installing docker.io..."
    sudo apt install docker.io docker-compose-plugin -y
    sudo systemctl enable --now docker
    # $USER automatically grabs the user running the script (e.g., cgmures)
    sudo usermod -aG docker "$USER"
    echo -e "${GREEN}Docker installed and configured for user $USER.${NC}"
    echo "Note: Group changes may require a logout/login to fully take effect."
else
    echo "Docker is already installed."
fi

echo ">>> Checking if XRDP is installed..."
if ! command -v xrdp >/dev/null 2>&1; then
    echo "XRDP not found. Installing and configuring..."
    sudo apt install xrdp -y

    echo "Granting SSL Certificate Permissions..."
    sudo usermod -a -G ssl-cert xrdp

    echo "Applying GNOME black screen fix..."
    # Check if the fix is already there to avoid duplicate entries
    if ! grep -q "unset DBUS_SESSION_BUS_ADDRESS" /etc/xrdp/startwm.sh; then
        sudo sed -i '/^test -x \/etc\/X11\/Xsession/i unset DBUS_SESSION_BUS_ADDRESS\nunset XDG_RUNTIME_DIR' /etc/xrdp/startwm.sh
    fi

    sudo systemctl restart xrdp

    echo "Allowing RDP port 3389 through UFW firewall..."
    sudo ufw allow 3389/tcp >/dev/null 2>&1 || true
    echo -e "${GREEN}XRDP installation complete.${NC}"
else
    echo "XRDP is already installed."
fi

#getting current user
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(eval echo "~$TARGET_USER")

echo ">>> Configuring XRDP to use XFCE with DBUS for user $TARGET_USER..."
# Check if the correct dbus command is already present in the .xsession file
if ! sudo grep -q "exec dbus-run-session -- startxfce4" "$TARGET_HOME/.xsession" 2>/dev/null; then
    sudo rm -f "$TARGET_HOME/.xsession" "$TARGET_HOME/.xsessionrc"
    echo "exec dbus-run-session -- startxfce4" > "$TARGET_HOME/.xsession"
    sudo chmod +x "$TARGET_HOME/.xsession"
    sudo chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.xsession"
    sudo systemctl restart xrdp xrdp-sesman
    echo -e "${GREEN}.xsession configured for XFCE.${NC}"
else
    echo ".xsession is already correctly configured for XFCE. Skipping."
fi


cd $INSTALL_DIR
sudo git config --global --add safe.directory $INSTALL_DIR/orin
echo ">>> Syncing repository: $REPO_URL"
if [ -d "$REPO_DIR/.git" ]; then
    echo "Repository exists. Fetching updates and overwriting local modifications..."
    cd "$REPO_DIR" || exit 1
    sudo chown -R "$TARGET_USER:$TARGET_USER" /usr/local/bin/orin
    #git fetch --all
    #CURRENT_BRANCH=$(git branch --show-current)
    #sudo git reset --hard "origin/$CURRENT_BRANCH"
    #sudo git clean -fd
    # Return to previous directory so the rest of the script doesn't break
    cd ..
else
    echo "Repository not found locally. Cloning..."
    sudo git clone "$REPO_URL"
fi
cd "$REPO_DIR" || exit 1

if [ -d "Updater" ]; then
    echo ">>> Syncing Updater base files to $INSTALL_DIR..."
    sudo mkdir -p "$INSTALL_DIR/Updater/updatescripts"
    # Copy all files from Updater EXCEPT those in the updatescripts folder
    sudo find "Updater" -type f ! -path "*/updatescripts/*" ! -path "*/updateScripts/*" -exec cp --parents -u {} "$INSTALL_DIR/" \;

    echo ">>> Scanning for scripts in Updater/updatescripts to install..."
    shopt -s nocaseglob nullglob
    for script in Updater/updateScripts/*.sh; do
        script_name=$(basename "$script")
        echo -e -n "${BLUE}Do you want to copy and install '$script_name' to $INSTALL_DIR/Updater/updatescripts/? [y/N]: ${NC}"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            sudo cp "$script" "$INSTALL_DIR/Updater/updatescripts/"
            echo -e "${GREEN}✔ Installed $script_name${NC}"
        else
            echo "Skipped $script_name"
        fi
    done
    shopt -u nocaseglob nullglob
fi


echo ">>> Configuring root cron job..."
CRON_CMD="$INSTALL_DIR/Updater/runUpdates.sh"
CRON_SCHEDULE="0 3 * * 6"
CRON_JOB="$CRON_SCHEDULE $CRON_CMD"

# Check if the exact job already exists in root's crontab
if sudo crontab -l 2>/dev/null | grep -F -q "$CRON_CMD"; then
    echo "Cron job for runUpdates.sh already exists. Skipping."
else
    echo "Adding cron job to run every Saturday at 03:00 AM..."
    # Append the new cron job to the existing root crontab
    (sudo crontab -l 2>/dev/null; echo "$CRON_JOB") | sudo crontab -
fi


echo ">>> Making all .sh scripts executable inside $REPO_DIR..."
sudo find "$INSTALL_DIR" -type f -name "*.sh" -exec sudo chmod +x {} +

if [ -x "$INSTALL_DIR/Updater/runUpdates.sh" ]; then
    echo -e -n "${BLUE}Would you like to execute installed scripts for the first time... [y/N]: ${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Running Container updates"
        sudo "$INSTALL_DIR/Updater/runUpdates.sh"
    else
        echo "Skipped running newly installed scripts"
    fi
else
    echo -e "${RED}Error: $INSTALL_DIR/Updater/runUpdates.sh is not executable or not found.${NC}"
fi

# For absolutely no power limits (MAXN)
echo -e -n "${BLUE}Setting CPU clocks to uncapped. Warning: YOU must use an 90W 19V power supply, otherwise leave this unset [y/N]: ${NC}"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo nvpmodel -m 0
    echo -e "${GREEN}✔ Powermode was set${NC}"
else
    echo "Skipped setting powermode"
fi

echo -e "${GREEN}>>> Installation complete. Please reboot the system before use!${NC}"
