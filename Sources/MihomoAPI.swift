//
//  MihomoAPI.swift
//  AJMihomoControl
//
//  Created by xujun (https://github.com/xujun)
//  Copyright © 2026 xujun. All rights reserved.
//

import Foundation
import Combine

// MARK: - 数据模型

/// 延迟历史记录
struct DelayHistory: Codable {
    let time: String?
    let delay: Int  // 毫秒，0 表示超时/失败
}

/// 代理信息（单个代理或代理组）
struct ProxyInfo: Codable, Identifiable {
    var id: String { name }
    let name: String
    let type: String
    var now: String?
    var all: [String]?
    var history: [DelayHistory]?
    var hidden: Bool?
    var nowDelay: Int?
    var server: String?  // API 通常不返回此字段

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        now = try container.decodeIfPresent(String.self, forKey: .now)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden)
        nowDelay = try container.decodeIfPresent(Int.self, forKey: .nowDelay)
        server = try container.decodeIfPresent(String.self, forKey: .server)

        // all 可能是 [String] 或 [ProxyInfo]（嵌套代理组的情况）
        if let allStrings = try? container.decodeIfPresent([String].self, forKey: .all) {
            all = allStrings
        } else if let allProxies = try? container.decodeIfPresent([ProxyInfo].self, forKey: .all) {
            all = allProxies.map { $0.name }
        } else {
            all = nil
        }

        history = try container.decodeIfPresent([DelayHistory].self, forKey: .history)
    }

    enum CodingKeys: String, CodingKey {
        case name, type, now, all, history, hidden, nowDelay, server
    }

    /// 系统代理类型（应该过滤掉的）
    private static let systemTypes = ["Direct", "Reject", "RejectDrop", "Compatible", "Pass", "Selector", "Fallback", "URLTest"]

    /// 是否为真正的代理服务器（不是系统代理）
    var isRealProxy: Bool {
        return !Self.systemTypes.contains(type)
    }

    /// 是否为可切换的代理组类型
    var isSwitchableGroup: Bool {
        let switchableTypes = ["Selector", "Fallback", "URLTest"]
        return switchableTypes.contains(type) && (all != nil) && (hidden != true)
    }

    /// 获取当前最新延迟
    var currentDelay: Int? {
        if let nowDelay = nowDelay, nowDelay > 0 {
            return nowDelay
        }
        guard let history = history, !history.isEmpty else { return nil }
        return history.last?.delay
    }
}

/// /proxies API 响应
struct ProxyResponse: Codable {
    let proxies: [String: ProxyInfo]
}

/// 切换代理请求体
struct SwitchProxyRequest: Codable {
    let name: String
}

/// 延迟测试响应
struct DelayResponse: Codable {
    let delay: Int  // 毫秒
}

// MARK: - Mihomo API 客户端

class MihomoAPI: ObservableObject {
    @Published var proxyServers: [ProxyInfo] = []  // 所有真正的代理服务器
    @Published var isLoading = false
    @Published var isTestingDelay = false
    @Published var errorMessage: String?
    @Published var delayCache: [String: Int] = [:]  // 缓存代理延迟: proxyName -> delay(ms)
    @Published var currentProxy: String = ""  // 当前选中的代理（从 GLOBAL 组获取）

    private let switchableTypes = ["Selector", "Fallback", "URLTest"]

    // MARK: - 基础配置

    private func baseURL() -> String {
        let config = AppConfig.load()
        return "http://\(config.proxyHost):\(config.dashboardPort)"
    }

    private func authHeaders() -> [String: String] {
        let config = AppConfig.load()
        var secret = config.apiSecret

        // 如果没有手动配置 secret，尝试从 mihomo 配置文件中读取
        if secret.isEmpty {
            secret = Self.readSecretFromConfig(config.resolvedMihomoConfigPath)
        }

        guard !secret.isEmpty else { return [:] }
        return ["Authorization": "Bearer \(secret)"]
    }

    /// 从 mihomo 配置文件中读取 secret
    private static func readSecretFromConfig(_ configPath: String) -> String {
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return ""
        }

        // 简单的 YAML 解析：查找 "secret:" 或 "secret :" 行
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // 匹配 "secret:" 或 "secret :" 开头的行
            if trimmed.hasPrefix("secret:") || trimmed.hasPrefix("secret :") {
                // 提取冒号后的值
                if let colonIndex = trimmed.firstIndex(of: ":") {
                    let value = trimmed[trimmed.index(after: colonIndex)...]
                        .trimmingCharacters(in: .whitespaces)
                        // 移除引号
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    return value
                }
            }
        }
        return ""
    }

    // MARK: - 获取代理列表

    func fetchProxies() {
        DispatchQueue.main.async { self.isLoading = true; self.errorMessage = nil }

        let urlString = "\(baseURL())/proxies"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = L10n.apiUnreachable
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        for (key, value) in authHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
            }

            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "\(L10n.apiUnreachable): \(error.localizedDescription)"
                    self?.proxyServers = []
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    self?.errorMessage = L10n.apiUnreachable
                    self?.proxyServers = []
                }
                return
            }

            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(ProxyResponse.self, from: data)

                // 提取所有有 server 字段的真正代理服务器
                let servers = response.proxies.values
                    .filter { $0.isRealProxy }
                    .sorted { $0.name < $1.name }

                // 获取当前选中的代理（从 Selector 类型组中查找）
                // 优先找 PROXY 组，其次 GLOBAL 组
                var currentProxyName = ""
                let realProxyNames = Set(servers.map { $0.name })

                // 先检查 PROXY 组
                if let proxyGroup = response.proxies["PROXY"],
                   let now = proxyGroup.now,
                   realProxyNames.contains(now) {
                    currentProxyName = now
                }
                // 再检查 GLOBAL 组
                else if let globalGroup = response.proxies["GLOBAL"],
                        let now = globalGroup.now {
                    // 如果 GLOBAL 选中的是真实代理
                    if realProxyNames.contains(now) {
                        currentProxyName = now
                    }
                }
                // 最后遍历所有 Selector 组
                if currentProxyName.isEmpty {
                    for (_, proxy) in response.proxies {
                        if proxy.type == "Selector", let now = proxy.now, realProxyNames.contains(now) {
                            currentProxyName = now
                            break
                        }
                    }
                }

                DispatchQueue.main.async {
                    self?.proxyServers = servers
                    self?.currentProxy = currentProxyName
                    self?.errorMessage = nil
                }
            } catch let decodingError as DecodingError {
                let details: String
                switch decodingError {
                case .keyNotFound(let key, let context):
                    details = "缺少字段: \(key.stringValue) at \(context.codingPath.map{$0.stringValue}.joined(separator: "."))"
                case .typeMismatch(let type, let context):
                    details = "类型错误: \(type) at \(context.codingPath.map{$0.stringValue}.joined(separator: "."))"
                case .valueNotFound(let type, let context):
                    details = "值缺失: \(type) at \(context.codingPath.map{$0.stringValue}.joined(separator: "."))"
                case .dataCorrupted(let context):
                    details = "数据损坏: \(context.debugDescription)"
                @unknown default:
                    details = decodingError.localizedDescription
                }
                // 打印原始响应以便调试
                let rawResponse = String(data: data, encoding: .utf8) ?? "(无法解码)"
                print("[MihomoAPI] 解析失败，原始响应: \(rawResponse)")
                DispatchQueue.main.async {
                    self?.errorMessage = "解析失败: \(details)"
                    self?.proxyServers = []
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "解析失败: \(error.localizedDescription)"
                    self?.proxyServers = []
                }
            }
        }.resume()
    }

    // MARK: - 切换代理

    func switchProxy(name: String) {
        // 在所有 Selector 组中切换代理
        var requestCount = 0

        // 先获取当前代理组列表
        let urlString = "\(baseURL())/proxies"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        for (key, value) in authHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }

            do {
                let response = try JSONDecoder().decode(ProxyResponse.self, from: data)
                // 找到所有 Selector 类型的组
                let selectorGroups = response.proxies.values.filter { $0.type == "Selector" }

                for group in selectorGroups {
                    self.switchInGroup(groupName: group.name, proxyName: name)
                    requestCount += 1
                }

                DispatchQueue.main.async {
                    self.currentProxy = name
                }
            } catch {
                // 如果解析失败，至少切换到 GLOBAL
                self.switchInGroup(groupName: "GLOBAL", proxyName: name)
                DispatchQueue.main.async {
                    self.currentProxy = name
                }
            }
        }.resume()
    }

    private func switchInGroup(groupName: String, proxyName: String) {
        let encodedGroup = groupName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? groupName
        let urlString = "\(baseURL())/proxies/\(encodedGroup)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = try? JSONEncoder().encode(SwitchProxyRequest(name: proxyName))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        for (key, value) in authHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    // MARK: - 测试延迟

    func testDelay(proxy: String, completion: @escaping (Int?) -> Void) {
        let encodedProxy = proxy.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? proxy
        let urlString = "\(baseURL())/proxies/\(encodedProxy)/delay?timeout=5000&url=https://www.gstatic.com/generate_204"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        for (key, value) in authHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            do {
                let delayResponse = try JSONDecoder().decode(DelayResponse.self, from: data)
                DispatchQueue.main.async { completion(delayResponse.delay) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }.resume()
    }

    /// 批量测试所有代理服务器的延迟
    func testAllDelays() {
        DispatchQueue.main.async { self.isTestingDelay = true }

        let servers = proxyServers
        var completedCount = 0
        let totalCount = servers.count

        guard totalCount > 0 else {
            DispatchQueue.main.async { self.isTestingDelay = false }
            return
        }

        for server in servers {
            testDelay(proxy: server.name) { [weak self] delay in
                completedCount += 1
                // 缓存延迟结果
                if let delay = delay, delay > 0 {
                    DispatchQueue.main.async {
                        self?.delayCache[server.name] = delay
                    }
                } else if delay == 0 || delay == nil {
                    DispatchQueue.main.async {
                        self?.delayCache[server.name] = 0
                    }
                }
                // 所有测试完成
                if completedCount >= totalCount {
                    DispatchQueue.main.async {
                        self?.isTestingDelay = false
                    }
                }
            }
        }

        // 超时保护：最多等 15 秒
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            if self?.isTestingDelay == true {
                self?.isTestingDelay = false
            }
        }
    }

    /// 清空状态（mihomo 停止时调用）
    func reset() {
        DispatchQueue.main.async {
            self.proxyServers = []
            self.currentProxy = ""
            self.isLoading = false
            self.isTestingDelay = false
            self.errorMessage = nil
            self.delayCache = [:]
        }
    }
}
