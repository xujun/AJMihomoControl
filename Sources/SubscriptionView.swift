//
//  SubscriptionView.swift
//  AJMihomoControl
//
//  Created by xujun (https://github.com/xujun)
//  Copyright © 2026 xujun. All rights reserved.
//

import SwiftUI

// MARK: - 订阅设置区块

struct SubscriptionSectionView: View {
    @ObservedObject var manager: SubscriptionManager
    @ObservedObject var mihomoManager: MihomoManager
    @ObservedObject var mihomoAPI: MihomoAPI
    var onApplied: (() -> Void)? = nil

    @State private var newURL = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if manager.subscriptions.isEmpty {
                Text(L10n.subscriptionEmpty)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(manager.subscriptions) { subscription in
                        SubscriptionRow(
                            subscription: subscription,
                            manager: manager,
                            onApply: applyOnly,
                            onRemove: {
                                manager.remove(subscription)
                                applyOnly()
                            }
                        )
                    }
                }
            }

            HStack(spacing: 6) {
                TextField(L10n.subscriptionPlaceholder, text: $newURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .onSubmit { addAndApply() }

                Button(L10n.addAndApply) {
                    addAndApply()
                }
                .buttonStyle(.bordered)
                .disabled(newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 8) {
                Button(action: applyOnly) {
                    Text(L10n.applySubscriptions)
                        .frame(maxWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.subscriptions.isEmpty || manager.isApplying)

                if manager.isApplying {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                if let message = manager.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(manager.statusIsError ? .red : .secondary)
                        .lineLimit(2)
                }
            }

            Text(L10n.subscriptionHelp)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private func addAndApply() {
        let url = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        if manager.add(url: url) {
            newURL = ""
            applyOnly()
        }
    }

    private func applyOnly() {
        manager.apply { outcome in
            guard outcome.success else { return }
            onApplied?()
            guard mihomoManager.isRunning else {
                mihomoAPI.fetchProxies()
                return
            }

            mihomoManager.restart()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                onApplied?()
                mihomoAPI.fetchProxies()
            }
        }
    }
}

// MARK: - 单条订阅

private struct SubscriptionRow: View {
    let subscription: Subscription
    @ObservedObject var manager: SubscriptionManager
    let onApply: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { subscription.enabled },
                set: {
                    manager.setEnabled(subscription, enabled: $0)
                    onApply()
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 1) {
                Text(subscription.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(subscription.displayURL)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 4)

            if let error = subscription.lastError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .lineLimit(1)
            } else if let count = subscription.nodeCount, count > 0 {
                Text(String(format: L10n.subscriptionNodeCount, count))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Button {
                onRemove()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(L10n.deleteSubscription)
        }
    }
}
