<div align="center">
<pre>
╔═══════════════════════════════════════════════════════════════════════════════════╗
║                                                                                   ║
║   ███╗   ███╗███████╗██████╗ ██╗ █████╗ ███████╗███╗   ███╗██╗████████╗██╗  ██╗   ║
║   ████╗ ████║██╔════╝██╔══██╗██║██╔══██╗██╔════╝████╗ ████║██║╚══██╔══╝██║  ██║   ║
║   ██╔████╔██║█████╗  ██║  ██║██║███████║███████╗██╔████╔██║██║   ██║   ███████║   ║
║   ██║╚██╔╝██║██╔══╝  ██║  ██║██║██╔══██║╚════██║██║╚██╔╝██║██║   ██║   ██╔══██║   ║
║   ██║ ╚═╝ ██║███████╗██████╔╝██║██║  ██║███████║██║ ╚═╝ ██║██║   ██║   ██║  ██║   ║
║   ╚═╝     ╚═╝╚══════╝╚═════╝ ╚═╝╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝   ╚═╝   ╚═╝  ╚═╝   ║
║                                                                                   ║
║                              MediaSmith v2.2                                     ║
╚═══════════════════════════════════════════════════════════════════════════════════╝
</pre>
</div>

<p align="center">
	<em><code>❯ Advanced multimedia processing with multi-mode execution and real-time monitoring</code></em>
</p>

<p align="center">
	<img src="https://img.shields.io/badge/version-2.2-blue.svg" alt="version">
	<img src="https://img.shields.io/badge/license-MIT-green.svg" alt="license">
	<img src="https://img.shields.io/badge/shell-bash-orange.svg" alt="shell">
	<img src="https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey.svg" alt="platform">
</p>

## 🔗 Table of Contents
- [📍 Overview](#-overview)
- [🚀 Getting Started](#-getting-started)
- [🤖 Usage](#-usage)
- [⚡ Real-time Monitoring](#-real-time-monitoring)
- [🔧 Execution Modes](#-execution-modes)
- [📊 Testing](#-testing)

---

## 📍 Overview

**MediaSmith** is a powerful multimedia processing script that handles video, audio, and image conversions with support for multiple execution modes, real-time monitoring, and automated processing workflows.

### Core Philosophy
- **Cross-Platform**: Works on Linux and macOS with optimized monitoring for each platform
- **Multiple Execution Modes**: Choose the right mode for your performance needs
- **Real-time Processing**: Automatic file detection and processing with `inotifywait` (Linux) or `fswatch` (macOS)
- **Simple Configuration**: Easy setup with sensible defaults

## 🚀 Getting Started

### Quick Setup
```bash
# 1. Make executable
chmod +x mediasmith.sh

# 2. Install dependencies
./scripts/deps_check.sh

# 3. Test the system
./scripts/system_info.sh

# 4. Run first conversion
./mediasmith.sh sample_file.jpg
```

### Dependencies
- **Required**: `ffmpeg`, `imagemagick`, `bash` (4.0+)
- **Linux**: `inotify-tools` for real-time monitoring
- **macOS**: `fswatch` for real-time monitoring (install via Homebrew)

## 🤖 Usage

### Basic Conversion
```bash
# Convert a single file
./mediasmith.sh image.jpg

# Convert a directory recursively
./mediasmith.sh -r /path/to/media/

# Custom output directory and format
./mediasmith.sh -o converted/ -v webm video.mp4
```

### Core Options
| Option | Description |
|--------|-------------|
| `-h` | Show help |
| `-r` | Process recursively |
| `-o <dir>` | Output directory |
| `-v <ext>` | Video format (mp4, webm, avi) |
| `-a <ext>` | Audio format (mp3, flac, wav) |
| `-i <ext>` | Image format (jpg, png, webp) |

## ⚡ Real-time Monitoring

MediaSmith supports real-time file monitoring on both Linux and macOS platforms.

### Linux (inotify)
```bash
# Install inotify-tools
sudo apt-get install inotify-tools  # Ubuntu/Debian
sudo yum install inotify-tools      # CentOS/RHEL

# Start monitoring
./mediasmith.sh --watch
```

### macOS (fswatch)
```bash
# Install fswatch via Homebrew
brew install fswatch

# Start monitoring
./mediasmith.sh --watch
```

### How it Works
1. **Automatic Detection**: MediaSmith detects available monitoring tools
2. **Fallback Mode**: If no monitoring tools are available, uses polling
3. **Instant Processing**: New files are processed immediately when detected
4. **Background Operation**: Monitoring runs in the background

### Monitoring Configuration
```bash
# Configure monitoring settings
./mediasmith.sh -c

# Key settings:
# - WATCH_DIR: Directory to monitor (default: ./files/)
# - WATCH_INTERVAL: Polling interval for fallback mode
# - AUTO_PROCESS: Enable/disable automatic processing
```

### Example Workflow
```bash
# Start monitoring in background
./mediasmith.sh --watch &

# Copy files to watch directory
cp *.jpg files/
# Files are automatically converted!

# Check results
ls out/
```

## 🔧 Execution Modes

Choose the execution mode that fits your needs:

### Normal Mode (Default)
```bash
./mediasmith.sh file.jpg
```
- **Best for**: Single files, interactive use
- **Characteristics**: Synchronous, full terminal output

### Fork Mode (`-f`)
```bash
./mediasmith.sh -f directory/ -r
```
- **Best for**: Background batch processing
- **Characteristics**: Non-blocking, runs in background

### Subshell Mode (`-s`)
```bash
./mediasmith.sh -s file.mp4
```
- **Best for**: Isolated processing, testing
- **Characteristics**: Process isolation, protected environment

### Thread Mode (`-t`)
```bash
./mediasmith.sh -t directory/
```
- **Best for**: High-performance batch operations
- **Characteristics**: Multi-threaded C helper, parallel processing

## 📊 Testing

### Quick Test
```bash
# Run comprehensive tests
./scripts/automated_tests.sh

# Check system compatibility
./scripts/system_info.sh

# Performance benchmarking
./scripts/benchmark.sh
```

### Test Results
✅ **All execution modes tested and working**  
✅ **Cross-platform monitoring verified**  
✅ **Performance benchmarks completed**  
✅ **Error handling validated**  

---

## 📁 Project Structure
```
mediasmith/
├── mediasmith.sh           # Main script
├── lib/                    # Core modules
│   ├── conversion.sh       # Conversion logic
│   ├── logging.sh          # Logging system
│   ├── watcher.sh          # File monitoring
│   └── utils.sh            # Utilities
├── scripts/                # Utility scripts
│   ├── system_info.sh      # System diagnostics
│   ├── automated_tests.sh  # Test suite
│   ├── benchmark.sh        # Performance tests
│   └── setup.sh            # Setup script
├── config/                 # Configuration
├── files/                  # Input directory (watched)
└── out/                    # Output directory
```

## 🎗 License

MIT License - see LICENSE file for details.

---

**MediaSmith v2.2** - Simple, powerful, cross-platform multimedia processing.
