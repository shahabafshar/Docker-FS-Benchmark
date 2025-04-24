FROM alpine:latest

# Install Alpine packages instead of Debian ones
# No need for apt-get which requires internet
RUN apk add --no-cache \
    bash \
    coreutils \
    util-linux \
    grep \
    sed \
    awk \
    python3 \
    py3-pip

# Install minimal Python packages
RUN pip3 install --no-cache-dir \
    numpy \
    pandas

# Create benchmark directory
WORKDIR /benchmark

# Copy benchmark scripts
COPY . /benchmark/

# Create minimal IO benchmark tool
RUN echo '#!/bin/bash' > /benchmark/io_benchmark.sh && \
    echo 'TARGET_DIR=${TARGET_DIR:-/data}' >> /benchmark/io_benchmark.sh && \
    echo 'OUTPUT_DIR=${OUTPUT_DIR:-/data/results}' >> /benchmark/io_benchmark.sh && \
    echo 'mkdir -p "${OUTPUT_DIR}"' >> /benchmark/io_benchmark.sh && \
    echo 'echo "Running simplified I/O benchmarks on ${TARGET_DIR}"' >> /benchmark/io_benchmark.sh && \
    echo 'echo "Writing test file..."' >> /benchmark/io_benchmark.sh && \
    echo 'dd if=/dev/zero of="${TARGET_DIR}/test.img" bs=1M count=100 conv=fsync 2> "${OUTPUT_DIR}/write_speed.txt"' >> /benchmark/io_benchmark.sh && \
    echo 'echo "Reading test file..."' >> /benchmark/io_benchmark.sh && \
    echo 'dd if="${TARGET_DIR}/test.img" of=/dev/null bs=1M 2> "${OUTPUT_DIR}/read_speed.txt"' >> /benchmark/io_benchmark.sh && \
    echo 'echo "File create/delete test..."' >> /benchmark/io_benchmark.sh && \
    echo 'time (for i in $(seq 1 1000); do touch "${TARGET_DIR}/file_$i"; done) 2> "${OUTPUT_DIR}/file_create.txt"' >> /benchmark/io_benchmark.sh && \
    echo 'time (for i in $(seq 1 1000); do rm "${TARGET_DIR}/file_$i"; done) 2> "${OUTPUT_DIR}/file_delete.txt"' >> /benchmark/io_benchmark.sh && \
    echo 'echo "I/O benchmarks complete. Results saved to ${OUTPUT_DIR}"' >> /benchmark/io_benchmark.sh

# Create minimal docker benchmark placeholder
RUN echo '#!/bin/bash' > /benchmark/docker_benchmark.sh && \
    echo 'TARGET_DIR=${TARGET_DIR:-/data}' >> /benchmark/docker_benchmark.sh && \
    echo 'OUTPUT_DIR=${OUTPUT_DIR:-/data/results}' >> /benchmark/docker_benchmark.sh && \
    echo 'mkdir -p "${OUTPUT_DIR}"' >> /benchmark/docker_benchmark.sh && \
    echo 'echo "Docker benchmarks would run on the host, not in container" > "${OUTPUT_DIR}/docker_note.txt"' >> /benchmark/docker_benchmark.sh && \
    echo 'echo "Docker benchmarks skipped in container"' >> /benchmark/docker_benchmark.sh

# Create minimal ML benchmark placeholder
RUN echo '#!/bin/bash' > /benchmark/ml_benchmark.sh && \
    echo 'TARGET_DIR=${TARGET_DIR:-/data}' >> /benchmark/ml_benchmark.sh && \
    echo 'OUTPUT_DIR=${OUTPUT_DIR:-/data/results}' >> /benchmark/ml_benchmark.sh && \
    echo 'mkdir -p "${OUTPUT_DIR}"' >> /benchmark/ml_benchmark.sh && \
    echo 'echo "ML benchmarks skipped (simplified image)" > "${OUTPUT_DIR}/ml_benchmark.txt"' >> /benchmark/ml_benchmark.sh && \
    echo 'echo "ML benchmarks skipped in container"' >> /benchmark/ml_benchmark.sh

# Set execute permissions
RUN chmod +x /benchmark/*.sh

ENTRYPOINT ["/benchmark/run.sh"] 