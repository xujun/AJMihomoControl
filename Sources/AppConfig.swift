//
//  AppConfig.swift
//  AJMihomoControl
//
//  Created by xujun (https://github.com/xujun)
//  Copyright © 2026 xujun. All rights reserved.
//

import Foundation

/// 应用配置，通过 UserDefaults 持久化
struct AppConfig: Codable {
    var mihomoBinaryPath: String
    var mihomoConfigPath: String
    var mihomoHome: String
    var networkAdapter: String
    var proxyHost: String
    var proxyPort: Int
    var dashboardPort: Int

    /// 自动检测 mihomo 安装路径
    static func detectMihomoPaths() -> (binary: String, config: String, home: String) {
        #if arch(arm64)
        let homebrewPrefix = "/opt/homebrew"
        #else
        let homebrewPrefix = "/usr/local"
        #endif

        let homebrewBinary = "\(homebrewPrefix)/bin/mihomo"
        let homebrewConfig = "\(homebrewPrefix)/etc/mihomo/config.yaml"
        let homebrewHome = "\(homebrewPrefix)/etc/mihomo"

        if FileManager.default.fileExists(atPath: homebrewBinary) {
            return (homebrewBinary, homebrewConfig, homebrewHome)
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["mihomo"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty,
               FileManager.default.fileExists(atPath: output) {
                let configDir = (output as NSString).deletingLastPathComponent
                return (output, "\(configDir)/mihomo/config.yaml", "\(configDir)/mihomo")
            }
        } catch {}

        return (homebrewBinary, homebrewConfig, homebrewHome)
    }

    static let `default`: AppConfig = {
        let paths = detectMihomoPaths()
        return AppConfig(
            mihomoBinaryPath: paths.binary,
            mihomoConfigPath: paths.config,
            mihomoHome: paths.home,
            networkAdapter: "Wi-Fi",
            proxyHost: "127.0.0.1",
            proxyPort: 10808,
            dashboardPort: 9090
        )
    }()

    static func load() -> AppConfig {
        guard let data = UserDefaults.standard.data(forKey: "MihomoControlConfig") else {
            return .default
        }
        return (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? .default
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "MihomoControlConfig")
        }
    }

    var resolvedMihomoConfigPath: String {
        NSString(string: mihomoConfigPath).expandingTildeInPath
    }

    var resolvedMihomoHome: String {
        NSString(string: mihomoHome).expandingTildeInPath
    }

    var resolvedMihomoBinaryPath: String {
        NSString(string: mihomoBinaryPath).expandingTildeInPath
    }
}
