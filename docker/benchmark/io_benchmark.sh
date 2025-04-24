#!/bin/bash
# I/O benchmarks using fio and bonnie++
# This script runs a series of filesystem performance tests to evaluate
# sequential/random read/write performance and file operations.

# Set target directories with defaults
TARGET_DIR=${TARGET_DIR:-/data}
OUTPUT_DIR=${OUTPUT_DIR:-/data/results}

# Create output directory if it doesn't exist
mkdir -p "${OUTPUT_DIR}"

echo "Running I/O benchmarks on ${TARGET_DIR}"

# Sequential Read Test
# Parameters:
# - bs=1m: 1MB block size (large blocks for sequential operations)
# - direct=1: Use O_DIRECT to bypass page cache
# - size=1G: Total size to read per job
# - numjobs=4: Run 4 parallel jobs to simulate multiple threads
echo "Running sequential read test..."
fio --directory="${TARGET_DIR}" \
    --name=seqread \
    --rw=read \
    --bs=1m \
    --direct=1 \
    --size=1G \
    --numjobs=4 \
    --group_reporting \
    --output="${OUTPUT_DIR}/fio_seqread.txt"

# Sequential Write Test
# Same parameters as sequential read, but for writes
echo "Running sequential write test..."
fio --directory="${TARGET_DIR}" \
    --name=seqwrite \
    --rw=write \
    --bs=1m \
    --direct=1 \
    --size=1G \
    --numjobs=4 \
    --group_reporting \
    --output="${OUTPUT_DIR}/fio_seqwrite.txt"

# Random Read Test
# Parameters:
# - bs=4k: 4KB block size (typical for random I/O)
# - rw=randread: Random read pattern
# - Other parameters same as sequential tests
echo "Running random read test..."
fio --directory="${TARGET_DIR}" \
    --name=randread \
    --rw=randread \
    --bs=4k \
    --direct=1 \
    --size=1G \
    --numjobs=4 \
    --group_reporting \
    --output="${OUTPUT_DIR}/fio_randread.txt"

# Random Write Test
# Same parameters as random read, but for writes
echo "Running random write test..."
fio --directory="${TARGET_DIR}" \
    --name=randwrite \
    --rw=randwrite \
    --bs=4k \
    --direct=1 \
    --size=1G \
    --numjobs=4 \
    --group_reporting \
    --output="${OUTPUT_DIR}/fio_randwrite.txt"

# Bonnie++ File Operation Test
# Parameters:
# - d: directory to test
# - u: run as root user
# - n: no per-char I/O tests (0)
# - r: file size in MB (1024 = 1GB)
# - s: RAM size in MB to use (1024 = 1GB)
# - f: skip per-char tests
# - b: use direct I/O if possible
# - D: disable fsync after sequential create tests
echo "Running Bonnie++ file operation tests..."
bonnie++ -d "${TARGET_DIR}" -u root -n 0 -r 1024 -s 1024 -f -b -D > "${OUTPUT_DIR}/bonnie.txt"

echo "I/O benchmarks complete. Results saved to ${OUTPUT_DIR}" 