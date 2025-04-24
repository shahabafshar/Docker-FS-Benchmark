FROM python:3.9-slim

# Install system tools
RUN apt-get update && apt-get install -y \
    fio \
    bonnie++ \
    iproute2 \
    procps \
    sysstat \
    util-linux \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip install --no-cache-dir \
    numpy \
    pandas \
    prometheus-client \
    psutil \
    matplotlib \
    seaborn

# Create benchmark directory
WORKDIR /benchmark

# Copy benchmark scripts
COPY . /benchmark/

# Set execute permissions
RUN chmod +x /benchmark/*.sh

ENTRYPOINT ["/benchmark/run.sh"] 