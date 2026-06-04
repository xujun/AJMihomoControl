//
//  AppDelegate.swift
//  AJMihomoControl
//
//  Created by xujun (https://github.com/xujun)
//  Copyright © 2026 xujun. All rights reserved.
//

import Cocoa
import SwiftUI
import Combine

@main
struct MihomoControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Pure menu-bar app
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let proxyManager = ProxyManager()
    let mihomoManager = MihomoManager()
    private var statusItem: NSStatusItem!
    private var controlWindow: NSWindow?
    private var mihomoConfigWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var customButton: ClickableStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Create custom clickable status item
        customButton = ClickableStatusItem(
            onLeftClick: { [weak self] in
                self?.openSettingsWindow()
            },
            onRightClick: { [weak self] in
                self?.showMenu()
            }
        )
        updateIcon()

        // Observe proxy state changes to update icon in real-time
        proxyManager.$isEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIcon()
            }
            .store(in: &cancellables)

        // 启动 mihomo（如果配置文件存在）
        let config = AppConfig.load()
        if FileManager.default.fileExists(atPath: config.resolvedMihomoConfigPath) {
            mihomoManager.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                if self?.mihomoManager.isRunning == true {
                    self?.proxyManager.enable()
                }
            }
        }

        // 启动时打开设置窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.openSettingsWindow()
        }
    }

    // MARK: - Icon

    func updateIcon() {
        guard let customButton = customButton else { return }
        if proxyManager.isEnabled {
            let image = NSImage(systemSymbolName: "network", accessibilityDescription: nil)
            image?.isTemplate = true
            customButton.setImage(image)
            customButton.setToolTip(L10n.proxyOnTip)
        } else {
            let image = NSImage(systemSymbolName: "network.slash", accessibilityDescription: nil)
            image?.isTemplate = true
            customButton.setImage(image)
            customButton.setToolTip(L10n.proxyOffTip)
        }
    }

    // MARK: - Menu

    private func clearMenuItemIcon(_ item: NSMenuItem) {
        let transparentImage = NSImage(size: NSSize(width: 1, height: 1))
        transparentImage.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: NSSize(width: 1, height: 1)).fill()
        transparentImage.unlockFocus()
        item.image = transparentImage
    }

    private func showMenu() {
        let menu = NSMenu()

        // Status header
        let statusItem = NSMenuItem(title: L10n.appTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        clearMenuItemIcon(statusItem)
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        // Toggle proxy
        let toggleTitle = proxyManager.isEnabled ? L10n.closeProxy : L10n.openProxy
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleProxy), keyEquivalent: "")
        toggleItem.target = self
        clearMenuItemIcon(toggleItem)
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // Mihomo status
        let mihomoStatusText = mihomoManager.isRunning ? L10n.mihomoRunning : L10n.mihomoStopped
        let mihomoStatusItem = NSMenuItem(title: mihomoStatusText, action: nil, keyEquivalent: "")
        mihomoStatusItem.isEnabled = false
        clearMenuItemIcon(mihomoStatusItem)
        menu.addItem(mihomoStatusItem)

        if mihomoManager.isRunning {
            let restartItem = NSMenuItem(title: L10n.restartMihomo, action: #selector(restartMihomo), keyEquivalent: "")
            restartItem.target = self
            clearMenuItemIcon(restartItem)
            menu.addItem(restartItem)

            let stopItem = NSMenuItem(title: L10n.stopMihomo, action: #selector(stopMihomo), keyEquivalent: "")
            stopItem.target = self
            clearMenuItemIcon(stopItem)
            menu.addItem(stopItem)
        } else {
            let startItem = NSMenuItem(title: L10n.startMihomo, action: #selector(startMihomo), keyEquivalent: "")
            startItem.target = self
            clearMenuItemIcon(startItem)
            menu.addItem(startItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Mihomo 配置
        let configItem = NSMenuItem(title: L10n.mihomoConfig, action: #selector(openMihomoConfig), keyEquivalent: "")
        configItem.target = self
        clearMenuItemIcon(configItem)
        menu.addItem(configItem)

        // 打开配置目录
        let folderItem = NSMenuItem(title: L10n.openConfigFolder, action: #selector(openConfigFolder), keyEquivalent: "")
        folderItem.target = self
        clearMenuItemIcon(folderItem)
        menu.addItem(folderItem)

        // 打开控制面板
        let panelItem = NSMenuItem(title: L10n.openControlPanel, action: #selector(openSettings), keyEquivalent: ",")
        panelItem.target = self
        clearMenuItemIcon(panelItem)
        menu.addItem(panelItem)

        menu.addItem(NSMenuItem.separator())

        // Language submenu
        let langMenu = NSMenu()
        for lang in AppLanguage.allCases {
            let isSelected = lang == AppLanguage.current
            let title = "\(isSelected ? "✓ " : "  ")\(lang.displayName)"
            let langItem = NSMenuItem(title: title, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            langItem.target = self
            langItem.representedObject = lang.rawValue
            langItem.image = nil
            langMenu.addItem(langItem)
        }
        let langItem = NSMenuItem(title: L10n.language, action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        langItem.image = nil
        menu.addItem(langItem)

        menu.addItem(NSMenuItem.separator())

        // About
        let aboutItem = NSMenuItem(title: L10n.about, action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        clearMenuItemIcon(aboutItem)
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        clearMenuItemIcon(quitItem)
        menu.addItem(quitItem)

        customButton?.showMenu(menu)
    }

    // MARK: - Control Panel Window

    func openSettingsWindow() {
        if let window = controlWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 340),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.controlPanelTitle
        window.center()
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 580, height: 340)

        let rootView = SettingsView(
            proxyManager: proxyManager,
            mihomoManager: mihomoManager
        )

        let hostingView = NSHostingView(rootView: rootView)
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controlWindow = window
    }

    // MARK: - Mihomo Config Window

    func openMihomoConfigWindow() {
        if let window = mihomoConfigWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.mihomoConfigTitle
        window.center()
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 580, height: 260)

        let rootView = MihomoConfigView(
            proxyManager: proxyManager,
            mihomoManager: mihomoManager
        )

        let hostingView = NSHostingView(rootView: rootView)
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mihomoConfigWindow = window
    }

    // MARK: - About Window

    func openAboutWindow() {
        if let window = aboutWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 240),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "关于"
        window.center()
        window.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: AboutMenuContent())
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow = window
    }
}

// MARK: - Actions
extension AppDelegate {
    @objc func toggleProxy() {
        if proxyManager.isEnabled {
            proxyManager.disable()
        } else {
            if !mihomoManager.isRunning {
                mihomoManager.start()
            }
            proxyManager.enable()
        }
    }

    @objc func startMihomo() {
        mihomoManager.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.proxyManager.enable()
        }
    }

    @objc func stopMihomo() {
        proxyManager.disable()
        mihomoManager.stop()
    }

    @objc func restartMihomo() {
        mihomoManager.restart()
    }

    @objc func toggleInterface(_ sender: NSMenuItem) {
        guard let interface = sender.representedObject as? String else { return }
        if proxyManager.isInterfaceEnabled(interface) {
            proxyManager.disableInterface(interface)
        } else {
            proxyManager.enableInterface(interface)
        }
    }

    @objc func openConfigFolder() {
        let config = AppConfig.load()
        let folderURL = URL(fileURLWithPath: config.resolvedMihomoConfigPath).deletingLastPathComponent()
        NSWorkspace.shared.open(folderURL)
    }

    @objc func openSettings() {
        openSettingsWindow()
    }

    @objc func openMihomoConfig() {
        openMihomoConfigWindow()
    }

    @objc func openAbout() {
        openAboutWindow()
    }

    @objc func changeLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = AppLanguage(rawValue: raw) else { return }
        AppLanguage.set(lang)

        // Close all windows so they reopen with new language
        controlWindow?.close()
        controlWindow = nil
        mihomoConfigWindow?.close()
        mihomoConfigWindow = nil
        aboutWindow?.close()
        aboutWindow = nil

        // Reopen control panel
        openSettingsWindow()
    }
}

// MARK: - Custom Status Item with Click Handling

class ClickableStatusItem {
    private let statusItem: NSStatusItem
    private let onLeftClick: () -> Void
    private let onRightClick: () -> Void

    init(onLeftClick: @escaping () -> Void, onRightClick: @escaping () -> Void) {
        self.onLeftClick = onLeftClick
        self.onRightClick = onRightClick
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem.behavior = .removalAllowed

        let button = self.statusItem.button!
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleClick(_ sender: Any) {
        guard let event = NSApp.currentEvent else { return }
        switch event.type {
        case .leftMouseUp:
            onLeftClick()
        case .rightMouseUp:
            onRightClick()
        default:
            break
        }
    }

    func setImage(_ image: NSImage?) {
        statusItem.button?.image = image
    }

    func setToolTip(_ text: String) {
        statusItem.button?.toolTip = text
    }

    func showMenu(_ menu: NSMenu) {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}
