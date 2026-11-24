//
//  SubscriptionConverter.swift
//  AJMihomoControl
//

import Foundation

/// 将订阅内容（Base64 / URI 列表 / Clash YAML）转换为 mihomo 代理 YAML 片段
enum SubscriptionConverter {
    static func convert(_ data: Data) -> [ConfigProxy] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return convert(text)
    }

    static func convert(_ text: String) -> [ConfigProxy] {
        let content = text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else { return [] }

        if content.contains("proxies:") {
            return ProxyConfigPatcher.parse(content).items
        }

        if content.contains("://") {
            return content
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                .compactMap { convertURI($0) }
        }

        if let decoded = base64Decode(content), decoded != content {
            return convert(decoded)
        }
        return []
    }

    private static func convertURI(_ uri: String) -> ConfigProxy? {
        let lower = uri.lowercased()
        let yaml: String?
        switch true {
        case lower.hasPrefix("vless://"): yaml = vless(uri)
        case lower.hasPrefix("vmess://"): yaml = vmess(uri)
        case lower.hasPrefix("trojan://"): yaml = trojan(uri)
        case lower.hasPrefix("ss://"): yaml = shadowsocks(uri)
        case lower.hasPrefix("hysteria2://"), lower.hasPrefix("hy2://"): yaml = hysteria2(uri)
        case lower.hasPrefix("tuic://"): yaml = tuic(uri)
        default: yaml = nil
        }
        guard let raw = yaml else { return nil }
        return ConfigProxy(raw: raw)
    }

    // MARK: - vless

    private static func vless(_ uri: String) -> String? {
        guard let c = URLComponents(string: uri),
              let host = c.host, let uuid = c.user, let port = c.port else { return nil }

        let q = query(c)
        var lines = common(name: name(c, prefix: host), type: "vless", server: host, port: port)
        lines.append("uuid: \(quote(uuid))")
        lines.append("udp: true")

        let security = q["security"] ?? ""
        if security == "tls" || security == "reality" {
            lines.append("tls: true")
        }
        if let sni = q["sni"], !sni.isEmpty { lines.append("servername: \(quote(sni))") }
        if truthy(q["insecure"]) || truthy(q["allowInsecure"]) { lines.append("skip-cert-verify: true") }
        if let fp = q["fp"], !fp.isEmpty { lines.append("client-fingerprint: \(quote(fp))") }
        if let flow = q["flow"], !flow.isEmpty { lines.append("flow: \(quote(flow))") }
        if let alpn = q["alpn"] { lines.append("alpn: [\(alpn.split(separator: ",").map { quote(String($0)) }.joined(separator: ", "))]") }

        let network = q["type"] ?? "tcp"
        if network != "tcp" { lines.append("network: \(quote(network))") }
        appendTransport(&lines, network: network, q: q)

        if security == "reality" {
            lines.append("reality-opts:")
            if let pbk = q["pbk"] { lines.append("  public-key: \(quote(pbk))") }
            if let sid = q["sid"] { lines.append("  short-id: \(quote(sid))") }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - hysteria2

    private static func hysteria2(_ uri: String) -> String? {
        guard let c = URLComponents(string: uri),
              let host = c.host, let port = c.port else { return nil }
        let q = query(c)
        var lines = common(name: name(c, prefix: host), type: "hysteria2", server: host, port: port)
        if let password = c.user, !password.isEmpty { lines.append("password: \(quote(password))") }
        if let sni = q["sni"], !sni.isEmpty { lines.append("sni: \(quote(sni))") }
        if truthy(q["insecure"]) { lines.append("skip-cert-verify: true") }
        if let obfs = q["obfs"], !obfs.isEmpty { lines.append("obfs: \(quote(obfs))") }
        if let obfsPassword = q["obfs-password"], !obfsPassword.isEmpty {
            lines.append("obfs-password: \(quote(obfsPassword))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - vmess

    private static func vmess(_ uri: String) -> String? {
        let payload = String(uri.dropFirst("vmess://".count))
        guard let json = base64Decode(payload),
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        func str(_ key: String) -> String {
            if let value = object[key] as? String { return value }
            if let value = object[key] as? Int { return String(value) }
            return ""
        }

        let host = str("add")
        let port = Int(str("port")) ?? 0
        guard !host.isEmpty, port > 0 else { return nil }

        let ps = str("ps").isEmpty ? host : str("ps")
        var lines = common(name: ps, type: "vmess", server: host, port: port)
        lines.append("uuid: \(quote(str("id")))")
        lines.append("alterId: \(Int(str("aid")) ?? 0)")
        let cipher = str("scy")
        lines.append("cipher: \(quote(cipher.isEmpty ? "auto" : cipher))")
        lines.append("udp: true")

        let tls = str("tls").lowercased()
        if tls == "tls" || tls == "reality" { lines.append("tls: true") }
        let sni = str("sni")
        if !sni.isEmpty { lines.append("servername: \(quote(sni))") }
        if truthy(str("allowInsecure")) || truthy(str("skip-cert-verify")) {
            lines.append("skip-cert-verify: true")
        }
        let alpn = str("alpn")
        if !alpn.isEmpty {
            lines.append("alpn: [\(alpn.split(separator: ",").map { quote(String($0)) }.joined(separator: ", "))]")
        }

        let network = str("net").isEmpty ? "tcp" : str("net")
        if network != "tcp" { lines.append("network: \(quote(network))") }
        var q: [String: String] = [:]
        q["path"] = str("path")
        q["host"] = str("host")
        q["serviceName"] = str("path")
        appendTransport(&lines, network: network, q: q)
        return lines.joined(separator: "\n")
    }

    // MARK: - trojan

    private static func trojan(_ uri: String) -> String? {
        guard let c = URLComponents(string: uri),
              let host = c.host, let port = c.port else { return nil }
        let q = query(c)
        var lines = common(name: name(c, prefix: host), type: "trojan", server: host, port: port)
        if let password = c.user, !password.isEmpty { lines.append("password: \(quote(password))") }
        lines.append("udp: true")
        if let sni = q["sni"] ?? q["peer"], !sni.isEmpty { lines.append("sni: \(quote(sni))") }
        if truthy(q["allowInsecure"]) || truthy(q["insecure"]) { lines.append("skip-cert-verify: true") }
        if let alpn = q["alpn"] {
            lines.append("alpn: [\(alpn.split(separator: ",").map { quote(String($0)) }.joined(separator: ", "))]")
        }
        let network = q["type"] ?? "tcp"
        if network != "tcp" { lines.append("network: \(quote(network))") }
        appendTransport(&lines, network: network, q: q)
        return lines.joined(separator: "\n")
    }

    // MARK: - shadowsocks

    private static func shadowsocks(_ uri: String) -> String? {
        var body = String(uri.dropFirst("ss://".count))
        var fragment = ""
        if let hash = body.firstIndex(of: "#") {
            fragment = String(body[body.index(after: hash)...]).removingPercentEncoding ?? ""
            body = String(body[..<hash])
        }
        var queryText = ""
        if let question = body.firstIndex(of: "?") {
            queryText = String(body[body.index(after: question)...])
            body = String(body[..<question])
        }

        var userInfo: String
        var hostPort: String
        if let at = body.lastIndex(of: "@") {
            userInfo = String(body[..<at])
            hostPort = String(body[body.index(after: at)...])
            if !userInfo.contains(":"), let decoded = base64Decode(userInfo) { userInfo = decoded }
        } else if let decoded = base64Decode(body) {
            guard let at = decoded.lastIndex(of: "@") else { return nil }
            userInfo = String(decoded[..<at])
            hostPort = String(decoded[decoded.index(after: at)...])
        } else {
            return nil
        }

        let parts = userInfo.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let hostParts = hostPort.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard hostParts.count == 2, let port = Int(hostParts[1]) else { return nil }

        let server = String(hostParts[0])
        let name = fragment.isEmpty ? server : fragment
        var lines = common(name: name, type: "ss", server: server, port: port)
        lines.append("cipher: \(quote(String(parts[0])))")
        lines.append("password: \(quote(String(parts[1])))")
        lines.append("udp: true")

        let q = parseQuery(queryText)
        if let plugin = q["plugin"], !plugin.isEmpty {
            let pieces = plugin.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            lines.append("plugin: \(quote(String(pieces[0])))")
            if pieces.count > 1, !pieces[1].isEmpty {
                lines.append("plugin-opts:")
                for option in pieces[1].split(separator: ";") {
                    let pair = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    let key = String(pair[0])
                    let value = pair.count > 1 ? String(pair[1]) : "true"
                    if key == "host" || key == "path" || key == "mode" {
                        lines.append("  \(key): \(quote(value))")
                    }
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - tuic

    private static func tuic(_ uri: String) -> String? {
        guard let c = URLComponents(string: uri),
              let host = c.host, let port = c.port else { return nil }
        let q = query(c)
        var lines = common(name: name(c, prefix: host), type: "tuic", server: host, port: port)
        if let uuid = c.user, !uuid.isEmpty { lines.append("uuid: \(quote(uuid))") }
        if let password = c.password, !password.isEmpty {
            lines.append("password: \(quote(password))")
        } else if let password = q["password"], !password.isEmpty {
            lines.append("password: \(quote(password))")
        }
        if let sni = q["sni"], !sni.isEmpty { lines.append("sni: \(quote(sni))") }
        if truthy(q["allow_insecure"]) || truthy(q["insecure"]) { lines.append("skip-cert-verify: true") }
        if let alpn = q["alpn"] {
            lines.append("alpn: [\(alpn.split(separator: ",").map { quote(String($0)) }.joined(separator: ", "))]")
        }
        return lines.joined(separator: "\n")
    }

    private static func parseQuery(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = pieces.first?.removingPercentEncoding else { continue }
            result[key] = pieces.count > 1 ? (pieces[1].removingPercentEncoding ?? "") : ""
        }
        return result
    }

    // MARK: - helpers

    static func common(name: String, type: String, server: String, port: Int) -> [String] {
        [
            "name: \(quote(name))",
            "type: \(type)",
            "server: \(quote(server))",
            "port: \(port)"
        ]
    }

    static func appendTransport(_ lines: inout [String], network: String, q: [String: String]) {
        switch network {
        case "ws":
            lines.append("ws-opts:")
            lines.append("  path: \(quote(q["path"] ?? "/"))")
            if let host = q["host"], !host.isEmpty {
                lines.append("  headers:")
                lines.append("    Host: \(quote(host))")
            }
        case "grpc":
            if let service = q["serviceName"], !service.isEmpty {
                lines.append("grpc-opts:")
                lines.append("  grpc-service-name: \(quote(service))")
            }
        case "http", "h2":
            lines.append("h2-opts:")
            if let host = q["host"], !host.isEmpty {
                lines.append("  host:")
                lines.append("    - \(quote(host))")
            }
            if let path = q["path"], !path.isEmpty { lines.append("  path: \(quote(path))") }
        default:
            break
        }
    }

    static func query(_ c: URLComponents) -> [String: String] {
        var result: [String: String] = [:]
        for item in c.queryItems ?? [] {
            result[item.name] = item.value ?? ""
        }
        return result
    }

    static func name(_ c: URLComponents, prefix: String) -> String {
        if let fragment = c.fragment?.removingPercentEncoding, !fragment.isEmpty { return fragment }
        return prefix
    }

    static func truthy(_ value: String?) -> Bool {
        guard let value = value?.lowercased() else { return false }
        return value == "1" || value == "true" || value == "yes"
    }

    static func quote(_ value: String) -> String {
        ConfigProxy.quote(value)
    }

    static func base64Decode(_ text: String) -> String? {
        var value = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)
        let remainder = value.count % 4
        if remainder > 0 { value += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: value, options: [.ignoreUnknownCharacters]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}