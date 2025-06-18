FROM alpine:latest

# Install necessary tools for ss command and bash
RUN apk add --no-cache iproute2 procps bash curl

# Create the directory for node_exporter's textfile collector
# This will be mounted from the host, but useful to have in image for clarity
RUN mkdir -p /var/lib/node_exporter/textfile_collector

# Copy the custom script
COPY external_ip_metrics.sh /usr/local/bin/external_ip_metrics.sh
RUN chmod +x /usr/local/bin/external_ip_metrics.sh

# Run the script in a loop to periodically update metrics
CMD while true; do /usr/local/bin/external_ip_metrics.sh; sleep 60; done