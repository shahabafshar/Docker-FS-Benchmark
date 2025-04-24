#!/bin/bash
#
# Docker Filesystem Benchmark - Docker Networking Fix Script
# This script helps diagnose and fix Docker networking issues

echo "=== Docker Filesystem Benchmark - Docker Fix Script ==="

# Check Docker version and capabilities
echo "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    echo "Error: Docker not found. Please install Docker first."
    exit 1
fi

echo "Docker version:"
docker --version

echo "Docker info:"
docker info | grep -E "Storage Driver|Logging Driver|Cgroup Driver|Network"

# Check if running in a containerized environment
echo -e "\nChecking if we're running in a container..."
if [ -f "/.dockerenv" ] || grep -q '/docker/' /proc/1/cgroup 2>/dev/null; then
    echo "WARNING: Detected Docker inside container/VM - this may cause networking issues"
    echo "Switching to host networking mode for containers"
    
    # Ensure the modified docker-compose is in place
    if grep -q "network_mode: \"host\"" docker/docker-compose.yml; then
        echo "Host networking already enabled in docker-compose.yml"
    else
        echo "Updating docker-compose.yml to use host networking..."
        sed -i 's/image: prom\/prometheus:latest/image: prom\/prometheus:latest\n    network_mode: "host"/' docker/docker-compose.yml
        sed -i 's/image: grafana\/grafana:latest/image: grafana\/grafana:latest\n    network_mode: "host"/' docker/docker-compose.yml
        sed -i 's/image: prom\/node-exporter:latest/image: prom\/node-exporter:latest\n    network_mode: "host"\n    pid: "host"/' docker/docker-compose.yml
        
        # Remove port mappings
        sed -i '/ports:/,+2d' docker/docker-compose.yml
        
        # Add listen address options
        sed -i '/--storage.tsdb.path=/a\      - '--web.listen-address=127.0.0.1:9090'' docker/docker-compose.yml
        sed -i '/grafana_data:/i\    environment:\n      - GF_SERVER_HTTP_ADDR=127.0.0.1\n      - GF_SERVER_HTTP_PORT=3000' docker/docker-compose.yml
        sed -i '/--collector.filesystem.ignored-mount-points=/a\      - '--web.listen-address=127.0.0.1:9100'' docker/docker-compose.yml
    fi
    
    # Update Grafana datasource
    if grep -q "localhost:9090" config/grafana/datasources.yml; then
        echo "Grafana already configured to use localhost"
    else
        echo "Updating Grafana datasource configuration..."
        sed -i 's/http:\/\/prometheus:9090/http:\/\/localhost:9090/' config/grafana/datasources.yml
    fi
else
    echo "Not running in a container environment, standard Docker networking should work."
fi

# Clean up any existing Docker resources from failed runs
echo -e "\nCleaning up existing Docker resources..."
docker-compose -f docker/docker-compose.yml down 2>/dev/null || true
docker network prune -f

# Set permissions on Docker socket if needed
if [ -e /var/run/docker.sock ]; then
    echo "Setting permissions on Docker socket..."
    chmod 666 /var/run/docker.sock 2>/dev/null || true
fi

echo -e "\n=== Docker Environment Setup Complete ==="
echo "Try running the benchmarks again with:"
echo "./scripts/run_benchmarks.sh --device=/dev/XXX --fs=ext4"
echo "Replace /dev/XXX with an actual storage device on your system"
echo -e "\nIf you continue having issues, try running just the IO benchmarks directly:"
echo "docker run --rm -v /path/to/test/device:/data -v \$PWD/results:/data/results -e BENCHMARK_TYPE=io docker-benchmark" 