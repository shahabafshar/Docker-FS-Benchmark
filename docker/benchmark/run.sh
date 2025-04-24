#!/bin/bash
# Main benchmark runner script

echo "Running Docker Filesystem Benchmark Suite"
echo "Target directory: ${TARGET_DIR:-/data}"

# Run IO benchmarks
if [ "${BENCHMARK_TYPE}" = "io" ] || [ "${BENCHMARK_TYPE}" = "all" ]; then
    echo "Running I/O benchmarks..."
    /benchmark/io_benchmark.sh
fi

# Run Docker benchmarks
if [ "${BENCHMARK_TYPE}" = "docker" ] || [ "${BENCHMARK_TYPE}" = "all" ]; then
    echo "Running Docker benchmarks..."
    /benchmark/docker_benchmark.sh
fi

# Run ML benchmarks
if [ "${BENCHMARK_TYPE}" = "ml" ] || [ "${BENCHMARK_TYPE}" = "all" ]; then
    echo "Running ML benchmarks..."
    /benchmark/ml_benchmark.sh
fi

echo "Benchmark complete." 