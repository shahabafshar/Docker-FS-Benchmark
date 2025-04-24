#!/bin/bash
# Main benchmark runner script
# This is the entrypoint for the benchmark container that coordinates
# running the various benchmark types based on environment variables.

echo "=== Docker Filesystem Benchmark Suite ==="
echo "Target directory: ${TARGET_DIR:-/data}"

# Check which benchmark type to run
# BENCHMARK_TYPE can be "io", "docker", "ml", or "all"
# If not specified, defaults to "all"
BENCHMARK_TYPE=${BENCHMARK_TYPE:-all}
echo "Benchmark type: ${BENCHMARK_TYPE}"

# Run IO benchmarks (fio and bonnie++)
# These measure raw filesystem performance with different I/O patterns
if [ "${BENCHMARK_TYPE}" = "io" ] || [ "${BENCHMARK_TYPE}" = "all" ]; then
    echo "Running I/O benchmarks..."
    /benchmark/io_benchmark.sh
fi

# Run Docker benchmarks
# These measure Docker-specific operations that depend on filesystem performance
# Note: Actual Docker commands are run by the host, this is just a placeholder
if [ "${BENCHMARK_TYPE}" = "docker" ] || [ "${BENCHMARK_TYPE}" = "all" ]; then
    echo "Running Docker benchmarks..."
    /benchmark/docker_benchmark.sh
fi

# Run ML benchmarks
# These measure TensorFlow model save/load performance
if [ "${BENCHMARK_TYPE}" = "ml" ] || [ "${BENCHMARK_TYPE}" = "all" ]; then
    echo "Running ML benchmarks..."
    /benchmark/ml_benchmark.sh
fi

echo "Benchmark complete."
echo "Results are available in ${OUTPUT_DIR:-/data/results}" 