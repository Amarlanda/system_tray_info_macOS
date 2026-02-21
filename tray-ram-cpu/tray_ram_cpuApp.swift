import Cocoa
import IOKit

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var previousCPUTicks: [(user: Double, system: Double, nice: Double, idle: Double)] = []
    var accentColour: NSColor = NSColor.systemOrange

    var detailItems: [String: NSMenuItem] = [:]
    var detailQueue = DispatchQueue(label: "details", qos: .utility)
    var lastComputeTime: Date?
    var isComputing = false

    static let detailKeys = [
        "Temperature", "Fan Speed", "IP Address", "Hostname",
        "Uptime", "OS Installed", "Login Today", "Login This Week", "Last Updated"
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        accentColour = loadAccentColour()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self

        for key in Self.detailKeys {
            let item = NSMenuItem()
            item.isEnabled = false
            item.attributedTitle = formatDetailRow(label: key, value: "...")
            menu.addItem(item)
            detailItems[key] = item
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu

        updateDisplay()
        timer = Timer.scheduledTimer(timeInterval: 3.0, target: self, selector: #selector(updateDisplay), userInfo: nil, repeats: true)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        if isComputing { return }
        if let last = lastComputeTime, Date().timeIntervalSince(last) < 60 { return }
        computeDetails()
    }

    // MARK: - Detail Computation

    func computeDetails() {
        isComputing = true
        detailQueue.async { [weak self] in
            guard let self = self else { return }

            let temp = self.getCPUTemperature()
            let tempStr = temp > 0 ? String(format: "%.0f°C", temp) : "N/A"
            self.updateDetailItem("Temperature", value: tempStr)

            let fanStr = self.getFanSpeeds()
            self.updateDetailItem("Fan Speed", value: fanStr)

            let ip = self.getIPAddress()
            self.updateDetailItem("IP Address", value: ip)

            let hostname = ProcessInfo.processInfo.hostName
            self.updateDetailItem("Hostname", value: hostname)

            let uptime = self.formatUptime(ProcessInfo.processInfo.systemUptime)
            self.updateDetailItem("Uptime", value: uptime)

            let installDate = self.getOSInstallDate()
            self.updateDetailItem("OS Installed", value: installDate)

            let (loginToday, loginWeek) = self.computeLoginTimes()
            self.updateDetailItem("Login Today", value: loginToday)
            self.updateDetailItem("Login This Week", value: loginWeek)

            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm:ss"
            let timeStr = fmt.string(from: Date())
            self.updateDetailItem("Last Updated", value: timeStr)

            DispatchQueue.main.async {
                self.lastComputeTime = Date()
                self.isComputing = false
            }
        }
    }

    func updateDetailItem(_ key: String, value: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let item = self.detailItems[key] else { return }
            item.attributedTitle = self.formatDetailRow(label: key, value: value)
        }
    }

    func formatDetailRow(label: String, value: String) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: boldFont, .foregroundColor: accentColour]
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]

        let paddedLabel = label.padding(toLength: 18, withPad: " ", startingAt: 0)
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: paddedLabel, attributes: labelAttrs))
        result.append(NSAttributedString(string: value, attributes: valueAttrs))
        return result
    }

    // MARK: - Menu Bar Display

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

    // MARK: - Fan Speed (SMC fpe2)

    func getFanSpeeds() -> String {
        var conn: io_connect_t = 0
        let service = IOServiceGetMatchingService(mach_port_t(0), IOServiceMatching("AppleSMC"))
        guard service != 0 else { return "N/A" }
        let r = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        guard r == kIOReturnSuccess else { return "N/A" }
        defer { IOServiceClose(conn) }

        var speeds: [Int] = []
        for i in 0..<4 {
            let key = "F\(i)Ac"
            if let rpm = readSMCFanRPM(conn: conn, key: key), rpm > 0 {
                speeds.append(rpm)
            }
        }

        if speeds.isEmpty { return "N/A" }
        return speeds.map { "\($0)" }.joined(separator: " / ") + " RPM"
    }

    func readSMCFanRPM(conn: io_connect_t, key: String) -> Int? {
        func fcc(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }

        var input = SMCKeyData(); var output = SMCKeyData()
        input.key = fcc(key); input.data8 = 9
        var size = MemoryLayout<SMCKeyData>.size
        guard IOConnectCallStructMethod(conn, 2, &input, size, &output, &size) == kIOReturnSuccess else { return nil }

        input.keyInfo.dataSize = output.keyInfo.dataSize; input.data8 = 5
        guard IOConnectCallStructMethod(conn, 2, &input, size, &output, &size) == kIOReturnSuccess else { return nil }

        let raw = (Int(output.bytes.0) << 8) | Int(output.bytes.1)
        return raw / 4
    }

    // MARK: - IP Address (POSIX getifaddrs)

    func getIPAddress() -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return "N/A" }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let ifa = ptr {
            let name = String(cString: ifa.pointee.ifa_name)
            if let sa = ifa.pointee.ifa_addr,
               (name == "en0" || name == "en1"),
               sa.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                           &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                return String(cString: hostname)
            }
            ptr = ifa.pointee.ifa_next
        }
        return "N/A"
    }

    // MARK: - Uptime

    func formatUptime(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    // MARK: - OS Install Date

    func getOSInstallDate() -> String {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: "/var/db/.AppleSetupDone")
            if let date = attrs[.creationDate] as? Date {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                return fmt.string(from: date)
            }
        } catch {}
        return "N/A"
    }

    // MARK: - Login Times (parsed from /usr/bin/last)

    func computeLoginTimes() -> (today: String, week: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/last")
        process.arguments = [NSUserName()]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() }
        catch { return ("N/A", "N/A") }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return ("N/A", "N/A") }

        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: now)
        let daysSinceMonday = (weekday + 5) % 7
        let weekStart = cal.date(byAdding: .day, value: -daysSinceMonday, to: todayStart)!

        var todaySeconds: TimeInterval = 0
        var weekSeconds: TimeInterval = 0

        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.dateFormat = "EEE MMM d HH:mm"
        let currentYear = cal.component(.year, from: now)

        for line in output.components(separatedBy: "\n") {
            guard line.contains("console") else { continue }
            guard let consoleRange = line.range(of: "console") else { continue }

            let rest = String(line[consoleRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            let tokens = rest.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 4 else { continue }

            let loginStr = "\(tokens[0]) \(tokens[1]) \(tokens[2]) \(tokens[3])"
            guard let parsedLogin = dateFmt.date(from: loginStr) else { continue }

            var loginComps = cal.dateComponents([.month, .day, .hour, .minute], from: parsedLogin)
            loginComps.year = currentYear
            guard var login = cal.date(from: loginComps) else { continue }
            if login > now {
                loginComps.year = currentYear - 1
                login = cal.date(from: loginComps) ?? login
            }

            var logout: Date
            if rest.contains("still logged in") {
                logout = now
            } else {
                // Find duration in parentheses
                guard let openParen = rest.range(of: "("),
                      let closeParen = rest.range(of: ")") else { continue }
                let durationStr = String(rest[openParen.upperBound..<closeParen.lowerBound])
                guard let dur = parseLastDuration(durationStr) else { continue }
                logout = login.addingTimeInterval(dur)
            }

            if logout < weekStart { continue }

            let ts = max(login, todayStart)
            let te = min(logout, now)
            if te > ts { todaySeconds += te.timeIntervalSince(ts) }

            let ws = max(login, weekStart)
            let we = min(logout, now)
            if we > ws { weekSeconds += we.timeIntervalSince(ws) }
        }

        return (formatLoginDuration(todaySeconds), formatLoginDuration(weekSeconds))
    }

    func parseLastDuration(_ str: String) -> TimeInterval? {
        let s = str.trimmingCharacters(in: .whitespaces)
        if s.contains("+") {
            let parts = s.components(separatedBy: "+")
            guard parts.count == 2, let days = Int(parts[0]) else { return nil }
            let tp = parts[1].components(separatedBy: ":")
            guard tp.count == 2, let h = Int(tp[0]), let m = Int(tp[1]) else { return nil }
            return TimeInterval(days * 86400 + h * 3600 + m * 60)
        }
        let tp = s.components(separatedBy: ":")
        if tp.count == 2, let h = Int(tp[0]), let m = Int(tp[1]) {
            return TimeInterval(h * 3600 + m * 60)
        }
        return nil
    }

    func formatLoginDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

// Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
