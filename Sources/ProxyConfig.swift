//
//  ProxyConfig.swift
//  AJMihomoControl
//

import Foundation
import Combine

/// config.yaml 中的代理服务器
struct ConfigProxy: Identifiable, Equatable {
    /// 去掉列表前缀后的 YAML 片段，缩进相对于 keyIndent
    var raw: String
    var name: String
    var type: String
    var server: String
    var port: Int

    var id: String { raw }

    init(raw: String) {
        self.raw = ConfigProxy.normalize(raw)
        let fields = ConfigProxy.fields(from: self.raw)
        self.name = fields.name
        self.type = fields.type
        self.server = fields.server
        self.port = fields.port
    }

    static func normalize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .newlines)
    }

    static func fields(from raw: String) -> (name: String, type: String, server: String, port: Int) {
        var name = "", type = "", server = "", port = 0
        for line in raw.components(separatedBy: "\n") {
            guard !line.hasPrefix(" "), let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "name": name = scalar(value)
            case "type": type = scalar(value)
            case "server": server = scalar(value)
            case "port": port = Int(scalar(value)) ?? 0
            default: break
            }
        }
        return (name, type, server, port)
    }

    static func scalar(_ value: String) -> String {
        var text = value
        if let range = text.range(of: " #") { text = String(text[..<range.lowerBound]) }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            text = String(text.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        } else if text.hasPrefix("'"), text.hasSuffix("'"), text.count >= 2 {
            text = String(text.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return text
    }

    static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// 管理 config.yaml 中 proxies 的增删改
final class ProxyConfigManager: ObservableObject {
    @Published private(set) var proxies: [ConfigProxy] = []
    @Published var statusMessage: String?
    @Published var statusIsError = false

    init() { reload() }

    var names: Set<String> { Set(proxies.map { $0.name }) }

    func reload() {
        let path = AppConfig.load().resolvedMihomoConfigPath
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            proxies = []
            return
        }
        proxies = ProxyConfigPatcher.parse(text).items
    }

    @discardableResult
    func add(raw: String) -> Bool {
        let proxy = ConfigProxy(raw: raw)
        guard validate(proxy) else { return false }
        guard !names.contains(proxy.name) else {
            setStatus(L10n.proxyNameExists, isError: true)
            return false
        }
        return commit(proxies + [proxy], added: [proxy.name], removed: [], renames: [],
                      success: L10n.proxyAdded)
    }

    @discardableResult
    func update(index: Int, raw: String) -> Bool {
        guard proxies.indices.contains(index) else { return false }
        let proxy = ConfigProxy(raw: raw)
        guard validate(proxy) else { return false }
        let old = proxies[index].name
        if proxy.name != old, names.contains(proxy.name) {
            setStatus(L10n.proxyNameExists, isError: true)
            return false
        }
        var updated = proxies
        updated[index] = proxy
        let renames = proxy.name == old ? [] : [(old, proxy.name)]
        return commit(updated, added: [], removed: [], renames: renames,
                      success: L10n.proxyUpdated)
    }

    @discardableResult
    func remove(index: Int) -> Bool {
        guard proxies.indices.contains(index) else { return false }
        var updated = proxies
        let removed = updated.remove(at: index)
        return commit(updated, added: [], removed: [removed.name], renames: [],
                      success: L10n.proxyDeleted)
    }

    private func validate(_ proxy: ConfigProxy) -> Bool {
        if proxy.name.trimmingCharacters(in: .whitespaces).isEmpty ||
            proxy.type.trimmingCharacters(in: .whitespaces).isEmpty ||
            proxy.server.trimmingCharacters(in: .whitespaces).isEmpty ||
            proxy.port <= 0 {
            setStatus(L10n.proxyInvalid, isError: true)
            return false
        }
        return true
    }

    private func commit(_ updated: [ConfigProxy], added: [String], removed: [String],
                        renames: [(String, String)], success: String) -> Bool {
        let config = AppConfig.load()
        let path = config.resolvedMihomoConfigPath
        guard let original = try? String(contentsOfFile: path, encoding: .utf8) else {
            setStatus(L10n.subscriptionConfigMissing, isError: true)
            return false
        }

        let text = ProxyConfigPatcher.write(configText: original, proxies: updated,
                                           added: added, removed: removed, renames: renames)
        do {
            try original.write(toFile: path + ".ajbak", atomically: true, encoding: .utf8)
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            setStatus("\(L10n.proxyWriteFailed)：\(error.localizedDescription)", isError: true)
            return false
        }

        proxies = updated
        setStatus(success, isError: false)
        return true
    }

    private func setStatus(_ message: String?, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}

// MARK: - 配置解析与写入

enum ProxyConfigPatcher {
    struct Parsed {
        var items: [ConfigProxy]
        var prelude: [String]
        var listIndent: Int
        var hasSection: Bool
    }

    static func parse(_ text: String) -> Parsed {
        let lines = normalized(text).components(separatedBy: "\n")
        guard let section = topLevelSection("proxies", in: lines) else {
            return Parsed(items: [], prelude: [], listIndent: 2, hasSection: false)
        }

        let body = Array(lines[section.bodyStart..<section.end])
        var listIndent = 2
        if let first = body.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("-") }) {
            listIndent = leadingSpaces(first)
        }

        let starts = body.indices.filter {
            leadingSpaces(body[$0]) == listIndent &&
            body[$0].trimmingCharacters(in: .whitespaces).hasPrefix("-")
        }
        guard let firstStart = starts.first else {
            return Parsed(items: [], prelude: body, listIndent: listIndent, hasSection: true)
        }

        let prelude = Array(body[0..<firstStart])
        var items: [ConfigProxy] = []
        for (offset, start) in starts.enumerated() {
            let end = offset + 1 < starts.count ? starts[offset + 1] : body.count
            if let raw = rawBody(Array(body[start..<end]), listIndent: listIndent) {
                items.append(ConfigProxy(raw: raw))
            }
        }
        return Parsed(items: items, prelude: prelude, listIndent: listIndent, hasSection: true)
    }

    static func write(configText: String, proxies: [ConfigProxy],
                      added: [String], removed: [String],
                      renames: [(String, String)]) -> String {
        var lines = normalized(configText).components(separatedBy: "\n")
        let parsed = parse(configText)
        let listIndent = parsed.hasSection ? parsed.listIndent : 2
        let blocks = proxies.flatMap { renderBlock($0, listIndent: listIndent) }

        if let section = topLevelSection("proxies", in: lines) {
            let prelude = parsed.prelude
            var body = prelude
            if !body.isEmpty && !blocks.isEmpty { body.append("") }
            body.append(contentsOf: blocks)
            lines.replaceSubrange(section.bodyStart..<section.end, with: body)
            lines[section.header] = "proxies:"
        } else if !blocks.isEmpty {
            if lines.last == "" { lines.removeLast() }
            lines.append("")
            lines.append("proxies:")
            lines.append(contentsOf: blocks)
        }

        adjustGroupReferences(&lines, added: added, removed: removed, renames: renames)

        var text = lines.joined(separator: "\n")
        while text.hasSuffix("\n\n") { text.removeLast() }
        if !text.hasSuffix("\n") { text += "\n" }
        return text
    }

    private static func renderBlock(_ proxy: ConfigProxy, listIndent: Int) -> [String] {
        let pad = String(repeating: " ", count: listIndent)
        let keyPad = String(repeating: " ", count: listIndent + 2)
        var result = [
            "\(pad)- name: \(ConfigProxy.quote(proxy.name))",
            "\(keyPad)type: \(proxy.type)",
            "\(keyPad)server: \(ConfigProxy.quote(proxy.server))",
            "\(keyPad)port: \(proxy.port)"
        ]

        for line in proxy.raw.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append("")
                continue
            }
            if !line.hasPrefix(" "), let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                if ["name", "type", "server", "port"].contains(key) { continue }
            }
            result.append(keyPad + line)
        }
        return result
    }

    private static func rawBody(_ block: [String], listIndent: Int) -> String? {
        guard let first = block.first else { return nil }
        let keyIndent = listIndent + 2
        var result: [String] = []

        var firstLine = String(first.dropFirst(min(listIndent, first.count)))
        if firstLine.hasPrefix("-") {
            firstLine = String(firstLine.dropFirst())
            if firstLine.hasPrefix(" ") { firstLine = String(firstLine.dropFirst()) }
        }
        result.append(firstLine)

        for line in block.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append("")
            } else {
                let spaces = leadingSpaces(line)
                result.append(String(line.dropFirst(min(spaces, keyIndent))))
            }
        }
        return result.joined(separator: "\n")
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func topLevelSection(_ key: String, in lines: [String]) -> (header: Int, bodyStart: Int, end: Int)? {
        guard let header = lines.firstIndex(where: {
            $0.hasPrefix("\(key):") && !$0.hasPrefix(" ") && !$0.hasPrefix("\t")
        }) else { return nil }

        var end = lines.count
        for index in (header + 1)..<lines.count {
            let line = lines[index]
            if line.isEmpty { continue }
            let first = line.first!
            if first == " " || first == "\t" { continue }
            end = index
            break
        }
        return (header, header + 1, end)
    }

    private static func adjustGroupReferences(_ lines: inout [String],
                                              added: [String], removed: [String],
                                              renames: [(String, String)]) {
        guard let section = topLevelSection("proxy-groups", in: lines) else { return }
        var body = Array(lines[section.bodyStart..<section.end])

        var filtered: [String] = []
        for line in body {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("-") {
                let value = ConfigProxy.scalar(String(trimmed.dropFirst()))
                if removed.contains(value) { continue }
                if let rename = renames.first(where: { $0.0 == value }) {
                    let pad = String(repeating: " ", count: leadingSpaces(line))
                    filtered.append("\(pad)- \(ConfigProxy.quote(rename.1))")
                    continue
                }
            }
            filtered.append(line)
        }
        body = filtered
        body = ensureGroupsNonEmpty(body)

        if !added.isEmpty {
            let items = parseGroupItems(body)
            let target = items.first(where: { $0.name.caseInsensitiveCompare("PROXY") == .orderedSame })
                ?? items.first(where: { $0.type.lowercased() == "select" })

            if let target = target {
                let keyIndent = target.indent + 2
                var proxiesIndex: Int?
                for index in target.start..<target.end {
                    let trimmed = body[index].trimmingCharacters(in: .whitespaces)
                    if leadingSpaces(body[index]) == keyIndent && trimmed.hasPrefix("proxies:") {
                        proxiesIndex = index
                        break
                    }
                }

                var namesToAdd = added
                if let proxiesIndex = proxiesIndex {
                    let stepIndent = leadingSpaces(body[proxiesIndex])
                    var listEnd = proxiesIndex + 1
                    while listEnd < target.end {
                        let trimmed = body[listEnd].trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty || trimmed.hasPrefix("#") || !trimmed.hasPrefix("-") { break }
                        if leadingSpaces(body[listEnd]) <= stepIndent { break }
                        let value = ConfigProxy.scalar(String(trimmed.dropFirst()))
                        namesToAdd.removeAll { $0 == value }
                        listEnd += 1
                    }
                    let entryIndent = stepIndent + 2
                    let entries = namesToAdd.map {
                        String(repeating: " ", count: entryIndent) + "- \(ConfigProxy.quote($0))"
                    }
                    body.insert(contentsOf: entries, at: listEnd)
                } else {
                    let entryIndent = keyIndent + 2
                    var insert = [String(repeating: " ", count: keyIndent) + "proxies:"]
                    insert.append(contentsOf: namesToAdd.map {
                        String(repeating: " ", count: entryIndent) + "- \(ConfigProxy.quote($0))"
                    })
                    body.insert(contentsOf: insert, at: target.start + 1)
                }
            }
        }

        lines.replaceSubrange(section.bodyStart..<section.end, with: body)
        lines[section.header] = "proxy-groups:"
    }

    private struct GroupItem {
        let start: Int
        let end: Int
        let indent: Int
        let name: String
        let type: String
    }

    private static func ensureGroupsNonEmpty(_ block: [String]) -> [String] {
        var body = block
        let items = parseGroupItems(body)

        for item in items.reversed() {
            var hasNodes = false
            var proxiesIndex: Int?
            let keyIndent = item.indent + 2

            for index in item.start..<item.end {
                let trimmed = body[index].trimmingCharacters(in: .whitespaces)
                let indent = leadingSpaces(body[index])

                if indent > item.indent && trimmed.hasPrefix("-") {
                    hasNodes = true
                }
                if indent == keyIndent && trimmed.hasPrefix("include-all"),
                   !trimmed.hasSuffix("false") {
                    hasNodes = true
                }
                if indent == keyIndent && (trimmed.hasPrefix("proxies:") || trimmed.hasPrefix("use:")) {
                    if trimmed.hasPrefix("proxies:") { proxiesIndex = index }
                    let value = String(trimmed.drop(while: { $0 != ":" }).dropFirst())
                        .trimmingCharacters(in: .whitespaces)
                    if value.hasPrefix("["), value != "[]" { hasNodes = true }
                }
            }

            if hasNodes { continue }

            if let proxiesIndex = proxiesIndex {
                let entryIndent = leadingSpaces(body[proxiesIndex]) + 2
                body.insert(String(repeating: " ", count: entryIndent) + "- DIRECT",
                            at: proxiesIndex + 1)
            } else {
                body.insert(contentsOf: [
                    String(repeating: " ", count: keyIndent) + "proxies:",
                    String(repeating: " ", count: keyIndent + 2) + "- DIRECT"
                ], at: item.start + 1)
            }
        }

        return body
    }

    private static func parseGroupItems(_ block: [String]) -> [GroupItem] {
        var listIndent: Int?
        var starts: [Int] = []

        for (index, line) in block.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || !trimmed.hasPrefix("-") { continue }
            let indent = leadingSpaces(line)
            if listIndent == nil { listIndent = indent }
            if indent == listIndent { starts.append(index) }
        }
        guard let indent = listIndent else { return [] }

        var items: [GroupItem] = []
        for (offset, start) in starts.enumerated() {
            let end = offset + 1 < starts.count ? starts[offset + 1] : block.count
            var name = "", type = ""
            for index in start..<end {
                var content = block[index].trimmingCharacters(in: .whitespaces)
                if content.hasPrefix("-") {
                    content = String(content.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                if content.hasPrefix("name:") {
                    name = ConfigProxy.scalar(String(content.dropFirst(5)))
                } else if content.hasPrefix("type:") {
                    type = ConfigProxy.scalar(String(content.dropFirst(5)))
                }
                if !name.isEmpty && !type.isEmpty { break }
            }
            items.append(GroupItem(start: start, end: end, indent: indent, name: name, type: type))
        }
        return items
    }

    private static func leadingSpaces(_ line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " || character == "\t" { count += 1 } else { break }
        }
        return count
    }
}