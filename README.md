# **Docker Filesystem Benchmark Suite**

A comprehensive, container-based benchmark framework for evaluating storage performance across different file systems and device classes on Docker containers.

---

## **Project Objective**

This study aims to systematically evaluate **OverlayFS, ZFS, Btrfs**, and also the control fs **ext4, XFS**, on **HDD, SATA SSD, and NVMe** storage using Docker containers. The tests will provide insights into how different backends behave under common enterprise, database, and ML/AI workloads.

---

## **Prerequisites**

- Linux-based system with Docker installed
- Root access for filesystem operations
- Sufficient storage devices for testing
- Python 3.8+ for analysis scripts
- Docker Compose for running the monitoring stack

---

## **Getting Started**

```bash
# Clone the repository
git clone https://github.com/shahabafshar/Docker-FS-Benchmark.git
cd Docker-FS-Benchmark

# Provide the scripts with execution permission
chmod +x ./scripts/*.sh

# Install dependencies and setup monitoring
./scripts/setup.sh

# Run benchmarks (will take several hours)
./scripts/run_benchmarks.sh

# Analyze results
./scripts/analyze_results.sh
```

## **Device Detection**

The benchmark automatically detects storage devices during setup, but you can also manually scan for devices:

```bash
# Scan for available block devices and update configuration
./scripts/run_benchmarks.sh --detect-devices
```

If you encounter device errors, verify your storage configuration:

```bash
# List all block devices
lsblk -d

# Check the current device configuration
cat config/devices.conf

# Run a specific device/filesystem combination
./scripts/run_benchmarks.sh --device=/dev/sdX --fs=ext4
```

## **Troubleshooting**

- **Device not found errors**: Edit `config/devices.conf` to match your system's actual devices
- **ZFS errors**: Ensure ZFS module is loaded with `modprobe zfs`
- **Permission errors**: Make sure you're running with root/sudo privileges
- **Mount errors**: Verify no filesystems are already mounted at `/mnt/testdisk`

---

## **System Configuration**

- **Platform:** Chameleon Cloud – Node `c10-21` @ TACC  
- **Model:** Dell PowerEdge R730  
- **CPU:** 2 × Intel Xeon E5-2670 v3 (48 threads total)  
- **RAM:** 512 GiB  
- **Storage Breakdown:**
  - **HDDs:** `/dev/sda`–`/dev/sdd` – 600 GB Seagate ST600MP0005
  - **SATA SSDs:** `/dev/sde`–`/dev/sdh` – 1.6 TB Intel SSDSC2BX01
  - **NVMe SSDs:** `/dev/nvme0n1`, `/dev/nvme1n1` – 2 TB Intel P3700
  - **System Disk:** `/dev/sdc` (OS + logs only; excluded from tests)

---

## **Filesystems to Benchmark**

- OverlayFS (as Docker's upperdir)
- ZFS
- Btrfs
- ext4
- XFS

---

## **Performance Metrics**

Each test suite will collect the following:
- IOPS (sequential/random read/write)
- Throughput (MB/s)
- Latency (avg/min/max)
- Docker container startup & teardown time
- Docker image pull/build time
- Filesystem snapshot creation/removal time (ZFS/Btrfs)
- ML/AI model storage performance (TensorFlow checkpoint save/load)
- System resource utilization (CPU, RAM, IO wait)
- Background noise baseline from idle-state monitoring

---

## **Benchmark Tools**

The suite uses the following industry-standard tools:
- **fio**: Flexible I/O tester for IOPS, throughput, and latency
- **fs-mark**: Filesystem metadata performance (file creation)
- **bonnie++**: Sequential reads, writes, and file operations
- **sysbench**: Database I/O patterns
- **TensorFlow I/O**: ML model checkpoint and loading performance

---

## **Monitoring Stack**

- **Prometheus** and **Grafana** containers run from `/dev/sdc`
- Metrics exported from:
  - Host-level node exporter
  - Docker daemon metrics
  - Filesystem-specific telemetry (e.g., ZFS ARC, Btrfs stats)

---

## **Project Structure**

```plaintext
docker-filesystem-benchmark/
├── README.md
├── config/
│   ├── prometheus/
│   └── grafana/
├── scripts/
│   ├── setup.sh                # Install deps, pull containers
│   ├── format_devices.sh       # Format storage with target FS
│   ├── run_benchmarks.sh       # Loop through devices and FSes
│   └── analyze_results.sh      # Parse + plot
├── docker/
│   ├── benchmark/              # Container for benchmark tools
│   ├── monitoring/             # Prometheus + Grafana
│   └── docker-compose.yml
├── benchmarks/
│   ├── io/                     # fio, fs-mark, bonnie++
│   ├── docker/                 # Pull/start/build benchmarks
│   └── ml/                     # TensorFlow/PyTorch I/O tests
└── results/
    ├── raw/
    ├── processed/
    └── visualizations/
```

---

## **Experiment Workflow**

1. **Idle-State Baseline:**
   - Run monitoring stack with no workload for 15 min.
   - Collect CPU, IO, memory, and disk stats.

2. **Per-Device Benchmarking Loop:**
   - For each device:
     - Wipe & reformat with selected FS (`blkdiscard`, `mkfs.*`)
     - Mount to `/mnt/testdisk`
     - Launch `docker-benchmark-runner` targeting the mount
     - Run full suite (I/O, Docker ops, ML)
     - Record results
     - Repeat for next FS

3. **Repeat for All Storage Categories**

4. **Visualization & Analysis:**
   - Auto-import into Grafana
   - Generate summary plots
   - Compare across FSes and devices

---

## **Usage**

```bash
# Install dependencies and setup
./scripts/setup.sh

# Customize device selection (optional)
# Edit config/devices.conf to select which devices to test

# Run all benchmarks (can take many hours)
./scripts/run_benchmarks.sh

# Run benchmarks on specific filesystem and device
./scripts/run_benchmarks.sh --fs=zfs --device=/dev/sde

# Generate analysis and visualizations
./scripts/analyze_results.sh

# View results in Grafana
http://localhost:3000/
```

---

## **Best Practices**

- Never benchmark on `/dev/sdc` (OS & logging only)
- All results timestamped and stored in `/mnt/sdc/results/`
- Containers are rebuilt fresh before each run to eliminate caching artifacts
- FS formatted from scratch before each test to normalize behavior

---

## **License**

This project is licensed under the MIT License - see the LICENSE file for details.

---

## **Authors**

- Shahab Afshar - Initial work

For questions or contributions, please open an issue or PR on the [GitHub repository](https://github.com/shahabafshar/Docker-FS-Benchmark)