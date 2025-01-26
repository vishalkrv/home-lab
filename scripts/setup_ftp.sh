#!/bin/bash

# Make sure the following package is installed
# sudo apt update -y
# sudo apt install -y vsftpd

# Define functions for enabling and disabling FTP
enable_ftp() {
    echo "Enabling FTP server..."

    # Configure vsftpd for basic FTP functionality
    echo "Configuring vsftpd..."
    sudo bash -c 'cat > /etc/vsftpd.conf' <<EOL
# Basic vsftpd Configuration
listen=YES
local_enable=YES
write_enable=YES
chroot_local_user=NO
allow_writeable_chroot=YES
file_open_mode=0755
pasv_enable=YES
pasv_min_port=10000
pasv_max_port=10100
EOL

    # Restart vsftpd service
    echo "Restarting vsftpd service..."
    sudo systemctl restart vsftpd

    # Ensure vsftpd starts on boot
    echo "Enabling vsftpd service to start on boot..."
    sudo systemctl enable vsftpd

    echo "FTP server is enabled and running."
}

disable_ftp() {
    echo "Disabling FTP server..."

    # Stop vsftpd service
    echo "Stopping vsftpd service..."
    sudo systemctl stop vsftpd

    # Disable vsftpd service from starting on boot
    echo "Disabling vsftpd service on boot..."
    sudo systemctl disable vsftpd

    echo "FTP server is disabled."
}

# Main menu
echo "Manage FTP Server"
echo "1. Enable FTP"
echo "2. Disable FTP"
read -p "Enter your choice (1 or 2): " choice

if [[ "$choice" == "1" ]]; then
    enable_ftp
elif [[ "$choice" == "2" ]]; then
    disable_ftp
else
    echo "Invalid choice. Exiting."
    exit 1
fi