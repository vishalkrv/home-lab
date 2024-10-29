# Creating a socat service

#### Filepath: /usr/local/bin/socat_service.sh 

```bash
#!/bin/bash

# Start the first socat command in the background
/usr/bin/socat TCP-LISTEN:2283,fork,reuseaddr TCP:in-oc-24:2283 &
PID1=$!

# Start the second socat command in the background
/usr/bin/socat TCP-LISTEN:4040,fork,reuseaddr TCP:in-pi-bkp:5001 &
PID2=$!

# Wait for any process to exit
wait -n

# If one process exits, kill the other
kill $PID1 $PID2
```

#### Save it and make it executable

```bash
sudo chmod +x /usr/local/bin/socat_service.sh
```

#### Create the systemd service file. Save this in /etc/systemd/system/socat.service.

```ini
[Unit]
Description=Socat TCP Forwarding Service
After=network.target

[Service]
Type=exec
ExecStart=/usr/local/bin/socat_service.sh
Restart=on-failure
RestartSec=5
StandardOutput=append:/var/log/socat.log
StandardError=append:/var/log/socat.log

[Install]
WantedBy=multi-user.target
```

#### Create log file

```bash
sudo touch /var/log/socat.log
sudo chown nobody:nogroup /var/log/socat.log  # Adjust if the service runs under a different user
sudo chmod 644 /var/log/socat.log
```

#### Configure Log Rotation
Create a log rotation configuration for socat.log in /etc/logrotate.d/socat:

```ini
/var/log/socat.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 nobody nogroup
    postrotate
        systemctl restart socat.service > /dev/null 2>/dev/null || true
    endscript
}
```

#### Enable and Start the Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable socat.service
sudo systemctl start socat.service
```

#### Check the status of the service
```bash
sudo systemctl status socat.service
```

### Check the logs
```bash
tail -f /var/log/socat.log
```