//
//  SettingsView.swift
//  AJMihomoControl
//
//  Created by xujun (https://github.com/xujun)
//  Copyright © 2026 xujun. All rights reserved.
//

import SwiftUI

// MARK: - 控制面板窗口（仅代理状态 + Mihomo 状态）
struct SettingsView: View {
    @ObservedObject var proxyManager: ProxyManager
    @ObservedObject var mihomoManager: MihomoManager
    @State private var config = AppConfig.load()

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ========== 系统代理 ==========
                    SettingsSection(L10n.proxySection) {
                        ProxyStatusCard(
                            proxyManager: proxyManager,
                            proxyHost: config.proxyHost,
                            proxyPort: config.proxyPort,
                            onEnable: {
                                if !mihomoManager.isRunning {
                                    mihomoManager.start()
                                }
                                proxyManager.enable()
                            },
                            onDisable: {
                                proxyManager.disable()
                            }
                        )
                    }

                    Spacer().frame(height: (geo.size.height - 280) / 2)

                    // ========== Mihomo ==========
                    SettingsSection(L10n.mihomoSection) {
                        MihomoStatusCard(
                            isRunning: mihomoManager.isRunning,
                            pid: mihomoManager.pid,
                            onStart: {
                                if !mihomoManager.isRunning {
                                    mihomoManager.start()
                                }
                                if !proxyManager.isEnabled {
                                    proxyManager.enable()
                                }
                            },
                            onStop: {
                                proxyManager.disable()
                                mihomoManager.stop()
                            },
                            onRestart: {
                                mihomoManager.restart()
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 2)
            }
        }
        .frame(minHeight: 260)
    }
}

// MARK: - Mihomo 配置窗口
struct MihomoConfigView: View {
    @ObservedObject var proxyManager: ProxyManager
    @ObservedObject var mihomoManager: MihomoManager
    @State private var config = AppConfig.load()
    @State private var hasChanges = false
    @State private var saveMessage: String?
    @State private var saveSuccess = false

    var body: some View {
        VStack(spacing: 0) {
            // ========== 内容区 ==========
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSection(L10n.mihomoConfigSection) {
                        LabeledPath(L10n.binaryPath, text: $config.mihomoBinaryPath, allowsFiles: true) { hasChanges = true }
                        LabeledPath(L10n.configPath, text: $config.mihomoConfigPath, allowsFiles: true) { hasChanges = true }
                        LabeledPath(L10n.workingDir, text: $config.mihomoHome, allowsFiles: false) { hasChanges = true }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 2)
            }

            // ========== 底部操作栏 ==========
            Divider()
            HStack {
                if let msg = saveMessage {
                    Label(msg, systemImage: saveSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(saveSuccess ? .green : .red)
                        .font(.caption)
                        .transition(.opacity)
                }
                Spacer()
                Button(action: handleSave) {
                    Text(L10n.saveSettings)
                        .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!hasChanges)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 580, idealWidth: 620, minHeight: 300)
        .onAppear { saveMessage = nil }
    }

    private func handleSave() {
        saveMessage = nil
        saveSuccess = false

        config.save()
        hasChanges = false
        saveSuccess = true
        saveMessage = L10n.settingsSaved

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if saveSuccess {
                withAnimation { saveMessage = nil }
            }
        }
    }
}

// MARK: - 关于页面（菜单栏中显示）
struct AboutMenuContent: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "network")
                .font(.system(size: 32))
                .foregroundColor(.accentColor)

            Text("Mihomo Control")
                .font(.headline)
            Text("\(L10n.version) 1.0.0")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.step1)
                Text(L10n.step2)
                Text(L10n.step3)
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }
}

// MARK: - 代理状态卡片
struct ProxyStatusCard: View {
    @ObservedObject var proxyManager: ProxyManager
    let proxyHost: String
    let proxyPort: Int
    let onEnable: () -> Void
    let onDisable: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(proxyManager.isEnabled ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                    .frame(width: 40, height: 40)
                Circle()
                    .strokeBorder(proxyManager.isEnabled ? Color.green : Color.red, lineWidth: 2)
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(proxyManager.isEnabled ? Color.green : Color.red)
                    .frame(width: 14, height: 14)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(proxyManager.isEnabled ? L10n.proxyOn : L10n.proxyOff)
                    .font(.headline)
                    .foregroundColor(proxyManager.isEnabled ? .green : .red)
                if proxyManager.isEnabled {
                    Text("\(proxyHost):\(String(proxyPort))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onEnable) {
                    Text(L10n.enable)
                        .frame(maxWidth: 60)
                }
                .buttonStyle(.borderedProminent)
                .disabled(proxyManager.isEnabled)

                Button(action: onDisable) {
                    Text(L10n.disable)
                        .frame(maxWidth: 60)
                }
                .buttonStyle(.bordered)
                .disabled(!proxyManager.isEnabled)
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

// MARK: - 状态卡片（Mihomo）
struct MihomoStatusCard: View {
    let isRunning: Bool
    let pid: Int32
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isRunning ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: isRunning ? "play.fill" : "stop.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isRunning ? .green : .red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isRunning ? L10n.running : L10n.stopped)
                    .font(.headline)
                    .foregroundColor(isRunning ? .green : .red)
                if isRunning {
                    Text("PID: \(String(pid))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if isRunning {
                    Button(action: onRestart) {
                        Text(L10n.restart)
                            .frame(maxWidth: 60)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onStop) {
                        Text(L10n.stop)
                            .frame(maxWidth: 60)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: onStart) {
                        Text(L10n.start)
                            .frame(maxWidth: 60)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: onStop) {
                        Text(L10n.stop)
                            .frame(maxWidth: 60)
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

// MARK: - 通用设置区块
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 标签 + 输入框
struct LabeledField: View {
    let label: String
    let field: FieldType
    var onChange: (() -> Void)?

    enum FieldType {
        case text(Binding<String>)
        case int(Binding<Int>)
    }

    init(_ label: String, _ field: FieldType, onChange: (() -> Void)? = nil) {
        self.label = label
        self.field = field
        self.onChange = onChange
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 50, alignment: .trailing)
                .foregroundColor(.secondary)

            switch field {
            case .text(let binding):
                TextField("", text: binding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 130)
                    .onChange(of: binding.wrappedValue) { onChange?() }
            case .int(let binding):
                TextField("", value: binding, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onChange(of: binding.wrappedValue) { onChange?() }
            }
        }
    }
}

// MARK: - 标签 + 路径选择
struct LabeledPath: View {
    let label: String
    @Binding var text: String
    let allowsFiles: Bool
    var onChange: (() -> Void)?

    init(_ label: String, text: Binding<String>, allowsFiles: Bool, onChange: (() -> Void)? = nil) {
        self.label = label
        self._text = text
        self.allowsFiles = allowsFiles
        self.onChange = onChange
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .fixedSize()
                .lineLimit(1)
                .foregroundColor(.secondary)
            TextField("路径", text: $text)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .onChange(of: text) { onChange?() }
            Button(L10n.select) {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                if allowsFiles {
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    panel.allowedContentTypes = [.yaml, .executable]
                } else {
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                }
                if panel.runModal() == .OK, let url = panel.url {
                    text = url.path
                    onChange?()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 22)
    }
}
