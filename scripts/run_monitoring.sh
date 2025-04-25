#!/bin/bash
#
# Docker Filesystem Benchmark - Simple Monitoring Script
# This script provides a simpler alternative to the full monitoring stack

set -e

echo "=== Docker Filesystem Benchmark - Simple Monitoring ==="

# Function to check if a container is running
container_running() {
    local container_name=$1
    if docker ps --format '{{.Names}}' | grep -q "^$container_name$"; then
        return 0  # Container is running
    else
        return 1  # Container is not running
    fi
}

# Function to check if docker-compose is available
docker_compose_available() {
    if command -v docker-compose &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Start the monitoring using docker-compose
start_compose_monitoring() {
    echo "Starting monitoring stack with docker-compose..."
    
    # Navigate to the docker directory
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local docker_dir="$(dirname "$script_dir")/docker"
    
    cd "$docker_dir"
    
    # Try to start with docker-compose
    if docker-compose up -d; then
        echo "Docker Compose monitoring stack started successfully."
        return 0
    else
        echo "Warning: Failed to start with docker-compose. Trying cleanup..."
        docker-compose down 2>/dev/null || true
        
        # Try one more time after cleanup
        if docker-compose up -d; then
            echo "Docker Compose monitoring stack started after cleanup."
            return 0
        else
            echo "Error: Still failed to start with docker-compose."
            return 1
        fi
    fi
}

# Start the monitoring container
start_monitoring() {
    echo "Starting node-exporter container..."
    
    # Check if container already exists
    if container_running "fs-benchmark-node-exporter"; then
        echo "Node exporter is already running."
        return 0
    fi
    
    # First try using docker-compose if available
    if docker_compose_available; then
        if start_compose_monitoring; then
            return 0
        else
            echo "Falling back to direct container method..."
        fi
    fi
    
    # Fallback: Run node-exporter container directly (no compose needed)
    docker run -d --rm \
        --name fs-benchmark-node-exporter \
        --net=host \
        --pid=host \
        -v /proc:/host/proc:ro \
        -v /sys:/host/sys:ro \
        -v /:/rootfs:ro \
        prom/node-exporter:latest \
        --path.procfs=/host/proc \
        --path.sysfs=/host/sys \
        --collector.filesystem.ignored-mount-points='^/(sys|proc|dev|host|etc)($$|/)' \
        --web.listen-address=127.0.0.1:9100
    
    echo "Node exporter started. Metrics available at http://localhost:9100/metrics"
}

# Stop the monitoring container
stop_monitoring() {
    echo "Stopping monitoring containers..."
    
    # First try to stop with docker-compose if available
    if docker_compose_available; then
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local docker_dir="$(dirname "$script_dir")/docker"
        
        cd "$docker_dir"
        if docker-compose down; then
            echo "Docker Compose monitoring stack stopped."
            return 0
        else
            echo "Warning: Failed to stop with docker-compose, trying direct container method..."
        fi
    fi
    
    # Fallback: Stop the node-exporter container directly
    if container_running "fs-benchmark-node-exporter"; then
        docker stop fs-benchmark-node-exporter
        echo "Node exporter stopped."
    else
        echo "Node exporter is not running."
    fi
    
    # Clean up any other potential containers
    for container in "docker_prometheus_1" "docker_grafana_1" "docker_node-exporter_1"; do
        if docker ps -a --format '{{.Names}}' | grep -q "$container"; then
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
        fi
    done
}

# Display usage
usage() {
    echo "Usage: $0 [command]"
    echo "Commands:"
    echo "  start    Start the monitoring container"
    echo "  stop     Stop the monitoring container"
    echo "  status   Check if monitoring is running"
    echo "  help     Display this message"
    echo ""
    echo "Example: $0 start"
}

# Check status of monitoring
status_monitoring() {
    local running=false
    
    # Check docker-compose containers
    for container in "docker_prometheus_1" "docker_grafana_1" "docker_node-exporter_1"; do
        if docker ps --format '{{.Names}}' | grep -q "$container"; then
            echo "$container is running."
            running=true
        fi
    done
    
    # Check direct container
    if container_running "fs-benchmark-node-exporter"; then
        echo "Node exporter is running."
        echo "Metrics available at http://localhost:9100/metrics"
        running=true
    fi
    
    if [ "$running" = false ]; then
        echo "No monitoring containers are running."
    fi
}

# Parse command line arguments
COMMAND=${1:-help}

case $COMMAND in
    start)
        start_monitoring
        ;;
    stop)
        stop_monitoring
        ;;
    status)
        status_monitoring
        ;;
    help)
        usage
        ;;
    *)
        echo "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac 