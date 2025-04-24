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

# Properly parse the system disk from config file
SYSTEM_DISK=$(grep "^SYSTEM_DISK=" "$CONFIG_FILE" | cut -d= -f2)
if [ -z "$SYSTEM_DISK" ]; then
    echo "Warning: SYSTEM_DISK not defined in config file. Using /dev/sdc as default."
    SYSTEM_DISK="/dev/sdc"
fi

echo "System disk set to: $SYSTEM_DISK"

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
    echo "Checking if device is mounted..."
    if mount | grep -q "$device"; then
        echo "Device is mounted, attempting to unmount..."
        umount "$device" 2>/dev/null || true
    fi
    
    # Check if the device is still mounted
    if mount | grep -q "$device"; then
        echo "Error: Unable to unmount $device. It may be in use."
        return 1
    fi
    
    # Clear any existing filesystem signatures
    echo "Clearing existing filesystem signatures..."
    if ! wipefs -a "$device" 2>/dev/null; then
        echo "Warning: Failed to clear filesystem signatures. Continuing anyway."
    fi
    
    # Format with requested filesystem
    case "$filesystem" in
        ext4)
            echo "Creating ext4 filesystem..."
            if ! mkfs.ext4 -F "$device"; then
                echo "Error: Failed to create ext4 filesystem on $device"
                return 1
            fi
            ;;
        xfs)
            echo "Creating xfs filesystem..."
            if ! mkfs.xfs -f "$device"; then
                echo "Error: Failed to create xfs filesystem on $device"
                return 1
            fi
            ;;
        btrfs)
            echo "Creating btrfs filesystem..."
            if ! mkfs.btrfs -f "$device"; then
                echo "Error: Failed to create btrfs filesystem on $device"
                return 1
            fi
            ;;
        zfs)
            # Create ZFS pool and filesystem
            pool_name="zfspool_$(basename "$device")"
            
            # Check if the ZFS module is loaded
            if ! lsmod | grep -q zfs; then
                echo "Error: ZFS kernel module not loaded. Please run 'modprobe zfs' first."
                return 1
            fi
            
            # Destroy if exists
            if zpool list | grep -q "$pool_name"; then
                echo "ZFS pool $pool_name exists, destroying..."
                zpool destroy "$pool_name" 2>/dev/null || true
            fi
            
            # Create new pool
            echo "Creating ZFS pool $pool_name..."
            if ! zpool create -f "$pool_name" "$device"; then
                echo "Error: Failed to create ZFS pool $pool_name"
                return 1
            fi
            
            echo "Setting ZFS pool properties..."
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
    if [ ! -d "$mount_point" ]; then
        echo "Creating mount point $mount_point..."
        mkdir -p "$mount_point"
    fi
    
    # Mount based on filesystem type
    case "$filesystem" in
        zfs)
            # For ZFS, we mount the pool
            if [ -z "$zfs_pool" ]; then
                echo "Error: ZFS pool name is required."
                return 1
            fi
            echo "Mounting ZFS pool $zfs_pool..."
            if ! mount -t zfs "$zfs_pool" "$mount_point"; then
                echo "Error: Failed to mount ZFS pool $zfs_pool"
                return 1
            fi
            ;;
        *)
            # For other filesystems, mount the device directly
            echo "Mounting device $device..."
            if ! mount "$device" "$mount_point"; then
                echo "Error: Failed to mount $device"
                return 1
            fi
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
    
    # Check if the device exists
    if [ ! -b "$device" ]; then
        echo "Error: Device $device does not exist or is not a block device."
        echo "Available block devices:"
        lsblk -d -o NAME,TYPE,SIZE,MODEL | grep disk
        return 1
    fi
    
    # Format the device
    local zfs_pool=""
    if [ "$filesystem" == "zfs" ]; then
        zfs_pool=$(format_device "$device" "$filesystem")
        if [ $? -ne 0 ] || [ -z "$zfs_pool" ]; then
            echo "Error: Failed to format $device with ZFS."
            return 1
        fi
    else
        if ! format_device "$device" "$filesystem"; then
            echo "Error: Failed to format $device with $filesystem."
            return 1
        fi
    fi
    
    # Mount the device
    if ! mount_device "$device" "$filesystem" "$mount_point" "$zfs_pool"; then
        echo "Error: Failed to mount $device ($filesystem) to $mount_point."
        return 1
    fi
    
    # Set appropriate permissions
    echo "Setting permissions on $mount_point..."
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
if prepare_device_for_benchmark "$DEVICE" "$FILESYSTEM"; then
    echo "Device preparation complete."
    exit 0
else
    echo "Device preparation failed."
    exit 1
fi 