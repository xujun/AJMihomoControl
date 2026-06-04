import Foundation

/// 管理 mihomo 进程生命周期
class MihomoManager: ObservableObject {
    @Published var isRunning = false
    @Published var pid: Int32 = 0
    @Published var lastOutput: String = ""
    @Published var managedByApp = false // true = 本应用启动的, false = 已存在的

    private var process: Process?

    init() {
        updateStatus()
    }

    // MARK: - 生命周期

    func start() {
        guard !isRunning else { return }

        let config = AppConfig.load()

        guard FileManager.default.fileExists(atPath: config.resolvedMihomoBinaryPath) else {
            lastOutput = "未找到 mihomo：\(config.resolvedMihomoBinaryPath)\n请在设置中指定正确路径。"
            updateStatus()
            return
        }

        guard FileManager.default.fileExists(atPath: config.resolvedMihomoConfigPath) else {
            lastOutput = "配置文件不存在：\(config.resolvedMihomoConfigPath)\n请先创建配置文件。"
            updateStatus()
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.resolvedMihomoBinaryPath)
        process.arguments = ["-d", config.resolvedMihomoHome, "-f", config.resolvedMihomoConfigPath]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            self.process = process
            managedByApp = true

            // 异步读取输出
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errData, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    self?.lastOutput = output + error
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.updateStatus()
            }
        } catch {
            lastOutput = "启动失败：\(error.localizedDescription)"
            updateStatus()
        }
    }

    func stop() {
        // 先尝试终止自己管理的进程
        if let process = process, process.isRunning {
            process.terminate()
            self.process = nil
        }
        // 如果 PID 已知，也发送 SIGTERM
        if pid > 0 {
            kill(pid, SIGTERM)
        }
        pid = 0
        isRunning = false
        managedByApp = false
    }

    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.start()
        }
    }

    // MARK: - 状态检测

    func updateStatus() {
        let config = AppConfig.load()

        // 方法 1：通过 PID 文件
        let pidFile = (config.resolvedMihomoHome as NSString).appendingPathComponent("mihomo.pid")
        if FileManager.default.fileExists(atPath: pidFile) {
            if let pidString = try? String(contentsOfFile: pidFile, encoding: .utf8),
               let pidValue = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                if kill(pidValue, 0) == 0 {
                    isRunning = true
                    self.pid = pidValue
                    return
                }
            }
            try? FileManager.default.removeItem(atPath: pidFile)
        }

        // 方法 2：搜索 mihomo 进程
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "mihomo"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let pidStr = output.split(separator: "\n").first,
               let foundPid = Int32(pidStr) {
                isRunning = true
                pid = foundPid
                managedByApp = false
                return
            }
        } catch {}

        // 方法 3：fallback — 用 -f 参数模糊匹配
        let task2 = Process()
        task2.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task2.arguments = ["-f", "mihomo"]
        let pipe2 = Pipe()
        task2.standardOutput = pipe2
        task2.standardError = FileHandle.nullDevice

        do {
            try task2.run()
            task2.waitUntilExit()
            let data = pipe2.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let pidStr = output.split(separator: "\n").first,
               let foundPid = Int32(pidStr) {
                isRunning = true
                pid = foundPid
                managedByApp = false
                return
            }
        } catch {}

        isRunning = false
        pid = 0
    }
}
