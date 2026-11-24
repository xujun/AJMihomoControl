import Foundation

/// 语言管理
enum AppLanguage: String, Codable, CaseIterable {
    case system = "system"
    case zh = "zh"
    case en = "en"

    var displayName: String {
        switch self {
        case .system: return String(localized: "跟随系统")
        case .zh: return "中文"
        case .en: return "English"
        }
    }

    /// 获取当前实际使用的语言
    static var current: AppLanguage {
        if let saved = UserDefaults.standard.string(forKey: "AppLanguage"),
           let lang = AppLanguage(rawValue: saved) {
            return lang
        }
        return .system
    }

    /// 设置语言
    static func set(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: "AppLanguage")
    }

    /// 检测系统语言是否为中文
    private static var isSystemChinese: Bool {
        let preferred = Locale.preferredLanguages.first ?? ""
        return preferred.hasPrefix("zh")
    }

    /// 返回当前是否中文
    static var isChinese: Bool {
        switch current {
        case .system: return isSystemChinese
        case .zh: return true
        case .en: return false
        }
    }
}

// MARK: - 本地化字符串
struct L10n {
    private static let isZh = AppLanguage.isChinese

    // 菜单栏
    static let appTitle = isZh ? "Mihomo Control" : "Mihomo Control"
    static let closeProxy = isZh ? "关闭系统代理" : "Disable System Proxy"
    static let openProxy = isZh ? "开启系统代理" : "Enable System Proxy"
    static let mihomoRunning = isZh ? "Mihomo 运行中" : "Mihomo Running"
    static let mihomoStopped = isZh ? "Mihomo 已停止" : "Mihomo Stopped"
    static let restartMihomo = isZh ? "重启 Mihomo" : "Restart Mihomo"
    static let stopMihomo = isZh ? "停止 Mihomo" : "Stop Mihomo"
    static let startMihomo = isZh ? "启动 Mihomo" : "Start Mihomo"
    static let mihomoConfig = isZh ? "Mihomo配置" : "Mihomo Config"
    static let openConfigFolder = isZh ? "打开配置目录" : "Open Config Folder"
    static let openControlPanel = isZh ? "打开控制面板" : "Open Control Panel"
    static let about = isZh ? "关于" : "About"
    static let language = isZh ? "语言" : "Language"
    static let quit = isZh ? "退出" : "Quit"

    // 控制面板
    static let controlPanelTitle = isZh ? "控制面板" : "Control Panel"
    static let proxySection = isZh ? "系统代理" : "System Proxy"
    static let proxyOn = isZh ? "代理中" : "Proxy On"
    static let proxyOff = isZh ? "未代理" : "Proxy Off"
    static let enable = isZh ? "启用" : "Enable"
    static let disable = isZh ? "停用" : "Disable"
    static let mihomoSection = isZh ? "Mihomo" : "Mihomo"
    static let running = isZh ? "运行中" : "Running"
    static let stopped = isZh ? "已停止" : "Stopped"
    static let restart = isZh ? "重启" : "Restart"
    static let stop = isZh ? "停止" : "Stop"
    static let start = isZh ? "启动" : "Start"

    // 配置窗口
    static let mihomoConfigTitle = isZh ? "Mihomo配置" : "Mihomo Config"
    static let mihomoConfigSection = isZh ? "Mihomo 配置" : "Mihomo Configuration"
    static let binaryPath = isZh ? "程序路径" : "Binary Path"
    static let configPath = isZh ? "配置文件" : "Config File"
    static let workingDir = isZh ? "工作目录" : "Working Directory"
    static let select = isZh ? "选择" : "Browse"
    static let saveSettings = isZh ? "保存设置" : "Save Settings"
    static let settingsSaved = isZh ? "设置已保存" : "Settings saved"

    // 关于窗口
    static let aboutTitle = isZh ? "关于" : "About"
    static let version = isZh ? "版本" : "Version"
    static let appDescription = isZh ? "一个 macOS 菜单栏应用\n用于控制 mihomo 代理和系统代理设置" : "A macOS menu bar app\nfor controlling mihomo proxy and system proxy settings."
    static let authorLabel = isZh ? "作者" : "Author"
    static let authorName = "xujun"
    static let authorLink = "https://github.com/xujun"
    static let contactEmail = "5798473@qq.com"
    static let quickStart = isZh ? "快速开始" : "Quick Start"
    static let step1 = isZh ? "1. 安装 mihomo：`brew install mihomo`" : "1. Install mihomo: `brew install mihomo`"
    static let step2 = isZh ? "2. 配置文件位于 `/usr/local/etc/mihomo/config.yaml`" : "2. Config file at `/usr/local/etc/mihomo/config.yaml`"
    static let step3 = isZh ? "3. 启动本应用 — 自动启动 mihomo 并开启代理" : "3. Launch this app — auto-starts mihomo and proxy"

    // 提示
    static let proxyOnTip = isZh ? "Mihomo Control - 代理已开启" : "Mihomo Control - Proxy ON"
    static let proxyOffTip = isZh ? "Mihomo Control - 代理未开启" : "Mihomo Control - Proxy OFF"

    // 代理切换
    static let proxySwitcherSection = isZh ? "代理服务器" : "Proxy Servers"
    static let refreshProxyList = isZh ? "刷新列表" : "Refresh"
    static let testAllDelays = isZh ? "测试延迟" : "Test Delays"
    static let noProxyGroups = isZh ? "无可用服务器" : "No available servers"
    static let apiUnreachable = isZh ? "无法连接到 mihomo API" : "Cannot connect to mihomo API"
    static let retry = isZh ? "重试" : "Retry"
    static let switching = isZh ? "切换中..." : "Switching..."
    static let apiSecretLabel = isZh ? "API 密钥" : "API Secret"
    static let proxyTypeSelect = isZh ? "选择" : "Select"
    static let proxyTypeFallback = isZh ? "回退" : "Fallback"
    static let proxyTypeURLTest = isZh ? "自动测速" : "URLTest"
    static let delayMs = isZh ? "毫秒" : "ms"
    static let delayTimeout = isZh ? "超时" : "Timeout"
    static let noDelay = isZh ? "未测试" : "Not tested"

    // 订阅
    static let subscriptionEmpty = isZh ? "暂无订阅，添加订阅链接以导入节点。" : "No subscriptions yet. Add a URL to import nodes."
    static let subscriptionPlaceholder = isZh ? "https://example.com/subscription" : "https://example.com/subscription"
    static let addAndApply = isZh ? "添加并应用" : "Add & Apply"
    static let applySubscriptions = isZh ? "更新并应用" : "Update & Apply"
    static let subscriptionHelp = isZh ? "订阅节点会导入到 proxies，之后可在下方像普通代理一样切换、修改和删除。应用后会重启 mihomo，原配置备份为 config.yaml.ajbak。" : "Subscription nodes are imported into proxies and can then be switched, edited and deleted like normal proxies below. Applying restarts mihomo and backs up the config to config.yaml.ajbak."
    static let subscriptionInvalidURL = isZh ? "请输入有效的 http(s) 订阅链接" : "Please enter a valid http(s) subscription URL"
    static let subscriptionExists = isZh ? "该订阅已存在" : "This subscription already exists"
    static let subscriptionAdded = isZh ? "已添加订阅，点击“更新并应用”生效" : "Subscription added. Click \"Update & Apply\" to activate."
    static let subscriptionConfigMissing = isZh ? "未找到 mihomo 配置文件" : "mihomo config file not found"
    static let subscriptionApplySuccess = isZh ? "订阅已写入配置，正在重启 mihomo" : "Subscriptions written to config, restarting mihomo"
    static let subscriptionApplyUnchanged = isZh ? "配置已是最新，无需修改" : "Config is already up to date"
    static let subscriptionApplyFailed = isZh ? "写入配置失败" : "Failed to write config"
    static let subscriptionCleared = isZh ? "已移除订阅节点" : "Subscription nodes removed"
    static let subscriptionNoNodes = isZh ? "未获取到节点" : "No nodes loaded"
    static let subscriptionNotLoaded = isZh ? "未加载" : "Not loaded"
    static let subscriptionNodeCount = isZh ? "%d 个节点" : "%d nodes"
    static let deleteSubscription = isZh ? "删除订阅" : "Delete subscription"
    static let subscriptionGroupFallback = isZh ? "未找到 PROXY 或 select 分组，已将订阅注入第一个分组" : "No PROXY or select group found; injected subscriptions into the first group"

    static func subscriptionInlineUnsupported(_ key: String) -> String {
        isZh ? "\(key) 使用了内联写法，已跳过订阅写入" : "\(key) uses inline syntax; subscription injection skipped"
    }

    static func subscriptionGroupCreated(_ name: String) -> String {
        isZh ? "未找到策略组，已自动创建 \(name)，请确认规则引用该分组" : "No proxy group found; created \(name). Make sure rules reference it"
    }

    static func subscriptionGroupUseUnsupported(_ name: String) -> String {
        isZh ? "策略组 \(name) 的 use 字段格式不支持，已跳过订阅注入" : "Group \(name) has an unsupported use format; subscription injection skipped"
    }

    static func subscriptionGroupInlineUnsupported(_ name: String) -> String {
        isZh ? "策略组 \(name) 使用了内联写法，已跳过订阅注入" : "Group \(name) uses inline syntax; subscription injection skipped"
    }

    // 代理服务器配置
    static let proxyConfigHelp = isZh ? "在这里切换、添加、修改或删除代理服务器。保存后会重启 mihomo，原配置备份为 config.yaml.ajbak。" : "Switch, add, edit or delete proxy servers here. Saving restarts mihomo and backs up the config to config.yaml.ajbak."
    static let proxyListEmpty = isZh ? "暂无代理服务器" : "No proxy servers"
    static let addProxy = isZh ? "添加" : "Add"
    static let editProxy = isZh ? "修改" : "Edit"
    static let deleteProxy = isZh ? "删除" : "Delete"
    static let proxyEditorTitleAdd = isZh ? "添加代理服务器" : "Add Proxy Server"
    static let proxyEditorTitleEdit = isZh ? "修改代理服务器" : "Edit Proxy Server"
    static let proxyYAMLLabel = isZh ? "代理配置（YAML）" : "Proxy config (YAML)"
    static let proxyYAMLHint = isZh ? "name、type、server、port 必填；其余字段按 mihomo 代理格式填写。" : "name, type, server and port are required. Other fields follow mihomo proxy syntax."
    static let saveProxy = isZh ? "保存并应用" : "Save & Apply"
    static let cancel = isZh ? "取消" : "Cancel"
    static let proxyNameExists = isZh ? "代理名称已存在" : "Proxy name already exists"
    static let proxyInvalid = isZh ? "请至少填写 name、type、server、port" : "Please fill in name, type, server and port"
    static let proxyWriteFailed = isZh ? "写入配置失败" : "Failed to write config"
    static let proxyAdded = isZh ? "代理服务器已添加，正在重启 mihomo" : "Proxy server added, restarting mihomo"
    static let proxyUpdated = isZh ? "代理服务器已修改，正在重启 mihomo" : "Proxy server updated, restarting mihomo"
    static let proxyDeleted = isZh ? "代理服务器已删除，正在重启 mihomo" : "Proxy server deleted, restarting mihomo"
    static let proxyReload = isZh ? "重新载入" : "Reload"

    static func proxyDeleteTitle(_ name: String) -> String {
        isZh ? "删除代理服务器“\(name)”？" : "Delete proxy server \"\(name)\"?"
    }
    static func proxyDeleteMessage(_ name: String) -> String {
        isZh ? "将从 config.yaml 的 proxies 和策略组引用中移除该节点。" : "This node will be removed from proxies and proxy group references in config.yaml."
    }
}
