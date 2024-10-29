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
