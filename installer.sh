#!/bin.bash
echo "Upgrading system"
sudo apt update
sudo apt upgrade -y
echo "Please reboot machine at the end"
# For absolutely no power limits (MAXN)
echo "Setting CPU clocks to uncapped. Warning: YOu must use an 90W 19V power supply, otherwise leave this uncommented"
sudo nvpmodel -m 0
sudo apt install nvidia-jetpack mc python3-pip  -y
echo "Installing JTOP"
sudo -H pip3 install -U jetson-stats --break-system-packages
sudo jtop --install-service
sudo systemctl restart jtop.service
echo "Installation completed. Rebooting machine"
#sudo reboot