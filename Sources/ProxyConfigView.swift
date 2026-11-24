//
//  ProxyConfigView.swift
//  AJMihomoControl
//

import SwiftUI

struct ProxyConfigWindowView: View {
    @ObservedObject var manager: ProxyConfigManager
    @ObservedObject var subscriptionManager: SubscriptionManager
    @ObservedObject var mihomoManager: MihomoManager
    @ObservedObject var mihomoAPI: MihomoAPI

    @State private var editor: ProxyEditorState?
    @State private var pendingDelete: DeleteTarget?

    private static let template = """
    name: "New Proxy"
    type: hysteria2
    server: 1.2.3.4
    port: 443
    password: ""
    sni: ""
    skip-cert-verify: true
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.proxyConfigHelp)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            SubscriptionSectionView(
                manager: subscriptionManager,
                mihomoManager: mihomoManager,
                mihomoAPI: mihomoAPI,
                onApplied: { manager.reload() }
            )

            HStack(spacing: 8) {
                Button {
                    manager.reload()
                    editor = ProxyEditorState(index: nil, raw: Self.template,
                                              title: L10n.proxyEditorTitleAdd)
                } label: {
                    Label(L10n.addProxy, systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    manager.reload()
                } label: {
                    Label(L10n.proxyReload, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Spacer()

                if let message = manager.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(manager.statusIsError ? .red : .secondary)
                        .lineLimit(2)
                }
            }

            if manager.proxies.isEmpty {
                HStack {
                    Image(systemName: "server.rack").foregroundColor(.secondary)
                    Text(L10n.proxyListEmpty).font(.caption).foregroundColor(.secondary)
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
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(manager.proxies.enumerated()), id: \.offset) { index, proxy in
                            HStack(spacing: 8) {
                                Image(systemName: mihomoAPI.currentProxy == proxy.name
                                      ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 10))
                                    .foregroundColor(mihomoAPI.currentProxy == proxy.name
                                                     ? .accentColor : .secondary)
                                    .frame(width: 12)

                                Button {
                                    mihomoAPI.switchProxy(name: proxy.name)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(proxy.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(1)
                                        Text("\(proxy.server):\(proxy.port)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(L10n.proxySwitcherSection)

                                Spacer()

                                TypeBadge(type: proxy.type)

                                Button {
                                    editor = ProxyEditorState(index: index, raw: proxy.raw,
                                                              title: L10n.proxyEditorTitleEdit)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                                .help(L10n.editProxy)

                                Button {
                                    pendingDelete = DeleteTarget(index: index, name: proxy.name)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                                .help(L10n.deleteProxy)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)

                            if index < manager.proxies.count - 1 {
                                Divider().padding(.leading, 10)
                            }
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
        .padding(16)
        .frame(minWidth: 560, minHeight: 320)
        .onAppear {
            manager.reload()
            if manager.proxies.isEmpty && subscriptionManager.hasLegacyProviderConfig && !subscriptionManager.isApplying {
                subscriptionManager.apply { _ in
                    manager.reload()
                    guard mihomoManager.isRunning else { return }
                    mihomoManager.restart()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        manager.reload()
                        mihomoAPI.fetchProxies()
                    }
                }
            }
        }
        .sheet(item: $editor) { state in
            ProxyEditorSheet(
                title: state.title,
                text: state.raw,
                manager: manager,
                onSave: { raw in
                    handleSave(index: state.index, raw: raw)
                }
            )
        }
        .alert(item: $pendingDelete) { target in
            Alert(
                title: Text(L10n.proxyDeleteTitle(target.name)),
                message: Text(L10n.proxyDeleteMessage(target.name)),
                primaryButton: .destructive(Text(L10n.deleteProxy)) {
                    if manager.remove(index: target.index) {
                        restartAndRefresh()
                    }
                },
                secondaryButton: .cancel(Text(L10n.cancel))
            )
        }
    }

    private func handleSave(index: Int?, raw: String) -> Bool {
        let success = index == nil
            ? manager.add(raw: raw)
            : manager.update(index: index!, raw: raw)
        if success { restartAndRefresh() }
        return success
    }

    private func restartAndRefresh() {
        guard mihomoManager.isRunning else {
            mihomoAPI.fetchProxies()
            return
        }
        mihomoManager.restart()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            manager.reload()
            mihomoAPI.fetchProxies()
        }
    }
}

private struct ProxyEditorState: Identifiable {
    let id = UUID()
    let index: Int?
    let raw: String
    let title: String
}

private struct DeleteTarget: Identifiable {
    let id = UUID()
    let index: Int
    let name: String
}

private struct ProxyEditorSheet: View {
    let title: String
    @State var text: String
    @ObservedObject var manager: ProxyConfigManager
    let onSave: (String) -> Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)

            Text(L10n.proxyYAMLLabel)
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 500, minHeight: 280)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )

            Text(L10n.proxyYAMLHint)
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                if let message = manager.statusMessage, manager.statusIsError {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }

                Spacer()

                Button(L10n.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(L10n.saveProxy) {
                    if onSave(text) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 540)
    }
}