#!/bin/bash
#
# Docker Filesystem Benchmark - Results Analysis
# This script parses benchmark results and generates visualizations

set -e

echo "=== Docker Filesystem Benchmark - Analysis ==="

# Directory paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$BASE_DIR/results"
PROCESSED_DIR="$RESULTS_DIR/processed"
VIZ_DIR="$RESULTS_DIR/visualizations"

# Activate the virtual environment
echo "Activating Python virtual environment..."
source "$SCRIPT_DIR/activate_venv.sh" || {
    echo "ERROR: Failed to activate virtual environment."
    echo "Please run setup.sh first to create the virtual environment."
    exit 1
}

# Ensure directories exist
mkdir -p "$PROCESSED_DIR"
mkdir -p "$VIZ_DIR"

# Create a Python script to parse and visualize results
cat > "$SCRIPT_DIR/analyze.py" << 'EOF'
#!/usr/bin/env python3
"""
Docker Filesystem Benchmark - Result Analysis Script
This script parses benchmark outputs and generates visualizations
"""

import os
import glob
import re
import json
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime

# Set plotting style
plt.style.use('ggplot')
sns.set_theme(style="whitegrid")

class BenchmarkAnalyzer:
    def __init__(self, results_dir, processed_dir, viz_dir):
        self.results_dir = results_dir
        self.processed_dir = processed_dir
        self.viz_dir = viz_dir
        self.data = {
            'fio': [],
            'bonnie': [],
            'docker': [],
            'ml': []
        }
        
        # Ensure output directories exist
        os.makedirs(self.processed_dir, exist_ok=True)
        os.makedirs(self.viz_dir, exist_ok=True)
    
    def process_results(self):
        """Process all raw results"""
        print("Processing benchmark results...")
        
        # Find all result directories
        result_dirs = glob.glob(os.path.join(self.results_dir, 'raw', '*'))
        
        for result_dir in result_dirs:
            # Extract device type, filesystem, and timestamp from directory name
            dir_name = os.path.basename(result_dir)
            parts = dir_name.split('_')
            
            if len(parts) < 3:
                print(f"Skipping directory with invalid name format: {dir_name}")
                continue
            
            device_name = parts[0]
            fs_type = parts[1]
            timestamp = '_'.join(parts[2:])
            
            # Process FIO results
            self.process_fio_results(result_dir, device_name, fs_type, timestamp)
            
            # Process Bonnie++ results
            self.process_bonnie_results(result_dir, device_name, fs_type, timestamp)
            
            # Process Docker benchmark results
            self.process_docker_results(result_dir, device_name, fs_type, timestamp)
            
            # Process ML benchmark results
            self.process_ml_results(result_dir, device_name, fs_type, timestamp)
        
        # Convert results to DataFrames
        self.convert_to_dataframes()
        
        # Save processed results
        self.save_processed_results()
        
        print("Results processing complete.")
    
    def process_fio_results(self, result_dir, device_name, fs_type, timestamp):
        """Process FIO benchmark results"""
        fio_files = {
            'seqread': os.path.join(result_dir, 'fio_seqread.txt'),
            'seqwrite': os.path.join(result_dir, 'fio_seqwrite.txt'),
            'randread': os.path.join(result_dir, 'fio_randread.txt'),
            'randwrite': os.path.join(result_dir, 'fio_randwrite.txt')
        }
        
        for test_type, file_path in fio_files.items():
            if not os.path.exists(file_path):
                print(f"File not found: {file_path}")
                continue
            
            try:
                with open(file_path, 'r') as f:
                    content = f.read()
                
                # Extract IOPS, bandwidth, and latency
                iops_match = re.search(r'IOPS=(\d+[\.\d+]*[kM]?)', content)
                bw_match = re.search(r'BW=(\d+[\.\d+]*[kMG]?B/s)', content)
                lat_match = re.search(r'lat \([^)]+\): min=(\d+), max=(\d+), avg=(\d+\.\d+)', content)
                
                iops = iops_match.group(1) if iops_match else 'N/A'
                bw = bw_match.group(1) if bw_match else 'N/A'
                
                if lat_match:
                    lat_min = lat_match.group(1)
                    lat_max = lat_match.group(2)
                    lat_avg = lat_match.group(3)
                else:
                    lat_min = lat_max = lat_avg = 'N/A'
                
                # Convert to numeric values
                try:
                    iops_value = self.parse_value(iops)
                    bw_value = self.parse_value(bw.split('B/s')[0])
                    lat_min_value = float(lat_min)
                    lat_max_value = float(lat_max)
                    lat_avg_value = float(lat_avg)
                except:
                    iops_value = bw_value = lat_min_value = lat_max_value = lat_avg_value = np.nan
                
                # Add to results
                self.data['fio'].append({
                    'device': device_name,
                    'filesystem': fs_type,
                    'timestamp': timestamp,
                    'test_type': test_type,
                    'iops': iops,
                    'iops_value': iops_value,
                    'bandwidth': bw,
                    'bandwidth_value': bw_value,
                    'latency_min': lat_min,
                    'latency_min_value': lat_min_value,
                    'latency_max': lat_max,
                    'latency_max_value': lat_max_value,
                    'latency_avg': lat_avg,
                    'latency_avg_value': lat_avg_value
                })
            
            except Exception as e:
                print(f"Error processing FIO file {file_path}: {str(e)}")
    
    def process_bonnie_results(self, result_dir, device_name, fs_type, timestamp):
        """Process Bonnie++ benchmark results"""
        bonnie_file = os.path.join(result_dir, 'bonnie.txt')
        
        if not os.path.exists(bonnie_file):
            print(f"Bonnie++ results not found: {bonnie_file}")
            return
        
        try:
            with open(bonnie_file, 'r') as f:
                content = f.read()
            
            # Extract sequential output (write)
            seq_out_match = re.search(r'Sequential output.*?per char.*?(\d+).*?Block.*?(\d+).*?Rewrite.*?(\d+)', 
                                    content, re.DOTALL)
            
            # Extract sequential input (read)
            seq_in_match = re.search(r'Sequential input.*?per char.*?(\d+).*?Block.*?(\d+)', 
                                   content, re.DOTALL)
            
            # Extract random seeks
            rand_seek_match = re.search(r'Seek.*?(\d+)/(\d+)', content)
            
            if seq_out_match:
                seq_out_per_char = seq_out_match.group(1)
                seq_out_block = seq_out_match.group(2)
                seq_out_rewrite = seq_out_match.group(3)
            else:
                seq_out_per_char = seq_out_block = seq_out_rewrite = 'N/A'
            
            if seq_in_match:
                seq_in_per_char = seq_in_match.group(1)
                seq_in_block = seq_in_match.group(2)
            else:
                seq_in_per_char = seq_in_block = 'N/A'
            
            if rand_seek_match:
                rand_seek = rand_seek_match.group(1)
                rand_seek_pct = rand_seek_match.group(2)
            else:
                rand_seek = rand_seek_pct = 'N/A'
            
            # Convert to numeric values
            try:
                seq_out_per_char_value = float(seq_out_per_char)
                seq_out_block_value = float(seq_out_block)
                seq_out_rewrite_value = float(seq_out_rewrite)
                seq_in_per_char_value = float(seq_in_per_char)
                seq_in_block_value = float(seq_in_block)
                rand_seek_value = float(rand_seek)
            except:
                seq_out_per_char_value = seq_out_block_value = seq_out_rewrite_value = np.nan
                seq_in_per_char_value = seq_in_block_value = rand_seek_value = np.nan
            
            # Add to results
            self.data['bonnie'].append({
                'device': device_name,
                'filesystem': fs_type,
                'timestamp': timestamp,
                'seq_out_per_char': seq_out_per_char,
                'seq_out_per_char_value': seq_out_per_char_value,
                'seq_out_block': seq_out_block,
                'seq_out_block_value': seq_out_block_value,
                'seq_out_rewrite': seq_out_rewrite,
                'seq_out_rewrite_value': seq_out_rewrite_value,
                'seq_in_per_char': seq_in_per_char,
                'seq_in_per_char_value': seq_in_per_char_value,
                'seq_in_block': seq_in_block,
                'seq_in_block_value': seq_in_block_value,
                'rand_seek': rand_seek,
                'rand_seek_value': rand_seek_value
            })
        
        except Exception as e:
            print(f"Error processing Bonnie++ file {bonnie_file}: {str(e)}")
    
    def process_docker_results(self, result_dir, device_name, fs_type, timestamp):
        """Process Docker benchmark results"""
        docker_files = {
            'pull': os.path.join(result_dir, 'docker_pull_time.txt'),
            'build': os.path.join(result_dir, 'docker_build_time.txt'),
            'start_stop': os.path.join(result_dir, 'docker_start_stop_time.txt')
        }
        
        docker_results = {
            'device': device_name,
            'filesystem': fs_type,
            'timestamp': timestamp
        }
        
        for test_type, file_path in docker_files.items():
            if not os.path.exists(file_path):
                print(f"Docker results not found: {file_path}")
                continue
            
            try:
                with open(file_path, 'r') as f:
                    content = f.read()
                
                # Extract real time using regex
                if test_type == 'start_stop':
                    # For start_stop, calculate average time
                    real_times = re.findall(r'real\s+(\d+)m(\d+\.\d+)s', content)
                    times_sec = [int(m) * 60 + float(s) for m, s in real_times]
                    avg_time = sum(times_sec) / len(times_sec) if times_sec else 0
                    docker_results[f'{test_type}_time'] = f"{avg_time:.2f}s"
                    docker_results[f'{test_type}_time_value'] = avg_time
                else:
                    # For pull and build
                    real_match = re.search(r'real\s+(\d+)m(\d+\.\d+)s', content)
                    if real_match:
                        minutes = int(real_match.group(1))
                        seconds = float(real_match.group(2))
                        total_time = minutes * 60 + seconds
                        docker_results[f'{test_type}_time'] = f"{minutes}m{seconds:.2f}s"
                        docker_results[f'{test_type}_time_value'] = total_time
                    else:
                        docker_results[f'{test_type}_time'] = 'N/A'
                        docker_results[f'{test_type}_time_value'] = np.nan
            
            except Exception as e:
                print(f"Error processing Docker file {file_path}: {str(e)}")
                docker_results[f'{test_type}_time'] = 'N/A'
                docker_results[f'{test_type}_time_value'] = np.nan
        
        self.data['docker'].append(docker_results)
    
    def process_ml_results(self, result_dir, device_name, fs_type, timestamp):
        """Process ML benchmark results"""
        ml_file = os.path.join(result_dir, 'ml_benchmark.txt')
        
        if not os.path.exists(ml_file):
            print(f"ML results not found: {ml_file}")
            return
        
        try:
            with open(ml_file, 'r') as f:
                content = f.read()
            
            # Extract save and load times
            save_match = re.search(r'Model save time: (\d+\.\d+) seconds', content)
            load_match = re.search(r'Model load time: (\d+\.\d+) seconds', content)
            
            if save_match:
                save_time = save_match.group(1)
                save_time_value = float(save_time)
            else:
                save_time = 'N/A'
                save_time_value = np.nan
            
            if load_match:
                load_time = load_match.group(1)
                load_time_value = float(load_time)
            else:
                load_time = 'N/A'
                load_time_value = np.nan
            
            # Add to results
            self.data['ml'].append({
                'device': device_name,
                'filesystem': fs_type,
                'timestamp': timestamp,
                'save_time': save_time,
                'save_time_value': save_time_value,
                'load_time': load_time,
                'load_time_value': load_time_value
            })
        
        except Exception as e:
            print(f"Error processing ML file {ml_file}: {str(e)}")
    
    def convert_to_dataframes(self):
        """Convert result lists to pandas DataFrames"""
        for key in self.data:
            if self.data[key]:
                self.data[key] = pd.DataFrame(self.data[key])
    
    def save_processed_results(self):
        """Save processed results to CSV files"""
        for key, df in self.data.items():
            if isinstance(df, pd.DataFrame) and not df.empty:
                output_file = os.path.join(self.processed_dir, f'{key}_results.csv')
                df.to_csv(output_file, index=False)
                print(f"Saved processed {key} results to {output_file}")
    
    def generate_visualizations(self):
        """Generate visualizations from processed results"""
        print("Generating visualizations...")
        
        # For each benchmark type, generate appropriate visualizations
        if isinstance(self.data['fio'], pd.DataFrame) and not self.data['fio'].empty:
            self.visualize_fio_results()
        
        if isinstance(self.data['bonnie'], pd.DataFrame) and not self.data['bonnie'].empty:
            self.visualize_bonnie_results()
        
        if isinstance(self.data['docker'], pd.DataFrame) and not self.data['docker'].empty:
            self.visualize_docker_results()
        
        if isinstance(self.data['ml'], pd.DataFrame) and not self.data['ml'].empty:
            self.visualize_ml_results()
        
        # Generate summary comparisons
        self.generate_summary_visualizations()
        
        print("Visualization generation complete.")
    
    def visualize_fio_results(self):
        """Generate visualizations for FIO results"""
        df = self.data['fio']
        
        # IOPS Comparison
        plt.figure(figsize=(12, 8))
        sns.barplot(data=df, x='filesystem', y='iops_value', hue='test_type')
        plt.title('IOPS Comparison by Filesystem and Test Type')
        plt.xlabel('Filesystem')
        plt.ylabel('IOPS')
        plt.tight_layout()
        plt.savefig(os.path.join(self.viz_dir, 'fio_iops_comparison.png'))
        
        # Bandwidth Comparison
        plt.figure(figsize=(12, 8))
        sns.barplot(data=df, x='filesystem', y='bandwidth_value', hue='test_type')
        plt.title('Bandwidth Comparison by Filesystem and Test Type')
        plt.xlabel('Filesystem')
        plt.ylabel('Bandwidth (MB/s)')
        plt.tight_layout()
        plt.savefig(os.path.join(self.viz_dir, 'fio_bandwidth_comparison.png'))
        
        # Latency Comparison
        plt.figure(figsize=(12, 8))
        sns.barplot(data=df, x='filesystem', y='latency_avg_value', hue='test_type')
        plt.title('Average Latency Comparison by Filesystem and Test Type')
        plt.xlabel('Filesystem')
        plt.ylabel('Latency (μs)')
        plt.tight_layout()
        plt.savefig(os.path.join(self.viz_dir, 'fio_latency_comparison.png'))
        
        # Device-based comparisons
        for device in df['device'].unique():
            device_df = df[df['device'] == device]
            
            # IOPS by Device
            plt.figure(figsize=(12, 8))
            sns.barplot(data=device_df, x='filesystem', y='iops_value', hue='test_type')
            plt.title(f'IOPS Comparison for {device} by Filesystem and Test Type')
            plt.xlabel('Filesystem')
            plt.ylabel('IOPS')
            plt.tight_layout()
            plt.savefig(os.path.join(self.viz_dir, f'fio_iops_comparison_{device}.png'))
    
    def visualize_bonnie_results(self):
        """Generate visualizations for Bonnie++ results"""
        df = self.data['bonnie']
        
        # Sequential Output Comparison
        plt.figure(figsize=(12, 8))
        plot_data = pd.melt(
            df, 
            id_vars=['device', 'filesystem'], 
            value_vars=['seq_out_block_value', 'seq_out_rewrite_value'],
            var_name='test_type', 
            value_name='throughput'
        )
        plot_data['test_type'] = plot_data['test_type'].map({
            'seq_out_block_value': 'Block Write',
            'seq_out_rewrite_value': 'Rewrite'
        })
        sns.barplot(data=plot_data, x='filesystem', y='throughput', hue='test_type')
        plt.title('Sequential Output Throughput Comparison by Filesystem')
        plt.xlabel('Filesystem')
        plt.ylabel('Throughput (KB/s)')
        plt.tight_layout()
        plt.savefig(os.path.join(self.viz_dir, 'bonnie_seq_out_comparison.png'))
        
        # Sequential Input Comparison
        plt.figure(figsize=(12, 8))
        sns.barplot(data=df, x='filesystem', y='seq_in_block_value')
        plt.title('Sequential Block Input Throughput Comparison by Filesystem')
        plt.xlabel('Filesystem')
        plt.ylabel('Throughput (KB/s)')
        plt.tight_layout()
        plt.savefig(os.path.join(self.viz_dir, 'bonnie_seq_in_comparison.png'))
        
        # Random Seek Comparison
        plt.figure(figsize=(12, 8))
        sns.barplot(data=df, x='filesystem', y='rand_seek_value')
        plt.title('Random Seek Performance Comparison by Filesystem')
        plt.xlabel('Filesystem')
        plt.ylabel('Seeks per Second')
        plt.tight_layout()
        plt.savefig(os.path.join(self.viz_dir, 'bonnie_rand_seek_comparison.png'))
    
    def visualize_docker_results(self):
        """Generate visualizations for Docker benchmark results"""
        df = self.data['docker']
        
        # Prepare data for plotting
        plot_data = pd.melt(
            df, 
            id_vars=['device', 'filesystem'], 
            value_vars=['pull_time_value', 'build_time_value', 'start_stop_time_value'],
            var_name='test_type', 
            value_name='time'
        )
        plot_data['test_type'] = plot_data['test_type'].map({
            'pull_time_value': 'Image Pull',
            'build_time_value': 'Image Build',
            'start_stop_time_value': 'Container Start/Stop'
        })
        
        # Docker Operations Time Comparison
        plt.figure(figsize=(12, 8))
        sns.barplot(data=plot_data, x='filesystem', y='time', hue='test_type')
        plt.title('Docker Operations Time Comparison by Filesystem')
        plt.xlabel('Filesystem')
        plt.ylabel('Time (seconds)')
        plt.tight_layout()
        plt.savefig(os.path.join(self.viz_dir, 'docker_time_comparison.png'))
        
        # Per-Device Docker Performance
        for device in df['device'].unique():
            device_df = df[df['device'] == device]
            device_plot_data = pd.melt(
                device_df, 
                id_vars=['device', 'filesystem'], 
                value_vars=['pull_time_value', 'build_time_value', 'start_stop_time_value'],
                var_name='test_type', 
                value_name='time'
            )
            device_plot_data['test_type'] = device_plot_data['test_type'].map({
                'pull_time_value': 'Image Pull',
                'build_time_value': 'Image Build',
                'start_stop_time_value': 'Container Start/Stop'
            })
            
            plt.figure(figsize=(12, 8))
            sns.barplot(data=device_plot_data, x='filesystem', y='time', hue='test_type')
            plt.title(f'Docker Operations Time Comparison for {device} by Filesystem')
            plt.xlabel('Filesystem')
            plt.ylabel('Time (seconds)')
            plt.tight_layout()
            plt.savefig(os.path.join(self.viz_dir, f'docker_time_comparison_{device}.png'))
    
    def visualize_ml_results(self):
        """Generate visualizations for ML benchmark results"""
        df = self.data['ml']
        
        # Prepare data for plotting
        plot_data = pd.melt(
            df, 
            id_vars=['device', 'filesystem'], 
            value_vars=['save_time_value', 'load_time_value'],
            var_name='operation', 
            value_name='time'
        )
        plot_data['operation'] = plot_data['operation'].map({
            'save_time_value': 'Model Save',
            'load_time_value': 'Model Load'
        })
        
        # ML Operations Time Comparison
        plt.figure(figsize=(12, 8))
        sns.barplot(data=plot_data, x='filesystem', y='time', hue='operation')
        plt.title('ML Model I/O Time Comparison by Filesystem')
        plt.xlabel('Filesystem')
        plt.ylabel('Time (seconds)')
        plt.tight_layout()
        plt.savefig(os.path.join(self.viz_dir, 'ml_time_comparison.png'))
        
        # Per-Device ML Performance
        for device in df['device'].unique():
            device_df = df[df['device'] == device]
            device_plot_data = pd.melt(
                device_df, 
                id_vars=['device', 'filesystem'], 
                value_vars=['save_time_value', 'load_time_value'],
                var_name='operation', 
                value_name='time'
            )
            device_plot_data['operation'] = device_plot_data['operation'].map({
                'save_time_value': 'Model Save',
                'load_time_value': 'Model Load'
            })
            
            plt.figure(figsize=(12, 8))
            sns.barplot(data=device_plot_data, x='filesystem', y='time', hue='operation')
            plt.title(f'ML Model I/O Time Comparison for {device} by Filesystem')
            plt.xlabel('Filesystem')
            plt.ylabel('Time (seconds)')
            plt.tight_layout()
            plt.savefig(os.path.join(self.viz_dir, f'ml_time_comparison_{device}.png'))
    
    def generate_summary_visualizations(self):
        """Generate summary visualizations comparing all benchmarks"""
        # Create a comprehensive heatmap if we have data from all benchmarks
        if all(isinstance(self.data[key], pd.DataFrame) and not self.data[key].empty 
               for key in ['fio', 'bonnie', 'docker', 'ml']):
            
            # Normalize each metric to 0-1 range for comparison
            metrics = {}
            
            # FIO - Random read IOPS
            if 'fio' in self.data and not self.data['fio'].empty:
                rand_read = self.data['fio'][self.data['fio']['test_type'] == 'randread']
                if not rand_read.empty:
                    metrics['rand_read_iops'] = self.normalize_series(rand_read.groupby('filesystem')['iops_value'].mean())
            
            # FIO - Random write IOPS
            if 'fio' in self.data and not self.data['fio'].empty:
                rand_write = self.data['fio'][self.data['fio']['test_type'] == 'randwrite']
                if not rand_write.empty:
                    metrics['rand_write_iops'] = self.normalize_series(rand_write.groupby('filesystem')['iops_value'].mean())
            
            # Bonnie - Sequential read
            if 'bonnie' in self.data and not self.data['bonnie'].empty:
                metrics['seq_read'] = self.normalize_series(self.data['bonnie'].groupby('filesystem')['seq_in_block_value'].mean())
            
            # Bonnie - Sequential write
            if 'bonnie' in self.data and not self.data['bonnie'].empty:
                metrics['seq_write'] = self.normalize_series(self.data['bonnie'].groupby('filesystem')['seq_out_block_value'].mean())
            
            # Docker - Image build (inverted since lower is better)
            if 'docker' in self.data and not self.data['docker'].empty:
                metrics['docker_build'] = 1 - self.normalize_series(self.data['docker'].groupby('filesystem')['build_time_value'].mean())
            
            # ML - Model save (inverted since lower is better)
            if 'ml' in self.data and not self.data['ml'].empty:
                metrics['ml_save'] = 1 - self.normalize_series(self.data['ml'].groupby('filesystem')['save_time_value'].mean())
            
            # Create a DataFrame for the heatmap
            heatmap_data = pd.DataFrame(metrics)
            
            # Generate heatmap
            plt.figure(figsize=(12, 8))
            sns.heatmap(heatmap_data, annot=True, cmap='RdYlGn', linewidths=.5, vmin=0, vmax=1)
            plt.title('Filesystem Performance Comparison (Normalized Scores)')
            plt.tight_layout()
            plt.savefig(os.path.join(self.viz_dir, 'fs_performance_heatmap.png'))
            
            # Save the summary as CSV
            heatmap_data.to_csv(os.path.join(self.processed_dir, 'performance_summary.csv'))
    
    def normalize_series(self, series):
        """Normalize a pandas Series to 0-1 range"""
        min_val = series.min()
        max_val = series.max()
        if min_val == max_val:
            return pd.Series(0.5, index=series.index)
        return (series - min_val) / (max_val - min_val)
    
    def parse_value(self, value_str):
        """Parse string values with units like 4k, 1M, etc."""
        value_str = str(value_str).strip()
        
        # Extract numeric part and unit
        match = re.match(r'(\d+(?:\.\d+)?)\s*([kMGT]?)', value_str)
        if not match:
            return np.nan
        
        value, unit = match.groups()
        value = float(value)
        
        # Convert based on unit
        if unit == 'k':
            value *= 1e3
        elif unit == 'M':
            value *= 1e6
        elif unit == 'G':
            value *= 1e9
        elif unit == 'T':
            value *= 1e12
        
        return value


def main():
    """Main function to run analysis"""
    import sys
    
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <results_dir> <processed_dir> <viz_dir>")
        sys.exit(1)
    
    results_dir = sys.argv[1]
    processed_dir = sys.argv[2]
    viz_dir = sys.argv[3]
    
    analyzer = BenchmarkAnalyzer(results_dir, processed_dir, viz_dir)
    analyzer.process_results()
    analyzer.generate_visualizations()
    
    print("Analysis complete!")


if __name__ == "__main__":
    main()
EOF

# Make the Python script executable
chmod +x "$SCRIPT_DIR/analyze.py"

# Run the analysis script
echo "Running analysis script with the virtual environment..."
python "$SCRIPT_DIR/analyze.py" "$RESULTS_DIR" "$PROCESSED_DIR" "$VIZ_DIR"

# Deactivate the virtual environment when done
deactivate

echo "=== Analysis Complete! ==="
echo "Results have been processed and visualized."
echo "Processed data: $PROCESSED_DIR"
echo "Visualizations: $VIZ_DIR" 