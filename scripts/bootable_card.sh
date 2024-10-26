#!/bin/bash

#
# Create a Bootable SDCard using a Debian Based OS 
#

# Variables (Update these with your information)
IMAGE_PATH="/mnt/passport/2024-07-04-raspios-bookworm-arm64-lite.img" # Image path that need to be setup
SD_CARD="/dev/mmcblk0" # SD Card path which can be seeing using lsblk
SSID="xxxxx" # WiFi network to connect once setup is completed
PASSWORD="xxxxxx" # WiFi password to connect once setup is completed
COUNTRY_CODE="IN"  # Use your two-letter country code
USERNAME="xxxxx"     # Choose a OS username
USER_PASSWORD="xxxxx" # Choose a strong password

# Confirm SD card device
echo "WARNING: This will erase all data on $SD_CARD."
read -p "Are you sure you want to proceed? Type 'yes' to continue: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Operation cancelled."
    exit 1
fi

# Unmount any mounted partitions
echo "Unmounting any mounted partitions on $SD_CARD..."
sudo umount ${SD_CARD}* || true

# Write the image to the SD card
echo "Writing the image to the SD card..."
sudo dd if="$IMAGE_PATH" of="$SD_CARD" bs=4M status=progress conv=fsync

# Sync to ensure all data is written
echo "Syncing data to disk..."
sudo sync

# Wait for the partitions to be recognized
echo "Waiting for the SD card to be recognized..."
sleep 5

# Mount the boot partition
BOOT_PART="${SD_CARD}p1"
MOUNT_POINT="/mnt/raspiboot"
echo "Mounting the boot partition..."
sudo mkdir -p "$MOUNT_POINT"
sudo mount "$BOOT_PART" "$MOUNT_POINT"

# Enable SSH
echo "Enabling SSH..."
sudo touch "$MOUNT_POINT/ssh"

# Configure Wi-Fi
echo "Configuring Wi-Fi..."
sudo tee "$MOUNT_POINT/wpa_supplicant.conf" > /dev/null << EOF
country=$COUNTRY_CODE
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="$SSID"
    psk="$PASSWORD"
    key_mgmt=WPA-PSK
}
EOF

# Create userconf file
echo "Creating user configuration..."
PASSWORD_HASH=$(echo "$USER_PASSWORD" | openssl passwd -6 -stdin)
sudo tee "$MOUNT_POINT/userconf" > /dev/null << EOF
$USERNAME:$PASSWORD_HASH
EOF

# Unmount the boot partition
echo "Unmounting the boot partition..."
sudo umount "$MOUNT_POINT"

# Clean up
echo "Cleaning up..."
sudo rmdir "$MOUNT_POINT"

# Final sync
echo "Final sync..."
sudo sync

echo "SD card is ready. You can now insert it into your Raspberry Pi."