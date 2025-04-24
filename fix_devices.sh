#!/bin/bash
#
# Docker Filesystem Benchmark - Device Configuration Fix
# This script fixes issues with the devices.conf file

echo "=== Docker Filesystem Benchmark - Device Configuration Fix ==="

# Check if devices.conf exists
if [ ! -f "config/devices.conf" ]; then
    echo "Error: config/devices.conf not found."
    echo "Please run setup.sh first."
    exit 1
fi

echo "Backing up current devices.conf to devices.conf.bak"
cp config/devices.conf config/devices.conf.bak

# Create a new devices.conf with improved format
echo "Creating new devices.conf file..."
cat > config/devices.conf << 'EOF'
# Define devices to test
# Format: device_path,device_type,device_name

# IMPORTANT: This file should be parsed, not sourced/executed

# Auto-detected storage devices:
EOF

# Try to detect block devices
echo "Detecting block devices..."
FOUND_DEVICES=false

if command -v lsblk &> /dev/null; then
    # Get a list of block devices
    block_devices=$(lsblk -d -o NAME,TYPE,SIZE | grep disk | awk '{print $1}')
    
    if [ -n "$block_devices" ]; then
        FOUND_DEVICES=true
        echo "Found block devices: $block_devices"
        
        # Identify system disk (use root mount)
        system_disk="sda"  # Default fallback
        root_device=$(df / | grep -v Filesystem | awk '{print $1}' | sed 's/[0-9]*$//')
        if [ -n "$root_device" ]; then
            # Extract just the device name without /dev/ prefix
            if [[ "$root_device" =~ /dev/(.+) ]]; then
                system_disk="${BASH_REMATCH[1]}"
            else
                system_disk="$root_device"
            fi
            echo "Detected system disk as $system_disk based on root mount"
        fi
        
        # Add each detected block device
        for dev in $block_devices; do
            # Skip if it's the system disk
            if [[ "$dev" == "$system_disk"* ]]; then
                echo "Skipping system disk: /dev/$dev"
                continue
            fi
            
            # Try to determine device type based on name
            dev_type="disk"
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
            
            # Add the device entry as a comment first, then the actual entry
            echo "# /dev/$dev,$dev_type,${dev_type}_$dev" >> config/devices.conf
        done
    fi
fi

if [ "$FOUND_DEVICES" = false ]; then
    echo "No block devices detected or lsblk not available."
    echo "Adding example device entries (commented out)..."
    cat >> config/devices.conf << 'EOF'
# Example entries (uncomment and modify as needed):
# /dev/sdb,hdd,hdd1
# /dev/sdc,hdd,hdd2
# /dev/sdd,ssd,ssd1
# /dev/nvme0n1,nvme,nvme1
EOF
fi

# Add system disk entry
echo "" >> config/devices.conf
echo "# Set system disk to avoid testing it" >> config/devices.conf
if [ -n "$root_device" ]; then
    echo "SYSTEM_DISK=$root_device" >> config/devices.conf
else
    echo "SYSTEM_DISK=/dev/sda  # MODIFY THIS to match your system disk" >> config/devices.conf
fi

echo "======================================================="
echo "Fixed devices.conf created. Here's what it looks like:"
echo "======================================================="
cat config/devices.conf
echo "======================================================="
echo ""
echo "IMPORTANT INSTRUCTIONS:"
echo "1. Review the file above and uncomment device entries you want to test"
echo "2. Verify the SYSTEM_DISK setting is correct"
echo "3. Run the benchmark with: ./scripts/run_benchmarks.sh"
echo ""
echo "For a single device test, try: ./scripts/run_benchmarks.sh --device=/dev/sdX --fs=ext4"
echo "Replace /dev/sdX with one of your actual devices"
echo ""
echo "If you still encounter issues, please check the GitHub repository for updates."

chmod +x fix_devices.sh 