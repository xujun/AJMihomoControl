//
//  ProxySwitcherView.swift
//  AJMihomoControl
//
//  Created by xujun (https://github.com/xujun)
//  Copyright © 2026 xujun. All rights reserved.
//

import SwiftUI
#if os(macOS)
import Cocoa
#endif

// MARK: - 代理切换主视图
struct ProxySwitcherView: View {
    @ObservedObject var mihomoAPI: MihomoAPI

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶部工具栏
            HStack {
                Button(action: { mihomoAPI.fetchProxies() }) {
                    Label(L10n.refreshProxyList, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(mihomoAPI.isLoading)

                Button(action: { mihomoAPI.testAllDelays() }) {
                    Label(mihomoAPI.isTestingDelay ? L10n.switching : L10n.testAllDelays, systemImage: "timer")
                }
                .buttonStyle(.bordered)
                .disabled(mihomoAPI.isLoading || mihomoAPI.proxyServers.isEmpty || mihomoAPI.isTestingDelay)

                Spacer()

                if mihomoAPI.isLoading || mihomoAPI.isTestingDelay {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }
            }

            // 内容区
            if let error = mihomoAPI.errorMessage {
                // 错误状态
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button(L10n.retry) { mihomoAPI.fetchProxies() }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
                .padding(12)
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
                )
            } else if mihomoAPI.proxyServers.isEmpty && !mihomoAPI.isLoading {
                // 空状态
                HStack {
                    Image(systemName: "server.rack")
                        .foregroundColor(.secondary)
                    Text(L10n.noProxyGroups)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            } else {
                // 代理服务器列表
                VStack(spacing: 0) {
                    ForEach(mihomoAPI.proxyServers) { server in
                        ProxyServerRow(
                            server: server,
                            isSelected: mihomoAPI.currentProxy == server.name,
                            delay: mihomoAPI.delayCache[server.name],
                            onSelect: {
                                mihomoAPI.switchProxy(name: server.name)
                            }
                        )
                        if server.id != mihomoAPI.proxyServers.last?.id {
                            Divider()
                                .padding(.leading, 28)
                        }
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
        }
    }
}

// MARK: - 代理服务器行
struct ProxyServerRow: View {
    let server: ProxyInfo
    let isSelected: Bool
    let delay: Int?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                // 第一列：选中标记 + 代理名称（靠左对齐）
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .frame(width: 12)

                    Text(server.name)
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .help(server.name)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 第二列：延迟标签（靠左对齐）
                HStack {
                    if let delay = delay {
                        DelayView(delay: delay)
                    } else {
                        Text("—")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 80, alignment: .leading)

                // 第三列：代理类型（靠右对齐）
                TypeBadge(type: server.type)
                    .frame(alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 类型徽章
struct TypeBadge: View {
    let type: String

    var body: some View {
        Text(type)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(typeColor.opacity(0.15))
            .foregroundColor(typeColor)
            .cornerRadius(4)
    }

    private var typeColor: Color {
        switch type {
        case "Shadowsocks": return .blue
        case "Vmess": return .purple
        case "Trojan": return .orange
        case "Hysteria", "Hysteria2": return .pink
        case "VLESS": return .cyan
        case "TUIC": return .green
        default: return .gray
        }
    }
}

// MARK: - 延迟显示
struct DelayView: View {
    let delay: Int  // 毫秒，0 表示超时

    var body: some View {
        if delay == 0 {
            Text(L10n.delayTimeout)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.red)
        } else {
            Text("\(delay)\(L10n.delayMs)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(delayColor)
        }
    }

    private var delayColor: Color {
        if delay < 200 { return .green }
        if delay < 500 { return .orange }
        return .red
    }
}
