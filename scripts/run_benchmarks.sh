#!/bin/bash
#
# Docker Filesystem Benchmark - Main Runner Script
# This script runs benchmarks across all specified devices and filesystems

set -e

echo "=== Docker Filesystem Benchmark Suite ==="
echo "Starting benchmark run: $(date)"

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires root privileges to format devices and mount filesystems."
    echo "Please run with sudo or as root."
    exit 1
fi

# Directory paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$BASE_DIR/config"
RESULTS_DIR="$BASE_DIR/results"
DOCKER_DIR="$BASE_DIR/docker"

# Load configuration
CONFIG_FILE="$CONFIG_DIR/devices.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found."
    echo "Please run setup.sh first."
    exit 1
fi

# Source system disk to avoid formatting it
source "$CONFIG_FILE"

# Ensure docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "Error: docker-compose is not installed."
    echo "Please install docker-compose first."
    exit 1
fi

# Prepare directories
mkdir -p "$RESULTS_DIR/raw"
mkdir -p "$RESULTS_DIR/processed"

# List of filesystems to test
FILESYSTEMS=("ext4" "xfs" "btrfs" "zfs")

# Function to get device list from config
get_devices() {
    local device_type=$1
    grep "^/dev/.*,$device_type," "$CONFIG_FILE" | cut -d',' -f1
}

# Function to get device nice name from config
get_device_name() {
    local device=$1
    grep "^$device," "$CONFIG_FILE" | cut -d',' -f3
}

# Function to prepare results directory for a specific run
prepare_result_dir() {
    local device=$1
    local fs=$2
    local device_name=$(get_device_name "$device")
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # Create directory for this run
    local result_dir="$RESULTS_DIR/raw/${device_name}_${fs}_${timestamp}"
    mkdir -p "$result_dir"
    
    echo "$result_dir"
}

# Function to start monitoring stack
start_monitoring() {
    echo "Starting monitoring stack..."
    
    # Navigate to Docker directory
    pushd "$DOCKER_DIR" > /dev/null
    
    # Start the monitoring stack
    docker-compose up -d
    
    # Wait for services to start
    sleep 10
    
    popd > /dev/null
    
    echo "Monitoring stack started."
}

# Function to stop monitoring stack
stop_monitoring() {
    echo "Stopping monitoring stack..."
    
    # Navigate to Docker directory
    pushd "$DOCKER_DIR" > /dev/null
    
    # Stop the monitoring stack
    docker-compose down
    
    popd > /dev/null
    
    echo "Monitoring stack stopped."
}

# Function to run idle state baseline
run_idle_baseline() {
    echo "Running idle state baseline for 15 minutes..."
    
    # Start monitoring
    start_monitoring
    
    # Sleep for 15 minutes
    sleep 900
    
    # Stop monitoring
    stop_monitoring
    
    echo "Idle state baseline complete."
}

# Function to run benchmarks on a specific device and filesystem
run_benchmark() {
    local device=$1
    local fs=$2
    local result_dir=$3
    local mount_point="/mnt/testdisk"
    
    echo "=== Running benchmarks for $device with $fs ==="
    
    # Format and mount the device
    "$SCRIPT_DIR/format_devices.sh" --device="$device" --fs="$fs"
    
    # Start monitoring
    start_monitoring
    
    # Record filesystem info
    df -h "$mount_point" > "$result_dir/filesystem_info.txt"
    
    # Run I/O benchmarks
    echo "Running I/O benchmarks..."
    docker run --rm \
        -v "$mount_point:/data" \
        -v "$result_dir:/data/results" \
        -e BENCHMARK_TYPE=io \
        -e TARGET_DIR=/data \
        -e OUTPUT_DIR=/data/results \
        --name benchmark_io \
        docker-benchmark
    
    # Run Docker benchmarks
    echo "Running Docker benchmarks..."
    # For Docker benchmarks, we do them outside the container since we need Docker
    
    # 1. Pull time benchmark
    echo "Measuring Docker image pull time..."
    {
        time docker pull alpine:latest
    } 2>&1 | tee "$result_dir/docker_pull_time.txt"
    
    # 2. Build time benchmark
    echo "Measuring Docker image build time..."
    mkdir -p "$mount_point/docker_build_test"
    cat > "$mount_point/docker_build_test/Dockerfile" << 'EOF'
FROM alpine:latest
RUN apk add --no-cache python3 py3-pip
RUN pip install numpy pandas matplotlib
WORKDIR /app
COPY . /app
CMD ["echo", "Hello, World!"]
EOF
    
    {
        time docker build -t benchmark_test "$mount_point/docker_build_test/"
    } 2>&1 | tee "$result_dir/docker_build_time.txt"
    
    # 3. Container start/stop time
    echo "Measuring container start/stop time..."
    for i in {1..10}; do
        {
            time docker run --rm alpine:latest echo "Test $i"
        } 2>&1 | tee -a "$result_dir/docker_start_stop_time.txt"
    done
    
    # Run ML benchmarks (if needed)
    if command -v python3 &> /dev/null; then
        echo "Running ML I/O benchmarks..."
        docker run --rm \
            -v "$mount_point:/data" \
            -v "$result_dir:/data/results" \
            -e BENCHMARK_TYPE=ml \
            -e TARGET_DIR=/data \
            -e OUTPUT_DIR=/data/results \
            --name benchmark_ml \
            tensorflow/tensorflow:latest-gpu \
            python -c "
import tensorflow as tf
import time
import os

# Create a simple model
model = tf.keras.Sequential([
    tf.keras.layers.Dense(128, activation='relu', input_shape=(784,)),
    tf.keras.layers.Dense(10, activation='softmax')
])

model.compile(optimizer='adam', loss='sparse_categorical_crossentropy', metrics=['accuracy'])

# Generate dummy data
import numpy as np
x_train = np.random.random((1000, 784))
y_train = np.random.randint(10, size=(1000, 1))

# Measure save time
start_time = time.time()
model.save(os.environ.get('TARGET_DIR') + '/model.h5')
save_time = time.time() - start_time
print(f'Model save time: {save_time:.2f} seconds')

# Measure load time
start_time = time.time()
loaded_model = tf.keras.models.load_model(os.environ.get('TARGET_DIR') + '/model.h5')
load_time = time.time() - start_time
print(f'Model load time: {load_time:.2f} seconds')

# Write results to file
with open(os.environ.get('OUTPUT_DIR') + '/ml_benchmark.txt', 'w') as f:
    f.write(f'Model save time: {save_time:.2f} seconds\\n')
    f.write(f'Model load time: {load_time:.2f} seconds\\n')
"
    else
        echo "Python not found, skipping ML benchmarks."
    fi
    
    # Stop monitoring
    stop_monitoring
    
    # Unmount the device
    echo "Unmounting $mount_point..."
    umount "$mount_point" || true
    
    # If ZFS, destroy the pool
    if [ "$fs" == "zfs" ]; then
        pool_name="zfspool_$(basename "$device")"
        zpool destroy "$pool_name" || true
    fi
    
    echo "=== Benchmark for $device with $fs complete ==="
}

# Function to run all benchmarks for all devices and filesystems
run_all_benchmarks() {
    echo "=== Starting full benchmark suite ==="
    
    # Run idle baseline first
    run_idle_baseline
    
    # Build benchmark container
    echo "Building benchmark container..."
    pushd "$DOCKER_DIR/benchmark" > /dev/null
    docker build -t docker-benchmark .
    popd > /dev/null
    
    # Loop through device types
    for device_type in "hdd" "ssd" "nvme"; do
        echo "Testing $device_type devices..."
        
        # Get devices of this type
        devices=$(get_devices "$device_type")
        
        # Loop through devices
        for device in $devices; do
            # Skip system disk
            if [ "$device" == "$SYSTEM_DISK" ]; then
                echo "Skipping system disk $device"
                continue
            fi
            
            # Loop through filesystems
            for fs in "${FILESYSTEMS[@]}"; do
                echo "Testing $device with $fs filesystem..."
                
                # Prepare result directory
                result_dir=$(prepare_result_dir "$device" "$fs")
                
                # Run benchmark
                run_benchmark "$device" "$fs" "$result_dir"
                
                echo "Completed $device with $fs"
            done
        done
    done
    
    echo "=== Full benchmark suite complete ==="
}

# Function to run benchmark for a specific device and filesystem
run_specific_benchmark() {
    local device=$1
    local fs=$2
    
    # Validate device
    if [ ! -b "$device" ]; then
        echo "Error: Device $device does not exist or is not a block device."
        exit 1
    fi
    
    # Validate filesystem
    if [[ ! " ${FILESYSTEMS[@]} " =~ " ${fs} " ]]; then
        echo "Error: Filesystem $fs is not supported."
        echo "Supported filesystems: ${FILESYSTEMS[*]}"
        exit 1
    fi
    
    # Prepare result directory
    result_dir=$(prepare_result_dir "$device" "$fs")
    
    # Build benchmark container
    echo "Building benchmark container..."
    pushd "$DOCKER_DIR/benchmark" > /dev/null
    docker build -t docker-benchmark .
    popd > /dev/null
    
    # Run the benchmark
    run_benchmark "$device" "$fs" "$result_dir"
}

# Display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --device=DEVICE        Specific device to test (e.g., /dev/sda)"
    echo "  --fs=FILESYSTEM        Specific filesystem to test (ext4, xfs, btrfs, zfs)"
    echo "  --help                 Display this help message"
    echo ""
    echo "Example: $0 --device=/dev/sde --fs=btrfs"
    echo "         $0              # Run all benchmarks"
}

# Parse command line arguments
SPECIFIC_DEVICE=""
SPECIFIC_FS=""

for arg in "$@"; do
    case $arg in
        --device=*)
        SPECIFIC_DEVICE="${arg#*=}"
        ;;
        --fs=*)
        SPECIFIC_FS="${arg#*=}"
        ;;
        --help)
        usage
        exit 0
        ;;
        *)
        echo "Unknown option: $arg"
        usage
        exit 1
        ;;
    esac
done

# Main execution
if [ -n "$SPECIFIC_DEVICE" ] && [ -n "$SPECIFIC_FS" ]; then
    # Run benchmark for specific device and filesystem
    run_specific_benchmark "$SPECIFIC_DEVICE" "$SPECIFIC_FS"
else
    # Run all benchmarks
    run_all_benchmarks
fi

echo "Benchmarks completed: $(date)" 