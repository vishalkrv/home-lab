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

# Mount a exteral drive permanently

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
