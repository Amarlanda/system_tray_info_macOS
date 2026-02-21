import Cocoa
import IOKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var previousCPUTicks: [(user: Double, system: Double, nice: Double, idle: Double)] = []
    var accentColour: NSColor = NSColor.systemOrange

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        accentColour = loadAccentColour()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu

        updateDisplay()
        timer = Timer.scheduledTimer(timeInterval: 3.0, target: self, selector: #selector(updateDisplay), userInfo: nil, repeats: true)
    }

    func loadAccentColour() -> NSColor {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.config/systemtraymonitor/colour.txt"
        guard let hex = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              hex.count == 6 else { return NSColor.systemOrange }
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        return NSColor(red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
                       green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
                       blue: CGFloat(rgb & 0xFF) / 255.0, alpha: 1.0)
    }

    @objc func updateDisplay() {
        let cpu = getCPUUsage()
        let ram = getRAMUsage()
        let temp = getCPUTemperature()

        guard let button = statusItem.button else { return }

        let boldFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        let accent: [NSAttributedString.Key: Any] = [.font: boldFont, .foregroundColor: accentColour]

        let result = NSMutableAttributedString()

        result.append(NSAttributedString(string: String(format: "CPU %-2.0f%%  ", cpu), attributes: accent))
        result.append(NSAttributedString(string: String(format: "RAM %-2.0f%%", ram), attributes: accent))

        if temp > 0 {
            result.append(NSAttributedString(string: String(format: "  %2.0f\u{00B0}C", temp), attributes: accent))
        }

        button.attributedTitle = result
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { false }

    @objc func quitApp() { NSApplication.shared.terminate(self) }

    // MARK: - CPU Usage (Mach kernel)
    func getCPUUsage() -> Double {
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUs: uint = 0

        let mibKeys: [Int32] = [CTL_HW, HW_NCPU]
        mibKeys.withUnsafeBufferPointer { mib in
            var size: size_t = MemoryLayout<uint>.size
            sysctl(UnsafeMutablePointer<Int32>(mutating: mib.baseAddress), 2, &numCPUs, &size, nil, 0)
        }
        if numCPUs == 0 { numCPUs = 1 }

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCpuInfo)
        guard result == KERN_SUCCESS else { return 0 }

        var ticks: [(user: Double, system: Double, nice: Double, idle: Double)] = []
        for i in 0..<Int(numCPUs) {
            let p = cpuInfo.advanced(by: Int(CPU_STATE_MAX) * i)
            ticks.append((Double(p[Int(CPU_STATE_USER)]), Double(p[Int(CPU_STATE_SYSTEM)]),
                          Double(p[Int(CPU_STATE_NICE)]), Double(p[Int(CPU_STATE_IDLE)])))
        }

        var usage = 0.0
        if previousCPUTicks.count == ticks.count {
            for i in 0..<ticks.count {
                let ud = ticks[i].user - previousCPUTicks[i].user
                let sd = ticks[i].system - previousCPUTicks[i].system
                let nd = ticks[i].nice - previousCPUTicks[i].nice
                let id = ticks[i].idle - previousCPUTicks[i].idle
                let total = ud + sd + nd + id
                if total > 0 { usage += ((ud + sd + nd) / total) * 100.0 }
            }
            usage /= Double(numCPUs)
        }
        previousCPUTicks = ticks

        let size = vm_size_t(MemoryLayout<integer_t>.stride * Int(numCpuInfo))
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        return usage
    }

    // MARK: - RAM Usage (Mach kernel)
    func getRAMUsage() -> Double {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return 0 }

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let page = Double(vm_kernel_page_size)
        let free = (Double(stats.free_count) + Double(stats.external_page_count)) * page
        return ((total - free) / total) * 100.0
    }

    // MARK: - CPU Temperature (SMC)
    struct SMCKeyData {
        struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
        var key: UInt32 = 0
        var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
        var pLimit: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
        var keyInfo = KeyInfo()
        var result: UInt8 = 0; var status: UInt8 = 0; var data8: UInt8 = 0; var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    func getCPUTemperature() -> Double {
        var conn: io_connect_t = 0
        let service = IOServiceGetMatchingService(mach_port_t(0), IOServiceMatching("AppleSMC"))
        guard service != 0 else { return 0 }
        let r = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        guard r == kIOReturnSuccess else { return 0 }
        defer { IOServiceClose(conn) }

        for key in ["TC0P", "TC0D", "TC0E", "TC1C", "TC2C", "TCXC"] {
            if let t = readSMCKey(conn: conn, key: key), t > 0 && t < 120 { return t }
        }
        return 0
    }

    func readSMCKey(conn: io_connect_t, key: String) -> Double? {
        func fcc(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }

        var input = SMCKeyData(); var output = SMCKeyData()
        input.key = fcc(key); input.data8 = 9
        var size = MemoryLayout<SMCKeyData>.size
        guard IOConnectCallStructMethod(conn, 2, &input, size, &output, &size) == kIOReturnSuccess else { return nil }

        input.keyInfo.dataSize = output.keyInfo.dataSize; input.data8 = 5
        guard IOConnectCallStructMethod(conn, 2, &input, size, &output, &size) == kIOReturnSuccess else { return nil }

        return Double(output.bytes.0) + Double(output.bytes.1) / 256.0
    }
}

// Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
