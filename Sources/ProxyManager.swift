//
//  ProxyManager.swift
//  AJMihomoControl
//
//  Created by xujun (https://github.com/xujun)
//  Copyright © 2026 xujun. All rights reserved.
//

import Foundation

/// 通过 networksetup 管理 macOS 系统代理设置
class ProxyManager: ObservableObject {
    @Published var isEnabled = false

    init() {
        refreshStatus()
    }

    // MARK: - 状态刷新（后台执行）

    func refreshStatus() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let interfaces = self._getInterfaces()
            let enabled = interfaces.contains { self._isEnabled($0) }
            DispatchQueue.main.async { self.isEnabled = enabled }
        }
    }

    func updateStatus() {
        refreshStatus()
    }

    // MARK: - 启用 / 停用

    func enable() {
        let config = AppConfig.load()
        let host = config.proxyHost
        let port = String(config.proxyPort)

        // 同步更新 UI
        isEnabled = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            for adapter in self._getInterfaces() {
                self._setProxy(adapter, host: host, port: port)
            }
        }
    }

    func disable() {
        // 同步更新 UI
        isEnabled = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            for adapter in self._getInterfaces() {
                self._disableProxy(adapter)
            }
        }
    }

    // MARK: - 单网卡（菜单项使用）

    func enableInterface(_ adapter: String) {
        let config = AppConfig.load()
        _setProxy(adapter, host: config.proxyHost, port: String(config.proxyPort))
    }

    func disableInterface(_ adapter: String) {
        _disableProxy(adapter)
    }

    // MARK: - 公共查询

    func isInterfaceEnabled(_ adapter: String) -> Bool {
        _isEnabled(adapter)
    }

    var availableInterfaces: [String] {
        _getInterfaces()
    }

    // MARK: - 内部方法

    private func _isEnabled(_ adapter: String) -> Bool {
        _run("networksetup", args: ["-getwebproxy", adapter]).contains("Enabled: Yes")
    }

    private func _getInterfaces() -> [String] {
        _run("networksetup", args: ["-listallnetworkservices"])
            .split(separator: "\n")
            .map(String.init)
            .filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.isEmpty && !t.hasPrefix("*") && !t.lowercased().contains("asterisk")
            }
    }

    private func _setProxy(_ adapter: String, host: String, port: String) {
        _ = _run("networksetup", args: ["-setwebproxy", adapter, host, port])
        _ = _run("networksetup", args: ["-setsecurewebproxy", adapter, host, port])
        _ = _run("networksetup", args: ["-setsocksfirewallproxy", adapter, host, port])
    }

    private func _disableProxy(_ adapter: String) {
        _ = _run("networksetup", args: ["-setwebproxystate", adapter, "off"])
        _ = _run("networksetup", args: ["-setsecurewebproxystate", adapter, "off"])
        _ = _run("networksetup", args: ["-setsocksfirewallproxystate", adapter, "off"])
    }

    private func _run(_ command: String, args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/\(command)")
        p.arguments = args
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
            p.waitUntilExit()
            let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return o + e
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}
