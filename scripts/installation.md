# Install CasaOS
```bash
curl -fsSL https://get.casaos.io | sudo bash
```
# Install Tailscale
```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

# Install Portainer Agent
```bash
sudo docker run -d \
  -p 9001:9001 \
  --name portainer_agent \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/lib/docker/volumes:/var/lib/docker/volumes \
  -v /:/host \
  portainer/agent:2.21.1
  ```

# Mount a external drive permanently

```bash
lsblk
# Get Device UUID
sudo blkid
sudo nano /etc/fstab
# Enter the below line in fstab
UUID=abcd-1234   /mnt/passport   ext4   defaults   0   2

sudo mount -a
systemctl daemon-reload
# Final Check
df -h
```

# Change hostname of the system

```bash
hostnamectl set-hostname server1.example.com
```

# Setup NFS server

```bash
# Install the NFS server package
sudo apt install nfs-kernel-server
# Create a Directory to Share
sudo mkdir -p /srv/nfs/shared
# Edit the /etc/exports File
sudo nano /etc/exports
  /srv/nfs/shared 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
# Export the Shared Directory
sudo exportfs -ra
# Start and Enable the NFS Server
sudo systemctl start nfs-server
sudo systemctl enable nfs-server
# Verify the NFS Share
showmount -e

# Mount the NFS Share on a Client Machine
sudo mkdir -p /mnt/shared
sudo mount -t nfs <server-ip>:/srv/nfs/shared /mnt/shared

# Make the Mount Permanent (Optional)
sudo nano /etc/fstab 
  <server-ip>:/srv/nfs/shared /mnt/shared nfs defaults 0 0

df -h
```
