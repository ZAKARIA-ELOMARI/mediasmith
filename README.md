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
║                               MediaSmith v2.2                                     ║
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
- [🔄 Remote Backup System](#-remote-backup-system)
- [⚙️ Configuration Management](#-configuration-management)
- [🔧 Administrative Commands](#-administrative-commands)
- [📊 Testing](#-testing)
- [🔍 Troubleshooting](#-troubleshooting)
- [📁 Project Structure](#-project-structure)

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
# 1. Install all dependencies automatically
make all

# 2. Generate test files for development
make test

# 3. Run first conversion
./mediasmith.sh sample_file.jpg
```

### Manual Setup (Alternative)
```bash
# 1. Make executable
chmod +x mediasmith.sh

# 2. Install dependencies manually
./scripts/deps_check.sh

# 3. Run first conversion
./mediasmith.sh sample_file.jpg
```

### Dependencies
- **Required**: `ffmpeg`, `imagemagick`, `bash` (4.0+)
- **Linux**: `inotify-tools` for real-time monitoring
- **macOS**: `fswatch` for real-time monitoring (install via Homebrew)

### Build System Commands
| Command | Description |
|---------|-------------|
| `make all` | Install dependencies and build binaries |
| `make build` | Compile the C thread helper only |
| `make scripts-perm` | Make all scripts executable |
| `make deps` | Install system dependencies |
| `make test` | Generate test files |
| `make clean` | Clean build artifacts |

## 🤖 Usage

### Basic Conversion
```bash
# Convert a single file
./mediasmith.sh image.jpg

# Convert a directory recursively
./mediasmith.sh -R /path/to/media/

# Custom output directory and format
./mediasmith.sh -o converted/ -v webm video.mp4
```

### Core Options
| Option | Description |
|--------|-------------|
| `-h` | Show help |
| `-R` | Process recursively |
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

# Run the script in background as Daemon
./mediasmith.sh --watch --daemon
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

### Thread Mode Performance
- **Multi-core utilization**: Automatically detects CPU cores
- **Parallel processing**: Up to 16 concurrent conversions
- **Progress monitoring**: Real-time conversion statistics
- **Optimal for**: Large batch operations (100+ files)

```bash
# High-performance batch processing
./mediasmith.sh -t /large/media/directory/
```

## 🔄 Remote Backup System

MediaSmith includes automated backup functionality with cloud storage support.

### Setup Remote Backup
```bash
# Interactive setup for cloud backup
./scripts/setup_remote_backup.sh

# Test backup configuration
./scripts/test_remote_backup.sh

# Manual backup trigger
./mediasmith.sh --backup
```

### Supported Storage Features
- **rclone** integration for different cloud providers
- **Automatic file synchronization** after conversion
- **Backup status tracking** and logging
- **Date-based backup organization**

### Backup Configuration
The backup system uses the following structure:
- `backup/` - Local backup storage
- `logs/backed_up.log` - Backup history
- `logs/to_backup.log` - Files queued for backup

### Example Backup Workflow
```bash
# Setup remote backup destination
./scripts/setup_remote_backup.sh

# Convert files (automatically queued for backup)
./mediasmith.sh video.mp4

# Check backup status
cat logs/backed_up.log
```

## ⚙️ Configuration Management

MediaSmith provides comprehensive configuration management through interactive and file-based settings.

### Interactive Configuration
```bash
# Launch configuration editor
./mediasmith.sh -c

# Available configuration options:
LOG_LEVEL="INFO"                    # Logging verbosity (DEBUG, INFO, WARN, ERROR)
DEFAULT_OUT_DIR="out"               # Default output directory
WATCH_INTERVAL="2"                  # Polling interval for file monitoring
default_video_ext="mp4"             # Default video output format
default_audio_ext="mp3"             # Default audio output format  
default_image_ext="jpg"             # Default image output format
REMOTE_DIR="backup_remote"          # Remote backup directory path
```

### Configuration Files
- `config/config.cfg` - Main configuration file
- `config/config.example.cfg` - Template with all available options

### Advanced Configuration
```bash
# Custom configuration file
./mediasmith.sh --config /path/to/custom.cfg

# Override specific settings
LOG_LEVEL=DEBUG ./mediasmith.sh file.jpg

# Reset to defaults
./mediasmith.sh --restore-defaults
```

## 🔧 Administrative Commands

MediaSmith provides several administrative commands for system management.

### System Administration
```bash
# Restore default configuration (requires sudo)
sudo ./mediasmith.sh --restore

# Custom log directory
sudo ./mediasmith.sh -l /custom/log/path

# Check dependencies
./scripts/deps_check.sh
```

### Log Management
```bash
# View conversion history
cat logs/converted_files.log

# View backup history
cat logs/backed_up.log

# View general system history
cat logs/history.log

```

## 📊 Testing

### Quick Test
```bash
# Generate test files for development
make test
```

### Test File Generation
The `make test` command executes `populate_test_files.sh` which creates a directory containing:
- Sample images (JPG, PNG, WebP)
- Sample videos (MP4, AVI)
- Sample audio files (MP3, WAV)

## 🔍 Troubleshooting

### Common Issues
- **Thread helper not found**: Run `make build` to compile the C helper
- **Permission denied**: Use `sudo ./mediasmith.sh --restore` to fix permissions
- **Monitoring not working**: Install `inotify-tools` (Linux) or `fswatch` (macOS)
- **Remote backup failing**: Run `./scripts/test_remote_backup.sh` to diagnose

### Debug Mode
```bash
# Enable debug logging
LOG_LEVEL=DEBUG ./mediasmith.sh file.jpg

# View detailed logs
tail -f logs/history.log
```

### Performance Issues
```bash
# Use thread mode for large batches
./mediasmith.sh -t /large/directory/

# Monitor conversion progress
watch -n 1 'ls -la out/'
```

### Configuration Problems
```bash
# Reset to default configuration
./mediasmith.sh --restore-defaults

# Verify configuration
./mediasmith.sh -c
```

---

## 📁 Project Structure
```
mediasmith/
├── mediasmith.sh           # Main script
├── makefile                # Build and setup automation
├── README.md               # Project documentation
├── .gitignore              # Git ignore rules
├── backup/                 # Backup storage
│   └── 2025-06-04/         # Date-based backups
├── bin/                    # Compiled binaries
│   └── thread_converter    # Multi-threaded converter binary
├── config/                 # Configuration files
│   ├── config.cfg          # Main configuration
│   └── config.example.cfg  # Configuration template
├── files/                  # Input directory (watched)
│   ├── sample1.mp4         # Test video file
│   ├── sample2.mkv         # Test video file
│   ├── sample3.wav         # Test audio file
│   ├── sample4.flac        # Test audio file
│   ├── sample5.png         # Test image file
│   └── sample6.jpg         # Test image file
├── lib/                    # Core modules
│   ├── backup.sh           # Backup functionality
│   ├── conversion.sh       # Conversion logic
│   ├── logging.sh          # Logging system
│   ├── utils.sh            # Utilities
│   └── watcher.sh          # File monitoring
├── logs/                   # Log files
│   ├── backed_up.log       # Backup history
│   ├── converted_files.log # Conversion history
│   ├── history.log         # General history
│   └── to_backup.log       # Files to backup
├── out/                    # Output directory
│   ├── audios/             # Converted audio files
│   ├── images/             # Converted image files
│   └── videos/             # Converted video files
├── scripts/                # Utility scripts
│   ├── deps_check.sh       # Dependency checker
│   ├── populate_test_files.sh # Test file generator
│   ├── setup_remote_backup.sh # Remote backup setup
│   └── test_remote_backup.sh  # Backup testing
└── src/                    # Source code
    └── thread_converter.c  # C source for multi-threaded converter
```

## 🎗 License

MIT License - see LICENSE file for details.

---

**MediaSmith v2.2** - Simple, powerful, cross-platform multimedia processing.
