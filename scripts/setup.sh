#!/bin/bash
#
# Docker Filesystem Benchmark - Setup Script
# This script installs dependencies and sets up the monitoring environment

set -e

echo "=== Docker Filesystem Benchmark Setup ==="
echo "Installing dependencies and setting up environments..."

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires root privileges to install packages and configure filesystems."
    echo "Please run with sudo or as root."
    exit 1
fi

# Detect OS
OS="$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')"
echo "Detected OS: $OS"

# Install package dependencies
echo "Installing required packages..."
if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
    apt-get update
    apt-get install -y \
        docker.io \
        docker-compose \
        python3 \
        python3-pip \
        fio \
        bonnie++ \
        util-linux \
        e2fsprogs \
        xfsprogs \
        btrfs-progs \
        zfsutils-linux \
        sysstat \
        jq \
        git
elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ] || [ "$OS" == "fedora" ]; then
    yum install -y epel-release
    yum install -y \
        docker \
        docker-compose \
        python3 \
        python3-pip \
        fio \
        bonnie++ \
        util-linux \
        e2fsprogs \
        xfsprogs \
        btrfs-progs \
        zfs \
        sysstat \
        jq \
        git
else
    echo "Unsupported OS: $OS"
    echo "Please install the required packages manually:"
    echo "- Docker and Docker Compose"
    echo "- Python 3 and pip"
    echo "- Filesystem utilities (e2fsprogs, xfsprogs, btrfs-progs, zfsutils)"
    echo "- Benchmark tools (fio, bonnie++)"
    echo "- System monitoring (sysstat)"
fi

# Install Python dependencies
echo "Installing Python dependencies..."
pip3 install \
    prometheus-client \
    pandas \
    matplotlib \
    seaborn \
    numpy \
    scipy

# Create default config file
echo "Creating default configuration..."
mkdir -p config
cat > config/devices.conf << 'EOF'
# Define devices to test
# Format: device_path,device_type,device_name

# HDDs
/dev/sda,hdd,hdd1
/dev/sdb,hdd,hdd2

# SSDs 
/dev/sde,ssd,ssd1
/dev/sdf,ssd,ssd2

# NVMe
/dev/nvme0n1,nvme,nvme1
/dev/nvme1n1,nvme,nvme2

# Set this to your system disk to avoid testing it
SYSTEM_DISK=/dev/sdc
EOF

# Pull Docker images
echo "Pulling necessary Docker images..."
docker pull prom/prometheus:latest
docker pull grafana/grafana:latest
docker pull python:3.9-slim
docker pull tensorflow/tensorflow:latest-gpu

# Setup monitoring
echo "Setting up Prometheus configuration..."
cat > config/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
  - job_name: 'docker'
    static_configs:
      - targets: ['localhost:9323']
  - job_name: 'benchmark'
    static_configs:
      - targets: ['localhost:9090']
EOF

# Setup Grafana dashboard
echo "Setting up Grafana configuration..."
cat > config/grafana/datasources.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOF

# Create docker-compose.yml for monitoring
echo "Creating docker-compose for monitoring stack..."
cat > docker/docker-compose.yml << 'EOF'
version: '3'

services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ../config/prometheus:/etc/prometheus
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    ports:
      - "9090:9090"
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    volumes:
      - ../config/grafana:/etc/grafana/provisioning/datasources
      - grafana_data:/var/lib/grafana
    ports:
      - "3000:3000"
    depends_on:
      - prometheus
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:latest
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)'
    ports:
      - "9100:9100"
    restart: unless-stopped

volumes:
  prometheus_data:
  grafana_data:
EOF

# Create Dockerfile for benchmark container
echo "Creating Dockerfile for benchmark container..."
mkdir -p docker/benchmark
cat > docker/benchmark/Dockerfile << 'EOF'
FROM python:3.9-slim

# Install system tools
RUN apt-get update && apt-get install -y \
    fio \
    bonnie++ \
    iproute2 \
    procps \
    sysstat \
    util-linux \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip install --no-cache-dir \
    numpy \
    pandas \
    prometheus-client \
    psutil \
    matplotlib \
    seaborn

# Create benchmark directory
WORKDIR /benchmark

# Copy benchmark scripts
COPY . /benchmark/

# Set execute permissions
RUN chmod +x /benchmark/*.sh

ENTRYPOINT ["/benchmark/run.sh"]
EOF

# Create benchmark runner script
cat > docker/benchmark/run.sh << 'EOF'
#!/bin/bash
# Main benchmark runner script

echo "Running Docker Filesystem Benchmark Suite"
echo "Target directory: ${TARGET_DIR:-/data}"

# Run IO benchmarks
if [ "${BENCHMARK_TYPE}" = "io" ] || [ "${BENCHMARK_TYPE}" = "all" ]; then
    echo "Running I/O benchmarks..."
    /benchmark/io_benchmark.sh
fi

# Run Docker benchmarks
if [ "${BENCHMARK_TYPE}" = "docker" ] || [ "${BENCHMARK_TYPE}" = "all" ]; then
    echo "Running Docker benchmarks..."
    /benchmark/docker_benchmark.sh
fi

# Run ML benchmarks
if [ "${BENCHMARK_TYPE}" = "ml" ] || [ "${BENCHMARK_TYPE}" = "all" ]; then
    echo "Running ML benchmarks..."
    /benchmark/ml_benchmark.sh
fi

echo "Benchmark complete."
EOF

# Create IO benchmark script
cat > docker/benchmark/io_benchmark.sh << 'EOF'
#!/bin/bash
# I/O benchmarks using fio and bonnie++

TARGET_DIR=${TARGET_DIR:-/data}
OUTPUT_DIR=${OUTPUT_DIR:-/data/results}

mkdir -p "${OUTPUT_DIR}"

echo "Running I/O benchmarks on ${TARGET_DIR}"

# Run fio for sequential read/write tests
fio --directory="${TARGET_DIR}" \
    --name=seqread \
    --rw=read \
    --bs=1m \
    --direct=1 \
    --size=1G \
    --numjobs=4 \
    --group_reporting \
    --output="${OUTPUT_DIR}/fio_seqread.txt"

fio --directory="${TARGET_DIR}" \
    --name=seqwrite \
    --rw=write \
    --bs=1m \
    --direct=1 \
    --size=1G \
    --numjobs=4 \
    --group_reporting \
    --output="${OUTPUT_DIR}/fio_seqwrite.txt"

# Run fio for random read/write tests
fio --directory="${TARGET_DIR}" \
    --name=randread \
    --rw=randread \
    --bs=4k \
    --direct=1 \
    --size=1G \
    --numjobs=4 \
    --group_reporting \
    --output="${OUTPUT_DIR}/fio_randread.txt"

fio --directory="${TARGET_DIR}" \
    --name=randwrite \
    --rw=randwrite \
    --bs=4k \
    --direct=1 \
    --size=1G \
    --numjobs=4 \
    --group_reporting \
    --output="${OUTPUT_DIR}/fio_randwrite.txt"

# Run bonnie++ for file operations
bonnie++ -d "${TARGET_DIR}" -u root -n 0 -r 1024 -s 1024 -f -b -D > "${OUTPUT_DIR}/bonnie.txt"

echo "I/O benchmarks complete. Results saved to ${OUTPUT_DIR}"
EOF

# Create Docker benchmark script
cat > docker/benchmark/docker_benchmark.sh << 'EOF'
#!/bin/bash
# Docker operations benchmarks

TARGET_DIR=${TARGET_DIR:-/data}
OUTPUT_DIR=${OUTPUT_DIR:-/data/results}

mkdir -p "${OUTPUT_DIR}"

echo "Running Docker benchmarks on ${TARGET_DIR}"

# We're in a container, so we can't run Docker commands directly
# This script just simulates what would be done in the run_benchmarks.sh script
echo "Note: This is a simulation as Docker-in-Docker is not used."
echo "Docker pull time benchmark would go here"
echo "Docker build time benchmark would go here"
echo "Docker container start/stop benchmark would go here"

echo "Docker benchmarks complete. Results would be saved to ${OUTPUT_DIR}"
EOF

# Create ML benchmark script
cat > docker/benchmark/ml_benchmark.sh << 'EOF'
#!/bin/bash
# ML I/O benchmarks 

TARGET_DIR=${TARGET_DIR:-/data}
OUTPUT_DIR=${OUTPUT_DIR:-/data/results}

mkdir -p "${OUTPUT_DIR}"

echo "Running ML I/O benchmarks on ${TARGET_DIR}"
echo "This would run TensorFlow checkpoint save/load tests"
echo "This script would be implemented in Python in a real setup"

echo "ML benchmarks complete. Results would be saved to ${OUTPUT_DIR}"
EOF

# Enable Docker API for metrics
echo "Configuring Docker for metrics export..."
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"
if [ -f "$DOCKER_DAEMON_JSON" ]; then
    # Check if metrics are already enabled
    if grep -q "metrics-addr" "$DOCKER_DAEMON_JSON"; then
        echo "Docker metrics already configured"
    else
        # Add metrics to existing config
        TMP_FILE=$(mktemp)
        cat "$DOCKER_DAEMON_JSON" | jq '. + {"metrics-addr": "127.0.0.1:9323", "experimental": true}' > "$TMP_FILE"
        cat "$TMP_FILE" > "$DOCKER_DAEMON_JSON"
        rm "$TMP_FILE"
    fi
else
    # Create new config
    mkdir -p /etc/docker
    echo '{"metrics-addr": "127.0.0.1:9323", "experimental": true}' > "$DOCKER_DAEMON_JSON"
fi

# Restart Docker to apply changes
echo "Restarting Docker service to apply changes..."
systemctl restart docker || service docker restart || echo "Please restart Docker manually"

echo "=== Setup Complete! ==="
echo "You can now run benchmarks with ./scripts/run_benchmarks.sh" 