# Tray RAM CPU Monitor

A lightweight macOS menu bar application that monitors and displays real-time CPU usage, RAM usage, and CPU temperature.

## Features

- 🖥️ **CPU Usage Monitoring** - Real-time CPU usage percentage
- 💾 **RAM Usage Monitoring** - Real-time memory consumption percentage  
- 🌡️ **CPU Temperature** - Live CPU temperature in Celsius
- ⚡ **Lightweight** - Minimal system resource usage
- 🔄 **Auto-refresh** - Updates every 2 seconds
- 🎨 **Clean Design** - Unobtrusive menu bar icons with SF Symbols

## Screenshots

The app displays three compact icons in your macOS menu bar:

🖥️ 25%  💾 45%  🌡️ 52°C

## Requirements

- **Operating System**: macOS 12.4 or later
- **Xcode**: 14.0+ (only if building from source)
- **Architecture**: Intel or Apple Silicon (Universal)

## Installation

### Download Release

1. Download the latest release from the Releases page
2. Unzip the downloaded file
3. Drag `tray-ram-cpu.app` to your `/Applications` folder
4. **First launch**: Right-click the app → Select **Open** (don't double-click)
5. Grant necessary system permissions when prompted

### Build from Source

1. Clone the repository
2. Open `tray-ram-cpu.xcodeproj` in Xcode
3. Build and run (⌘R)

## Usage

### Launching the App

The app runs as a menu bar utility with no dock icon:

1. **Launch** the application from your Applications folder
2. Three icons will appear in your menu bar showing:
   - 🖥️ CPU usage percentage
   - 💾 RAM usage percentage
   - 🌡️ CPU temperature in Celsius

### Interacting with the App

Click on any icon to open a menu with options:

- **Refresh** - Manually update statistics immediately
- **Quit** - Exit the application

### Automatic Updates

- Stats refresh automatically every **2 seconds**
- No user interaction required for continuous monitoring
- Icons update in real-time to reflect current system state

### Menu Bar Display

Each icon shows:

- **CPU**: Processor usage (0-100%)
- **RAM**: Memory usage (0-100%)
- **Temperature**: CPU temperature in Celsius (e.g., 45°C)

## Permissions

The app requires the following system permissions to function properly:

### Required Permissions

1. **System Process Information**
   - Uses the `ps` command to gather process data
   - Required for accurate CPU and memory statistics

2. **Temperature Sensor Access**
   - Uses the `powermetrics` command to read CPU temperature
   - May request administrator privileges on first run
   - Falls back to estimation based on CPU usage if denied

3. **System Statistics Access**
   - Uses mach kernel APIs for real-time monitoring
   - No explicit permission prompt needed

### Why Sandboxing is Disabled

The app has **sandboxing disabled** to enable:

- Execution of system commands
- Direct access to hardware statistics
- Real-time system monitoring capabilities

This is necessary for a system monitoring utility.

### First Launch

On first launch, you may see:

- Security warning: Right-click → **Open** to bypass
- Permission prompts for system access: Click **Allow**

## Technical Details

**Built with:**

- Swift 5.0
- Cocoa (AppKit)
- Native macOS APIs

**Monitoring Methods:**

- **CPU**: `host_processor_info` via mach kernel API
- **RAM**: `host_statistics64` for VM statistics  
- **Temperature**: `powermetrics` with estimation fallback

## License

MIT License

## Author

Created by Mihai

---

**Disclaimer**: This app is not affiliated with or endorsed by Apple Inc.
