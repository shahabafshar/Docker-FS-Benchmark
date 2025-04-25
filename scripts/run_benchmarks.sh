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

# Function to safely read the SYSTEM_DISK from config
get_system_disk() {
    # Extract only the line that defines SYSTEM_DISK
    grep -E "^SYSTEM_DISK=" "$CONFIG_FILE" | cut -d= -f2 || echo "/dev/sda"
}

# Get system disk without sourcing the file
SYSTEM_DISK=$(get_system_disk)
if [ -z "$SYSTEM_DISK" ]; then
    echo "Warning: SYSTEM_DISK not defined in config file. Using /dev/sda as default."
    SYSTEM_DISK="/dev/sda"
fi

echo "System disk set to: $SYSTEM_DISK"

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

# Function to verify device exists
verify_device() {
    local device=$1
    if [ ! -b "$device" ]; then
        echo "Warning: Device $device does not exist or is not a block device."
        return 1
    fi
    return 0
}

# Function to get device list from config and verify they exist
get_devices() {
    local device_type=$1
    local devices=()
    
    # Extract devices of the specified type from config file
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^#.*$ || -z "$line" ]]; then
            continue
        fi
        
        # Skip the SYSTEM_DISK line
        if [[ "$line" =~ ^SYSTEM_DISK= ]]; then
            continue
        fi
        
        # Parse device entries
        if [[ "$line" =~ ^/dev/.*,$device_type, ]]; then
            device=$(echo "$line" | cut -d',' -f1)
            
            # Verify device exists
            if verify_device "$device"; then
                devices+=("$device")
            fi
        fi
    done < "$CONFIG_FILE"
    
    # Check if any devices were found
    if [ ${#devices[@]} -eq 0 ]; then
        echo "No valid $device_type devices found in configuration."
        return 1
    fi
    
    # Return devices as space-separated string
    echo "${devices[@]}"
    return 0
}

# Function to get device nice name from config
get_device_name() {
    local device=$1
    local name
    
    # Try to find the device in the config file
    name=$(grep "^$device," "$CONFIG_FILE" | cut -d',' -f3)
    
    # If not found in config, use the device basename as fallback
    if [ -z "$name" ]; then
        name=$(basename "$device")
    fi
    
    echo "$name"
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

# Function to start monitoring
start_monitoring() {
    echo "Starting monitoring stack..."
    
    pushd "$DOCKER_DIR" > /dev/null
    
    # Check if docker-compose is available
    if command -v docker-compose &> /dev/null; then
        echo "Using docker-compose to start monitoring..."
        
        # First attempt to start with Docker Compose
        if docker-compose up -d; then
            echo "Monitoring stack started successfully."
        else
            echo "Warning: First attempt to start monitoring with docker-compose failed."
            echo "Cleaning up any partially started containers and trying again..."
            
            # Cleanup any partially started containers
            docker-compose down 2>/dev/null || true
            
            # Second attempt after cleanup
            echo "Making second attempt to start monitoring with docker-compose..."
            if docker-compose up -d; then
                echo "Monitoring stack started successfully on second attempt."
            else
                echo "Warning: Failed to start monitoring with docker-compose after retry."
                echo "Falling back to simple monitoring script..."
                
                # Use our simple monitoring script instead
                if [ -f "$SCRIPT_DIR/run_monitoring.sh" ]; then
                    "$SCRIPT_DIR/run_monitoring.sh" stop 2>/dev/null || true
                    "$SCRIPT_DIR/run_monitoring.sh" start
                else
                    echo "Error: Simple monitoring script not found at $SCRIPT_DIR/run_monitoring.sh"
                    echo "Proceeding without monitoring. Results may be incomplete."
                fi
            fi
        fi
    else
        echo "Docker Compose not found."
        
        # Try to start with simple monitoring script
        if [ -f "$SCRIPT_DIR/run_monitoring.sh" ]; then
            echo "Using simple monitoring script to start monitoring..."
            "$SCRIPT_DIR/run_monitoring.sh" start
        else
            echo "Error: Simple monitoring script not found at $SCRIPT_DIR/run_monitoring.sh"
            echo "Proceeding without monitoring. Results may be incomplete."
        fi
    fi
    
    popd > /dev/null
}

# Function to stop monitoring
stop_monitoring() {
    echo "Stopping monitoring stack..."
    
    pushd "$DOCKER_DIR" > /dev/null
    
    # Check if docker-compose is available
    if command -v docker-compose &> /dev/null; then
        echo "Using docker-compose to stop monitoring..."
        
        # Attempt to stop with Docker Compose
        if docker-compose down; then
            echo "Monitoring stack stopped successfully."
        else
            echo "Warning: Failed to stop monitoring with docker-compose."
            
            # Fallback to simple monitoring script
            if [ -f "$SCRIPT_DIR/run_monitoring.sh" ]; then
                echo "Falling back to simple monitoring script to stop monitoring..."
                "$SCRIPT_DIR/run_monitoring.sh" stop
            else
                echo "Error: Simple monitoring script not found at $SCRIPT_DIR/run_monitoring.sh"
                echo "Attempting direct container removal as last resort..."
                
                # Direct container removal as last resort
                docker rm -f node-exporter prometheus grafana 2>/dev/null || true
                echo "Cleanup attempt completed. Some containers may still be running."
            fi
        fi
    else
        echo "Docker Compose not found."
        
        # Try to stop with simple monitoring script
        if [ -f "$SCRIPT_DIR/run_monitoring.sh" ]; then
            echo "Using simple monitoring script to stop monitoring..."
            "$SCRIPT_DIR/run_monitoring.sh" stop
        else
            echo "Error: Simple monitoring script not found at $SCRIPT_DIR/run_monitoring.sh"
            echo "Attempting direct container removal..."
            
            # Direct container removal as last resort
            docker rm -f node-exporter prometheus grafana 2>/dev/null || true
            echo "Cleanup attempt completed. Some containers may still be running."
        fi
    fi
    
    popd > /dev/null
}

# Function to run idle state baseline
run_idle_baseline() {
    echo "Running idle state baseline for 15 minutes..."
    
    # Skip the wait if in debug mode
    if [ "$DEBUG_MODE" = true ]; then
        echo "DEBUG MODE: Skipping 15-minute wait"
        # Start monitoring
        start_monitoring
        
        # Sleep for 15 minutes
        sleep 5
        
        # Stop monitoring
        stop_monitoring
    else
        # Start monitoring
        start_monitoring
        
        # Sleep for 15 minutes
        sleep 900
        
        # Stop monitoring
        stop_monitoring
    fi
    
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
    
    # Start monitoring
    start_monitoring
    
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
            tensorflow/tensorflow:latest \
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

# Function to detect available storage devices
detect_storage_devices() {
    echo "Detecting available storage devices..."
    
    # Get a list of block devices
    local block_devices=$(lsblk -d -o NAME,TYPE,SIZE | grep disk | awk '{print $1}')
    
    if [ -z "$block_devices" ]; then
        echo "No block devices found. This is unusual and may indicate a problem."
        return 1
    fi
    
    echo "Found the following block devices:"
    lsblk -d -o NAME,TYPE,SIZE,MODEL | grep disk
    
    # Create a new devices.conf if the user confirms
    echo ""
    echo "Would you like to generate a new devices.conf file with these devices? (y/n)"
    read -r answer
    
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        local new_config="$CONFIG_DIR/devices.conf.new"
        
        # Start with a header
        cat > "$new_config" << 'EOF'
# Define devices to test
# Format: device_path,device_type,device_name

# Block devices detected on the system
EOF
        
        # Add each detected block device
        for dev in $block_devices; do
            # Skip if it's the system disk
            if [ "/dev/$dev" == "$SYSTEM_DISK" ]; then
                continue
            fi
            
            # Try to determine device type based on name
            local dev_type="disk"
            if [[ "$dev" == nvme* ]]; then
                dev_type="nvme"
            elif [[ "$dev" == sd* ]]; then
                # Check if it's an SSD or HDD
                if [ -e "/sys/block/$dev/queue/rotational" ]; then
                    if [ "$(cat /sys/block/$dev/queue/rotational)" == "0" ]; then
                        dev_type="ssd"
                    else
                        dev_type="hdd"
                    fi
                fi
            fi
            
            echo "/dev/$dev,$dev_type,${dev_type}_$dev" >> "$new_config"
        done
        
        # Add system disk entry
        echo "" >> "$new_config"
        echo "# Set this to your system disk to avoid testing it" >> "$new_config"
        echo "SYSTEM_DISK=$SYSTEM_DISK" >> "$new_config"
        
        # Offer to replace the old config
        echo "New configuration created at $new_config"
        echo "Would you like to use this new configuration? (y/n)"
        read -r answer
        
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            mv "$new_config" "$CONFIG_FILE"
            echo "Configuration updated."
        else
            echo "Keeping existing configuration."
        fi
    fi
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
        status=$?
        echo "^^^ status: $status"
        echo "^^^ devices: $devices"
        if [ $status -ne 0 ] || [ -z "$devices" ]; then
            echo "Warning: No $device_type devices found or error getting devices"
            continue
        fi


        echo "Querying devices of type: $device_type"
        if ! devices=$(get_devices "$device_type"); then
            echo "Warning: No $device_type devices found or error getting devices"
            continue
        fi
        
        if [ "$DEBUG_MODE" = true ]; then
            echo "DEBUG: Raw devices list for $device_type: $devices"
        fi
        
        # Convert space-separated list to array
        read -ra device_array <<< "$devices"
        
        if [ "$DEBUG_MODE" = true ]; then
            echo "DEBUG: Number of $device_type devices found: ${#device_array[@]}"
            echo "DEBUG: Device array contents:"
            printf "DEBUG: - %s\n" "${device_array[@]}"
        fi
        
        # Loop through devices
        for device in "${device_array[@]}"; do
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
    if ! verify_device "$device"; then
        echo "Error: Device $device does not exist or is not a block device."
        echo "Available block devices:"
        lsblk -d -o NAME,TYPE,SIZE,MODEL | grep disk
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
    echo "  --detect-devices       Scan for available storage devices and offer to update config"
    echo "  --debug                Run in debug mode (skip waits, print more info)"
    echo "  --help                 Display this help message"
    echo ""
    echo "Example: $0 --device=/dev/sde --fs=btrfs"
    echo "         $0 --detect-devices"
    echo "         $0 --debug --device=/dev/sda --fs=ext4"
    echo "         $0              # Run all benchmarks"
}

# Parse command line arguments
SPECIFIC_DEVICE=""
SPECIFIC_FS=""
DETECT_DEVICES=false
DEBUG_MODE=false

for arg in "$@"; do
    case $arg in
        --device=*)
        SPECIFIC_DEVICE="${arg#*=}"
        ;;
        --fs=*)
        SPECIFIC_FS="${arg#*=}"
        ;;
        --detect-devices)
        DETECT_DEVICES=true
        ;;
        --debug)
        DEBUG_MODE=true
        echo "DEBUG MODE ENABLED - Will skip long waits and show more information"
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
if [ "$DETECT_DEVICES" = true ]; then
    detect_storage_devices
elif [ -n "$SPECIFIC_DEVICE" ] && [ -n "$SPECIFIC_FS" ]; then
    # Run benchmark for specific device and filesystem
    run_specific_benchmark "$SPECIFIC_DEVICE" "$SPECIFIC_FS"
else
    # Run all benchmarks
    run_all_benchmarks
fi

echo "Benchmarks completed: $(date)" 