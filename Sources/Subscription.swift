//
//  Subscription.swift
//  AJMihomoControl
//
//  Created by xujun (https://github.com/xujun)
//  Copyright © 2026 xujun. All rights reserved.
//

import Foundation
import Combine
import CryptoKit

// MARK: - 订阅模型

struct Subscription: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var url: String
    var enabled: Bool
    var intervalHours: Int
    var lastApplied: Date?
    var nodeCount: Int?
    var lastError: String?

    init(id: String = UUID().uuidString,
         name: String = "",
         url: String,
         enabled: Bool = true,
         intervalHours: Int = 24,
         lastApplied: Date? = nil,
         nodeCount: Int? = nil,
         lastError: String? = nil) {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.url = trimmedURL
        self.name = trimmedName.isEmpty ? Subscription.defaultName(for: trimmedURL) : trimmedName
        self.enabled = enabled
        self.intervalHours = max(1, intervalHours)
        self.lastApplied = lastApplied
        self.nodeCount = nodeCount
        self.lastError = lastError
    }

    /// mihomo proxy-providers 中使用的稳定名称
    var providerName: String { Subscription.providerName(for: url) }

    var displayURL: String {
        guard url.count > 52 else { return url }
        return "\(url.prefix(34))…\(url.suffix(14))"
    }

    static func defaultName(for url: String) -> String {
        if let host = URL(string: url)?.host, !host.isEmpty {
            return host
        }
        return "Subscription"
    }

    static func providerName(for url: String) -> String {
        let digest = SHA256.hash(data: Data(url.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "ajsub_" + String(hex.prefix(10))
    }
}

// MARK: - 订阅持久化

final class SubscriptionStore {
    static let shared = SubscriptionStore()

    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.fileURL = base
                .appendingPathComponent("AJMihomoControl", isDirectory: true)
                .appendingPathComponent("subscriptions.json")
        }
    }

    func load() -> [Subscription] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Subscription].self, from: data)) ?? []
    }

    func save(_ subscriptions: [Subscription]) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(subscriptions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - 订阅管理

final class SubscriptionManager: ObservableObject {
    @Published private(set) var subscriptions: [Subscription] = []
    @Published var isApplying = false
    @Published var statusMessage: String?
    @Published var statusIsError = false

    private let store: SubscriptionStore

    init(store: SubscriptionStore = .shared) {
        self.store = store
        self.subscriptions = store.load()
    }

    /// 旧版本使用 proxy-providers，检测到后需要迁移为普通 proxies
    var hasLegacyProviderConfig: Bool {
        let path = AppConfig.load().resolvedMihomoConfigPath
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        return text.contains("ajsub_")
    }

    @discardableResult
    func add(url: String, name: String = "") -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              parsed.host?.isEmpty == false else {
            setStatus(L10n.subscriptionInvalidURL, isError: true)
            return false
        }

        guard !subscriptions.contains(where: { $0.url == trimmed }) else {
            setStatus(L10n.subscriptionExists, isError: true)
            return false
        }

        subscriptions.append(Subscription(name: name, url: trimmed))
        persist()
        setStatus(L10n.subscriptionAdded, isError: false)
        return true
    }

    func remove(_ subscription: Subscription) {
        subscriptions.removeAll { $0.id == subscription.id }
        persist()
        setStatus(nil, isError: false)
    }

    func setEnabled(_ subscription: Subscription, enabled: Bool) {
        guard let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) else { return }
        subscriptions[index].enabled = enabled
        persist()
    }

    struct ApplyOutcome {
        let success: Bool
        let changed: Bool
        let targetGroup: String?
        let warnings: [String]
        let message: String
    }

    /// 拉取订阅并将节点合并进 config.yaml 的 proxies（导入后即为普通代理，可修改/删除）
    func apply(completion: @escaping (ApplyOutcome) -> Void) {
        let enabled = subscriptions.filter { $0.enabled }
        guard !enabled.isEmpty else {
            let message = L10n.subscriptionEmpty
            setStatus(message, isError: false)
            completion(ApplyOutcome(success: true, changed: false, targetGroup: nil,
                                    warnings: [], message: message))
            return
        }

        isApplying = true
        let group = DispatchGroup()
        let lock = NSLock()
        var imported: [(Subscription, [ConfigProxy])] = []
        var errors: [(String, String)] = []

        for subscription in enabled {
            group.enter()
            fetch(subscription) { result in
                lock.lock()
                switch result {
                case .success(let proxies):
                    imported.append((subscription, proxies))
                case .failure(let error):
                    errors.append((subscription.name, error.localizedDescription))
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.finishApply(imported: imported, errors: errors, completion: completion)
        }
    }

    private func fetch(_ subscription: Subscription,
                       completion: @escaping (Result<[ConfigProxy], Error>) -> Void) {
        guard let url = URL(string: subscription.url) else {
            completion(.failure(NSError(domain: "Subscription", code: 400,
                                        userInfo: [NSLocalizedDescriptionKey: L10n.subscriptionInvalidURL])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("mihomo", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data = data else {
                completion(.failure(NSError(domain: "Subscription", code: 500,
                                            userInfo: [NSLocalizedDescriptionKey: L10n.subscriptionNoNodes])))
                return
            }
            let proxies = SubscriptionConverter.convert(data)
            if proxies.isEmpty {
                completion(.failure(NSError(domain: "Subscription", code: 422,
                                            userInfo: [NSLocalizedDescriptionKey: L10n.subscriptionNoNodes])))
            } else {
                completion(.success(proxies))
            }
        }.resume()
    }

    private func finishApply(imported: [(Subscription, [ConfigProxy])],
                             errors: [(String, String)],
                             completion: @escaping (ApplyOutcome) -> Void) {
        defer { isApplying = false }

        let config = AppConfig.load()
        let path = config.resolvedMihomoConfigPath
        guard FileManager.default.fileExists(atPath: path),
              let original = try? String(contentsOfFile: path, encoding: .utf8) else {
            let message = L10n.subscriptionConfigMissing
            setStatus(message, isError: true)
            completion(ApplyOutcome(success: false, changed: false, targetGroup: nil,
                                    warnings: [], message: message))
            return
        }

        // 清理旧版本写入的 proxy-providers / use
        let cleaned = SubscriptionConfigPatcher.patch(configText: original, subscriptions: [])
        let existing = ProxyConfigPatcher.parse(cleaned.text).items
        var merged = existing
        var existingNames = Set(existing.map { $0.name })
        var addedNames: [String] = []

        for (_, proxies) in imported {
            for proxy in proxies where !existingNames.contains(proxy.name) {
                merged.append(proxy)
                existingNames.insert(proxy.name)
                addedNames.append(proxy.name)
            }
        }

        let text = ProxyConfigPatcher.write(configText: cleaned.text, proxies: merged,
                                            added: addedNames, removed: [], renames: [])
        let changed = text != original

        if changed {
            do {
                try original.write(toFile: path + ".ajbak", atomically: true, encoding: .utf8)
                try text.write(toFile: path, atomically: true, encoding: .utf8)
            } catch {
                let message = "\(L10n.subscriptionApplyFailed)：\(error.localizedDescription)"
                setStatus(message, isError: true)
                completion(ApplyOutcome(success: false, changed: false, targetGroup: nil,
                                        warnings: [], message: message))
                return
            }
        }

        let now = Date()
        let errorMap = errors.reduce(into: [String: String]()) { $0[$1.0] = $1.1 }
        for index in subscriptions.indices {
            let name = subscriptions[index].name
            if let pair = imported.first(where: { $0.0.id == subscriptions[index].id }) {
                subscriptions[index].nodeCount = pair.1.count
                subscriptions[index].lastApplied = now
                subscriptions[index].lastError = nil
            } else if let error = errorMap[name] {
                subscriptions[index].lastError = error
            }
        }
        persist()

        var warnings = cleaned.warnings
        let failed = errors.map { "\($0.0): \($0.1)" }
        warnings.append(contentsOf: failed)

        let message: String
        if imported.isEmpty {
            message = L10n.subscriptionApplyFailed
        } else if changed {
            message = L10n.subscriptionApplySuccess
        } else {
            message = L10n.subscriptionApplyUnchanged
        }
        let finalMessage = warnings.isEmpty ? message : "\(warnings.joined(separator: "；")) — \(message)"
        setStatus(finalMessage, isError: imported.isEmpty)

        completion(ApplyOutcome(success: !imported.isEmpty, changed: changed,
                                targetGroup: nil, warnings: warnings, message: finalMessage))
    }

    private func persist() {
        store.save(subscriptions)
    }

    private func setStatus(_ message: String?, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}

// MARK: - 配置写入

enum SubscriptionConfigPatcher {
    static let providerPrefix = "ajsub_"

    struct Outcome {
        let text: String
        let targetGroup: String?
        let warnings: [String]
        let providerCount: Int
    }

    static func patch(configText: String, subscriptions: [Subscription]) -> Outcome {
        var lines = configText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var warnings: [String] = []
        let enabled = subscriptions.filter { $0.enabled }
        let providerIds = enabled.map { $0.providerName }

        let providersPatched = patchProviders(&lines, subscriptions: enabled, warnings: &warnings)

        var targetGroup: String?
        if providersPatched {
            targetGroup = patchGroups(&lines, providerIds: providerIds, warnings: &warnings)
        }

        var text = providersPatched ? lines.joined(separator: "\n") : configText
        while text.hasSuffix("\n\n") {
            text.removeLast()
        }
        if !text.hasSuffix("\n") {
            text += "\n"
        }

        return Outcome(text: text, targetGroup: targetGroup,
                       warnings: warnings,
                       providerCount: providersPatched ? enabled.count : 0)
    }

    // MARK: Providers

    @discardableResult
    private static func patchProviders(_ lines: inout [String],
                                       subscriptions: [Subscription],
                                       warnings: inout [String]) -> Bool {
        let key = "proxy-providers"

        if let section = topLevelSection(key, in: lines) {
            let inline = inlineValue(of: lines[section.header], key: key)
            guard isInlineContainerEmpty(inline) else {
                warnings.append(L10n.subscriptionInlineUnsupported(key))
                return false
            }

            var block = Array(lines[section.bodyStart..<section.end])
            let indent = childIndent(of: block) ?? 2
            removeManagedEntries(&block, prefix: providerPrefix)

            for subscription in subscriptions {
                block.append(contentsOf: providerLines(subscription, indent: indent))
            }

            lines.replaceSubrange(section.bodyStart..<section.end, with: block)
            lines[section.header] = "\(key):"

            if !hasYamlContent(block) {
                if let emptySection = topLevelSection(key, in: lines),
                   !hasYamlContent(lines[emptySection.bodyStart..<emptySection.end]) {
                    lines.remove(at: emptySection.header)
                }
            }
            return true
        }

        guard !subscriptions.isEmpty else { return true }

        if lines.last == "" {
            lines.removeLast()
        }
        lines.append("")
        lines.append("\(key):")
        for subscription in subscriptions {
            lines.append(contentsOf: providerLines(subscription, indent: 2))
        }
        return true
    }

    private static func providerLines(_ subscription: Subscription, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        let pad1 = pad + "  "
        let pad2 = pad1 + "  "
        let id = subscription.providerName
        let interval = max(1, subscription.intervalHours) * 3600

        return [
            "\(pad)\(id):",
            "\(pad1)type: http",
            "\(pad1)url: \(yamlQuote(subscription.url))",
            "\(pad1)interval: \(interval)",
            "\(pad1)proxy: DIRECT",
            "\(pad1)path: ./providers/\(id).yaml",
            "\(pad1)health-check:",
            "\(pad2)enable: true",
            "\(pad2)url: https://www.gstatic.com/generate_204",
            "\(pad2)interval: 300"
        ]
    }

    // MARK: Groups

    private static func patchGroups(_ lines: inout [String],
                                    providerIds: [String],
                                    warnings: inout [String]) -> String? {
        let key = "proxy-groups"

        guard let section = topLevelSection(key, in: lines) else {
            guard !providerIds.isEmpty else { return nil }

            if lines.last == "" {
                lines.removeLast()
            }
            lines.append("")
            lines.append("\(key):")
            lines.append(contentsOf: newGroupLines(name: "PROXY", providerIds: providerIds, indent: 2))
            warnings.append(L10n.subscriptionGroupCreated("PROXY"))
            return "PROXY"
        }

        let inline = inlineValue(of: lines[section.header], key: key)
        guard isInlineContainerEmpty(inline) else {
            warnings.append(L10n.subscriptionInlineUnsupported(key))
            return nil
        }

        var block = Array(lines[section.bodyStart..<section.end])
        let items = parseGroupItems(block)

        if items.isEmpty {
            guard !providerIds.isEmpty else {
                lines[section.header] = "\(key):"
                return nil
            }
            block.append(contentsOf: newGroupLines(name: "PROXY", providerIds: providerIds, indent: 2))
            lines.replaceSubrange(section.bodyStart..<section.end, with: block)
            lines[section.header] = "\(key):"
            warnings.append(L10n.subscriptionGroupCreated("PROXY"))
            return "PROXY"
        }

        let targetIndex: Int
        if let index = items.firstIndex(where: { $0.name.caseInsensitiveCompare("PROXY") == .orderedSame }) {
            targetIndex = index
        } else if let index = items.firstIndex(where: { $0.type.lowercased() == "select" }) {
            targetIndex = index
        } else {
            targetIndex = 0
            warnings.append(L10n.subscriptionGroupFallback)
        }

        let target = items[targetIndex]

        if isInlineGroupItem(block, item: target) {
            warnings.append(L10n.subscriptionGroupInlineUnsupported(target.name))
        } else {
            injectUse(into: &block, item: target, providerIds: providerIds, warnings: &warnings)
        }

        lines.replaceSubrange(section.bodyStart..<section.end, with: block)
        lines[section.header] = "\(key):"
        return target.name.isEmpty ? "PROXY" : target.name
    }

    private static func isInlineGroupItem(_ block: [String], item: GroupItem) -> Bool {
        guard item.start < block.count else { return false }
        let trimmed = block[item.start].trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("-") else { return false }
        let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        return content.hasPrefix("{")
    }

    private static func newGroupLines(name: String, providerIds: [String], indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        var result = [
            "\(pad)- name: \(yamlQuote(name))",
            "\(pad)  type: select",
            "\(pad)  use:"
        ]
        for id in providerIds {
            result.append("\(pad)    - \(id)")
        }
        return result
    }

    private struct GroupItem {
        let start: Int
        let end: Int
        let indent: Int
        let name: String
        let type: String
    }

    private static func parseGroupItems(_ block: [String]) -> [GroupItem] {
        var listIndent: Int?
        var starts: [Int] = []

        for (index, line) in block.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard trimmed.hasPrefix("-") else { continue }

            let indent = leadingSpaces(line)
            if listIndent == nil {
                listIndent = indent
            }
            if indent == listIndent {
                starts.append(index)
            }
        }

        guard let indent = listIndent else { return [] }

        var items: [GroupItem] = []
        for (offset, start) in starts.enumerated() {
            let end = offset + 1 < starts.count ? starts[offset + 1] : block.count
            var name = ""
            var type = ""

            for index in start..<end {
                var content = block[index].trimmingCharacters(in: .whitespaces)
                if content.hasPrefix("-") {
                    content = String(content.dropFirst()).trimmingCharacters(in: .whitespaces)
                }

                if content.hasPrefix("name:") {
                    name = yamlScalar(String(content.dropFirst("name:".count)))
                } else if content.hasPrefix("type:") {
                    type = yamlScalar(String(content.dropFirst("type:".count)))
                }

                if !name.isEmpty && !type.isEmpty { break }
            }

            items.append(GroupItem(start: start, end: end, indent: indent, name: name, type: type))
        }
        return items
    }

    private static func injectUse(into block: inout [String],
                                  item: GroupItem,
                                  providerIds: [String],
                                  warnings: inout [String]) {
        var useIndex: Int?
        for index in item.start..<item.end {
            let indent = leadingSpaces(block[index])
            let trimmed = block[index].trimmingCharacters(in: .whitespaces)
            if indent > item.indent && (trimmed.hasPrefix("use:") || trimmed.hasPrefix("use :")) {
                useIndex = index
                break
            }
        }

        guard let useIndex else {
            guard !providerIds.isEmpty else { return }

            let keyIndent = item.indent + 2
            var insert = [String(repeating: " ", count: keyIndent) + "use:"]
            for id in providerIds {
                insert.append(String(repeating: " ", count: keyIndent + 2) + "- \(id)")
            }
            block.insert(contentsOf: insert, at: item.start + 1)
            return
        }

        let line = block[useIndex]
        let indent = leadingSpaces(line)

        guard let colon = line.firstIndex(of: ":") else { return }
        let prefix = String(line[...colon])
        let rawValue = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

        // 内联列表：use: [a, b]
        if rawValue.hasPrefix("[") && rawValue.hasSuffix("]") {
            var values = rawValue
                .dropFirst()
                .dropLast()
                .split(separator: ",")
                .map { yamlScalar(String($0)) }
                .filter { !$0.isEmpty }

            values.removeAll { $0.hasPrefix(providerPrefix) }

            if providerIds.isEmpty && values.isEmpty {
                block.remove(at: useIndex)
            } else {
                values.append(contentsOf: providerIds)
                block[useIndex] = "\(prefix) [\(values.joined(separator: ", "))]"
            }
            return
        }

        if !rawValue.isEmpty && !rawValue.hasPrefix("#") {
            warnings.append(L10n.subscriptionGroupUseUnsupported(item.name))
            return
        }

        // 块状列表
        var listEnd = useIndex + 1
        while listEnd < item.end {
            let listLine = block[listEnd]
            let trimmed = listLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { break }

            let listIndent = leadingSpaces(listLine)
            if listIndent > indent && trimmed.hasPrefix("-") {
                listEnd += 1
            } else {
                break
            }
        }

        var kept: [String] = []
        var removedManaged = false
        for listLine in block[(useIndex + 1)..<listEnd] {
            let trimmed = listLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("-") {
                let value = yamlScalar(String(trimmed.dropFirst()))
                if value.hasPrefix(providerPrefix) {
                    removedManaged = true
                    continue
                }
            }
            kept.append(listLine)
        }

        if kept.isEmpty && providerIds.isEmpty && removedManaged {
            block.removeSubrange(useIndex..<listEnd)
            return
        }

        let entryIndent = indent + 2
        var additions: [String] = []
        for id in providerIds {
            additions.append(String(repeating: " ", count: entryIndent) + "- \(id)")
        }
        block.replaceSubrange((useIndex + 1)..<listEnd, with: kept + additions)
    }

    // MARK: Line helpers

    private static func topLevelSection(_ key: String, in lines: [String]) -> (header: Int, bodyStart: Int, end: Int)? {
        guard let header = lines.firstIndex(where: {
            $0.hasPrefix("\(key):") && !$0.hasPrefix(" ") && !$0.hasPrefix("\t")
        }) else {
            return nil
        }

        var end = lines.count
        for index in (header + 1)..<lines.count {
            let line = lines[index]
            if line.isEmpty { continue }
            let first = line.first!
            if first == " " || first == "\t" || first == "#" { continue }
            end = index
            break
        }
        return (header, header + 1, end)
    }

    private static func inlineValue(of line: String, key: String) -> String {
        var value = String(line.dropFirst(key.count))
        if value.hasPrefix(":") {
            value = String(value.dropFirst())
        }
        if let range = value.range(of: " #") {
            value = String(value[..<range.lowerBound])
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private static func isInlineContainerEmpty(_ value: String) -> Bool {
        value.isEmpty || value == "{}" || value == "[]" || value == "null" || value == "~"
    }

    private static func childIndent(of block: [String]) -> Int? {
        for line in block {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            return leadingSpaces(line)
        }
        return nil
    }

    private static func hasYamlContent<S: Sequence>(_ lines: S) -> Bool where S.Element == String {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            return true
        }
        return false
    }

    private static func removeManagedEntries(_ block: inout [String], prefix: String) {
        var index = 0
        while index < block.count {
            let line = block[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix(prefix) && trimmed.contains(":") {
                let indent = leadingSpaces(line)
                var end = index + 1
                while end < block.count {
                    let next = block[end]
                    let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                    if nextTrimmed.isEmpty {
                        end += 1
                        continue
                    }
                    if leadingSpaces(next) <= indent {
                        break
                    }
                    end += 1
                }
                block.removeSubrange(index..<end)
            } else {
                index += 1
            }
        }
    }

    private static func leadingSpaces(_ line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " {
                count += 1
            } else if character == "\t" {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    private static func yamlQuote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func yamlScalar(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)

        if value.hasPrefix("\"") {
            var result = ""
            var escaped = false
            for character in value.dropFirst() {
                if escaped {
                    result.append(character)
                    escaped = false
                    continue
                }
                if character == "\\" {
                    escaped = true
                    continue
                }
                if character == "\"" {
                    return result
                }
                result.append(character)
            }
            return result
        }

        if value.hasPrefix("'") {
            let body = value.dropFirst()
            if let end = body.firstIndex(of: "'") {
                return String(body[..<end])
            }
        }

        if let range = value.range(of: " #") {
            value = String(value[..<range.lowerBound])
        }
        return value.trimmingCharacters(in: .whitespaces)
    }
}
