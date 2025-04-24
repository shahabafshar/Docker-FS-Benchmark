#!/bin/bash
#
# Docker Filesystem Benchmark - Device Formatting Script
# This script formats storage devices with different filesystems for benchmarking

set -e

echo "=== Docker Filesystem Benchmark - Device Formatter ==="

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires root privileges to format devices."
    echo "Please run with sudo or as root."
    exit 1
fi

# Load configuration
CONFIG_FILE="config/devices.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found."
    echo "Please run setup.sh first."
    exit 1
fi

# Source system disk to avoid formatting it
source "$CONFIG_FILE"

# Function to format a device with a specific filesystem
format_device() {
    local device=$1
    local filesystem=$2
    
    # Check if device exists
    if [ ! -b "$device" ]; then
        echo "Error: Device $device does not exist or is not a block device."
        return 1
    fi
    
    # Check if device is the system disk
    if [ "$device" == "$SYSTEM_DISK" ]; then
        echo "Error: Cannot format $device as it is the system disk."
        return 1
    fi
    
    echo "Formatting $device with $filesystem filesystem..."
    
    # Unmount if mounted
    umount "$device" 2>/dev/null || true
    
    # Clear any existing filesystem signatures
    wipefs -a "$device"
    
    # Format with requested filesystem
    case "$filesystem" in
        ext4)
            mkfs.ext4 -F "$device"
            ;;
        xfs)
            mkfs.xfs -f "$device"
            ;;
        btrfs)
            mkfs.btrfs -f "$device"
            ;;
        zfs)
            # Create ZFS pool and filesystem
            pool_name="zfspool_$(basename "$device")"
            
            # Destroy if exists
            zpool destroy "$pool_name" 2>/dev/null || true
            
            # Create new pool
            zpool create -f "$pool_name" "$device"
            zfs set atime=off "$pool_name"
            zfs set compression=off "$pool_name"
            
            # We'll use the pool directly, so return the pool name
            echo "$pool_name"
            return 0
            ;;
        *)
            echo "Error: Unsupported filesystem $filesystem"
            return 1
            ;;
    esac
    
    echo "Formatting of $device with $filesystem complete."
    return 0
}

# Function to mount a formatted device
mount_device() {
    local device=$1
    local filesystem=$2
    local mount_point=$3
    local zfs_pool=$4
    
    echo "Mounting $device ($filesystem) to $mount_point..."
    
    # Create mount point if it doesn't exist
    mkdir -p "$mount_point"
    
    # Mount based on filesystem type
    case "$filesystem" in
        zfs)
            # For ZFS, we mount the pool
            if [ -z "$zfs_pool" ]; then
                echo "Error: ZFS pool name is required."
                return 1
            fi
            mount -t zfs "$zfs_pool" "$mount_point"
            ;;
        *)
            # For other filesystems, mount the device directly
            mount "$device" "$mount_point"
            ;;
    esac
    
    echo "Device mounted successfully at $mount_point"
    return 0
}

# Main function to format and mount a device for benchmarking
prepare_device_for_benchmark() {
    local device=$1
    local filesystem=$2
    local mount_point="/mnt/testdisk"
    
    echo "=== Preparing $device with $filesystem for benchmarking ==="
    
    # Format the device
    local zfs_pool=""
    if [ "$filesystem" == "zfs" ]; then
        zfs_pool=$(format_device "$device" "$filesystem")
    else
        format_device "$device" "$filesystem"
    fi
    
    # Mount the device
    mount_device "$device" "$filesystem" "$mount_point" "$zfs_pool"
    
    # Set appropriate permissions
    chmod 777 "$mount_point"
    
    echo "=== Device $device prepared with $filesystem at $mount_point ==="
    return 0
}

# Display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --device=DEVICE        Device to format (e.g., /dev/sda)"
    echo "  --fs=FILESYSTEM        Filesystem to use (ext4, xfs, btrfs, zfs)"
    echo "  --help                 Display this help message"
    echo ""
    echo "Example: $0 --device=/dev/sde --fs=btrfs"
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

# Execute the main function
prepare_device_for_benchmark "$DEVICE" "$FILESYSTEM"

echo "Device preparation complete." 