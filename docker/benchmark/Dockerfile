FROM python:3.9-slim

# Install system tools for benchmarking
# - fio: Flexible I/O tester for throughput and latency
# - bonnie++: Classic filesystem benchmarking tool
# - iproute2: Network utilities
# - procps: System information utilities
# - sysstat: Performance monitoring tools
# - util-linux: Basic system utilities
# - wget: For downloading files during tests
RUN apt-get update && apt-get install -y \
    fio \
    bonnie++ \
    iproute2 \
    procps \
    sysstat \
    util-linux \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages for data analysis and instrumentation
# - numpy/pandas: Data analysis libraries
# - prometheus-client: Metrics export
# - psutil: System monitoring
# - matplotlib/seaborn: Visualization libraries
RUN pip install --no-cache-dir \
    numpy \
    pandas \
    prometheus-client \
    psutil \
    matplotlib \
    seaborn

# Create benchmark directory
WORKDIR /benchmark

# Copy benchmark scripts from build context
COPY . /benchmark/

# Set execute permissions on all shell scripts
RUN chmod +x /benchmark/*.sh

# Use run.sh as the container entry point
ENTRYPOINT ["/benchmark/run.sh"] 