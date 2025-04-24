#!/bin/bash
#
# Docker Filesystem Benchmark - Direct Runner Script (No Monitoring)
# This script runs benchmarks without the monitoring stack for constrained environments

set -e

echo "=== Docker Filesystem Benchmark Suite (Direct Mode) ==="
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

# Prepare directories
mkdir -p "$RESULTS_DIR/raw"
mkdir -p "$RESULTS_DIR/processed"

# List of filesystems to test
FILESYSTEMS=("ext4" "xfs" "btrfs" "zfs")

# Function to verify device exists
verify_device() {
    local device=$1
    if [ ! -b "$device" ]; then
        echo "Error: Device $device does not exist or is not a block device."
        lsblk -d
        return 1
    fi
    return 0
}

# Function to prepare results directory for a specific run
prepare_result_dir() {
    local device=$1
    local fs=$2
    local device_name=$(basename "$device")
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # Create directory for this run
    local result_dir="$RESULTS_DIR/raw/${device_name}_${fs}_${timestamp}"
    mkdir -p "$result_dir"
    
    echo "$result_dir"
}

# Function to run benchmarks on a specific device and filesystem
run_direct_benchmark() {
    local device=$1
    local fs=$2
    local result_dir=$3
    local mount_point="/mnt/testdisk"
    
    echo "=== Running benchmarks for $device with $fs ==="
    
    # Format and mount the device
    "$SCRIPT_DIR/format_devices.sh" --device="$device" --fs="$fs"
    
    # Check if format and mount was successful
    if [ $? -ne 0 ]; then
        echo "Error: Failed to format or mount device $device with filesystem $fs"
        return 1
    fi
    
    # Verify the mount point exists and is accessible
    if [ ! -d "$mount_point" ]; then
        echo "Error: Mount point $mount_point does not exist"
        return 1
    fi
    
    # Record filesystem info
    if ! df -h "$mount_point" > "$result_dir/filesystem_info.txt" 2>&1; then
        echo "Warning: Could not record filesystem info for $mount_point"
    fi
    
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
    
    # Run Docker benchmarks directly
    echo "Running Docker benchmarks directly..."
    
    # 1. Pull time benchmark
    echo "Measuring Docker image pull time..."
    docker rmi alpine:latest >/dev/null 2>&1 || true
    {
        time docker pull alpine:latest
    } 2>&1 | tee "$result_dir/docker_pull_time.txt"
    
    # 2. Build time benchmark
    echo "Measuring Docker image build time..."
    mkdir -p "$mount_point/docker_build_test"
    cat > "$mount_point/docker_build_test/Dockerfile" << 'EOF'
FROM alpine:latest
RUN apk add --no-cache python3 py3-pip
WORKDIR /app
CMD ["echo", "Hello, World!"]
EOF
    
    {
        time docker build -t benchmark_test "$mount_point/docker_build_test/"
    } 2>&1 | tee "$result_dir/docker_build_time.txt"
    
    # 3. Container start/stop time (simplified)
    echo "Measuring container start/stop time..."
    for i in {1..5}; do
        {
            time docker run --rm alpine:latest echo "Test $i"
        } 2>&1 | tee -a "$result_dir/docker_start_stop_time.txt"
    done
    
    # Skip ML benchmarks as they're resource-intensive
    
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

# Display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --device=DEVICE        Specific device to test (e.g., /dev/sda)"
    echo "  --fs=FILESYSTEM        Specific filesystem to test (ext4, xfs, btrfs, zfs)"
    echo "  --help                 Display this help message"
    echo ""
    echo "Example: $0 --device=/dev/vda --fs=ext4"
}

# Parse command line arguments
DEVICE=""
FILESYSTEM=""

for arg in "$@"; do
    case $arg in
        --device=*)
        DEVICE="${arg#*=}"
        ;;
        --fs=*)
        FILESYSTEM="${arg#*=}"
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

# Validate inputs
if [ -z "$DEVICE" ] || [ -z "$FILESYSTEM" ]; then
    echo "Error: Both device and filesystem must be specified."
    usage
    exit 1
fi

# Check device
if ! verify_device "$DEVICE"; then
    echo "Device verification failed. Available devices:"
    lsblk -d
    exit 1
fi

# Check filesystem
if [[ ! " ${FILESYSTEMS[@]} " =~ " ${FILESYSTEM} " ]]; then
    echo "Error: Filesystem $FILESYSTEM is not supported."
    echo "Supported filesystems: ${FILESYSTEMS[*]}"
    exit 1
fi

# Build benchmark container
echo "Building benchmark container..."
pushd "$DOCKER_DIR/benchmark" > /dev/null
docker build -t docker-benchmark .
popd > /dev/null

# Run benchmark
result_dir=$(prepare_result_dir "$DEVICE" "$FILESYSTEM")
run_direct_benchmark "$DEVICE" "$FILESYSTEM" "$result_dir"

echo "Direct benchmarks completed: $(date)"
echo "Results saved to: $result_dir" 