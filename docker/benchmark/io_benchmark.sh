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