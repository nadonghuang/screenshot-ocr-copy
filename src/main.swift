import Cocoa
import ApplicationServices
import Vision
import Carbon.HIToolbox
import ServiceManagement
import UserNotifications
import ScreenCaptureKit

// MARK: - App Settings (persisted in UserDefaults)

struct AppSettings {
    var keyCode: UInt32
    var modifiers: UInt
    var soundEnabled: Bool
    var notificationEnabled: Bool
    var borderWidth: CGFloat

    static let `default` = AppSettings(
        keyCode: UInt32(31),  // kVK_ANSI_O
        modifiers: UInt(NSEvent.ModifierFlags([.command, .control]).rawValue),
        soundEnabled: true,
        notificationEnabled: true,
        borderWidth: 2
    )

    static func load() -> AppSettings {
        let d = UserDefaults.standard
        return AppSettings(
            keyCode: d.object(forKey: "hotkeyKeyCode") as? UInt32 ?? Self.default.keyCode,
            modifiers: d.object(forKey: "hotkeyModifiers") as? UInt ?? Self.default.modifiers,
            soundEnabled: d.object(forKey: "soundEnabled") as? Bool ?? Self.default.soundEnabled,
            notificationEnabled: d.object(forKey: "notifEnabled") as? Bool ?? Self.default.notificationEnabled,
            borderWidth: CGFloat(d.object(forKey: "borderWidth") as? Double ?? Double(Self.default.borderWidth))
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(keyCode, forKey: "hotkeyKeyCode")
        d.set(modifiers, forKey: "hotkeyModifiers")
        d.set(soundEnabled, forKey: "soundEnabled")
        d.set(notificationEnabled, forKey: "notifEnabled")
        d.set(Double(borderWidth), forKey: "borderWidth")
    }

    var displayString: String {
        var s = ""
        let mods = NSEvent.ModifierFlags(rawValue: modifiers)
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option) { s += "⌥" }
        if mods.contains(.shift) { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        s += keyCodeToString(keyCode)
        return s
    }

    private func keyCodeToString(_ code: UInt32) -> String {
        let m: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9", UInt32(kVK_Space): "空格", UInt32(kVK_Return): "回车",
            UInt32(kVK_Tab): "Tab", UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2",
            UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5",
            UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
            UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11",
            UInt32(kVK_F12): "F12",
        ]
        return m[code] ?? "键\(code)"
    }
}

// MARK: - History Manager

class HistoryManager {
    static let shared = HistoryManager()
    private let maxItems = 20
    private let key = "ocrHistory"

    struct Item: Codable {
        var text: String
        var timestamp: Date
    }

    func add(_ text: String) {
        var items = load()
        items.insert(Item(text: text, timestamp: Date()), at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() -> [Item] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([Item].self, from: data) else { return [] }
        return items
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    func text(at index: Int) -> String? {
        let items = load()
        guard index < items.count else { return nil }
        return items[index].text
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    var screenshotManager: ScreenshotManager!
    private var loginItem: NSMenuItem!
    private var settingsController: SettingsWindowController?
    private var historyPanel: HistoryPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 提示授予辅助功能权限（全局按键监听需要）
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        NSLog("🔑 AXIsProcessTrusted: \(trusted)")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: "截图OCR复制")
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        screenshotManager = ScreenshotManager()
        hotkeyManager = HotkeyManager()

        rebuildMenu()
        let settings = AppSettings.load()
        hotkeyManager.applyConfig(settings)
        NSLog("截图OCR复制 started. Hotkey: \(settings.displayString)")
    }

    func rebuildMenu() {
        let settings = AppSettings.load()
        let menu = NSMenu()
        menu.minimumWidth = 280

        menu.addItem(withTitle: "开始截图OCR  (\(settings.displayString))", action: #selector(triggerScreenshot), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())

        // 历史记录 → 点击弹出独立面板（NSMenu 子菜单不支持输入法，改用 NSPanel）
        menu.addItem(withTitle: "历史记录…", action: #selector(showHistoryPanel), keyEquivalent: "")

        menu.addItem(NSMenuItem.separator())
        loginItem = menu.addItem(withTitle: "开机自启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(withTitle: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出", action: #selector(quitApp), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc func triggerScreenshot() { screenshotManager.startCapture() }

    @objc func statusItemClicked() {
        // 左/右键均弹出菜单；截图走快捷键或菜单首项
        rebuildMenu()
        statusItem.button?.performClick(nil)
    }

    /// 点击「历史记录」：菜单关闭后弹出历史面板。
    /// NSPanel 是真正的 key window，完整支持任意输入法（跟随系统状态）。
    @objc func showHistoryPanel() {
        if historyPanel == nil {
            historyPanel = HistoryPanelController(screenshotManager: screenshotManager)
        }
        guard let button = statusItem.button, let win = button.window else { return }
        let rectInScreen = win.convertToScreen(button.frame)
        historyPanel?.present(anchoredTo: rectInScreen)
    }

    @objc func openSettings() {
        if settingsController == nil { settingsController = SettingsWindowController() }
        settingsController?.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        if loginItem.state == .on {
            do { try service.unregister(); loginItem.state = .off } catch {}
        } else {
            do { try service.register(); loginItem.state = .on } catch {}
        }
    }

    @objc func quitApp() { NSApp.terminate(nil) }

    func settingsDidChange() {
        let settings = AppSettings.load()
        hotkeyManager.applyConfig(settings)
        rebuildMenu()
    }

    func ocrCompleted() {
        // 历史面板若打开则刷新内容；否则无需处理（打开时再读取）
        historyPanel?.refresh()
    }
}

// MARK: - History Panel（独立窗口，支持完整输入法）

/// 可成为 key window 的无边框面板（IME 正常的前提）。
private class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 翻转坐标系容器：滚动文档顶部对齐。
private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 历史记录面板控制器：顶部搜索框 + 时间分级列表 + 清空按钮。
/// 面板尺寸固定，搜索时仅替换滚动区内容，避免任何跳动。
class HistoryPanelController: NSObject, NSSearchFieldDelegate, NSWindowDelegate {
    private weak var screenshotManager: ScreenshotManager?
    private var panel: HistoryPanel!
    private var searchField: NSSearchField!
    private var docView: FlippedView!
    private var scrollView: NSScrollView!
    private var clearButton: NSButton!
    private var keyword: String = ""
    private var debounce: Timer?
    private var escMonitor: Any?
    private var scrollObserver: NSObjectProtocol?

    private let panelWidth: CGFloat = 340
    private let panelHeight: CGFloat = 460

    init(screenshotManager: ScreenshotManager) {
        self.screenshotManager = screenshotManager
        super.init()
        buildUI()
    }

    private func buildUI() {
        let panel = HistoryPanel(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        self.panel = panel

        // 半透明毛玻璃容器（液态玻璃观感）
        let blur = NSVisualEffectView()
        blur.blendingMode = .behindWindow
        blur.material = .popover
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        panel.contentView = blur

        // 搜索框：真正 key window 内的文本框，输入法跟随系统
        searchField = NSSearchField()
        searchField.placeholderString = "搜索历史记录…"
        searchField.delegate = self
        searchField.bezelStyle = .roundedBezel
        searchField.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(searchField)

        // 清空按钮
        clearButton = NSButton(title: "清空历史记录", target: self, action: #selector(clearHistory))
        clearButton.bezelStyle = .inline
        clearButton.controlSize = .small
        clearButton.font = .systemFont(ofSize: 11)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(clearButton)

        // 滚动列表
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.contentView.postsBoundsChangedNotifications = true
        blur.addSubview(scrollView)

        docView = FlippedView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = docView

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: blur.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -12),

            clearButton.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            clearButton.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: clearButton.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: blur.bottomAnchor),

            // 文档宽度 = 可视宽度，禁止横向滚动；高度随内容增长
            docView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        // 滚动时清除所有悬停高亮（修复滚动时多行同时标蓝）
        let cv = scrollView.contentView
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: cv, queue: .main
        ) { [weak self] _ in
            self?.resetAllHoverHighlights()
        }
    }

    /// 在状态栏图标下方弹出，激活 app 使输入法正确挂载，并聚焦搜索框。
    func present(anchoredTo rect: NSRect) {
        var origin = rect.origin
        origin.x = rect.midX - panelWidth / 2
        origin.y = rect.minY - panelHeight
        if let scr = (NSScreen.main ?? NSScreen.screens.first) {
            let v = scr.visibleFrame
            origin.x = max(v.minX + 6, min(origin.x, v.maxX - panelWidth - 6))
            if origin.y < v.minY { origin.y = rect.maxY + 6 }   // 上方放不下则放下方
        }
        panel.setFrameOrigin(origin)
        rebuildContent()
        // 必须激活 app，否则输入法不会挂载到面板（导致只能输入中文）
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        startEscMonitor()
    }

    func refresh() {
        guard panel?.isVisible == true else { return }
        rebuildContent()
    }

    private func startEscMonitor() {
        if let m = escMonitor { NSEvent.removeMonitor(m) }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil }   // Esc 关闭
            return event
        }
    }

    deinit {
        if let o = scrollObserver { NotificationCenter.default.removeObserver(o) }
    }

    var isOpen: Bool { panel?.isVisible == true }

    private func resetAllHoverHighlights() {
        for case let row as HistoryRowView in docView.subviews {
            row.resetHighlight()
        }
    }

    func close() {
        panel.orderOut(nil)
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        keyword = ""
        searchField.stringValue = ""
        // 归还前台焦点给原 app
        NSApp.deactivate()
    }

    // 失去焦点（点别处/切 app）→ 关闭
    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    // MARK: - 搜索

    func controlTextDidChange(_ obj: Notification) {
        keyword = searchField.stringValue
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            self?.rebuildContent()
        }
    }

    @objc private func clearHistory() {
        HistoryManager.shared.clear()
        rebuildContent()
    }

    // MARK: - 内容构建（面板尺寸固定，仅替换滚动区 → 不抖动）

    private func rebuildContent() {
        for v in docView.subviews { v.removeFromSuperview() }
        let items = HistoryManager.shared.load()
        let kw = keyword.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = kw.isEmpty ? items : items.filter { $0.text.lowercased().contains(kw) }

        let pad: CGFloat = 12
        var prev: NSLayoutYAxisAnchor = docView.topAnchor
        var gap: CGFloat = 8

        if filtered.isEmpty {
            let ph = NSTextField(labelWithString: items.isEmpty ? "暂无历史记录" : "无匹配结果")
            ph.font = .systemFont(ofSize: 13)
            ph.textColor = .tertiaryLabelColor
            ph.translatesAutoresizingMaskIntoConstraints = false
            docView.addSubview(ph)
            ph.topAnchor.constraint(equalTo: prev, constant: gap).isActive = true
            ph.leadingAnchor.constraint(equalTo: docView.leadingAnchor, constant: pad).isActive = true
            ph.bottomAnchor.constraint(lessThanOrEqualTo: docView.bottomAnchor, constant: -8).isActive = true
            return
        }

        for (label, group) in groupHistoryByDate(filtered) {
            let header = NSTextField(labelWithString: label)
            header.font = .boldSystemFont(ofSize: 11)
            header.textColor = .secondaryLabelColor
            header.translatesAutoresizingMaskIntoConstraints = false
            docView.addSubview(header)
            header.topAnchor.constraint(equalTo: prev, constant: gap).isActive = true
            header.leadingAnchor.constraint(equalTo: docView.leadingAnchor, constant: pad).isActive = true
            header.trailingAnchor.constraint(equalTo: docView.trailingAnchor, constant: -pad).isActive = true
            prev = header.bottomAnchor
            gap = 2

            for item in group {
                let row = HistoryRowView(text: item.text)
                row.translatesAutoresizingMaskIntoConstraints = false
                row.onCopy = { [weak self] in self?.copyText(item.text) }
                docView.addSubview(row)
                row.topAnchor.constraint(equalTo: prev, constant: 1).isActive = true
                row.leadingAnchor.constraint(equalTo: docView.leadingAnchor, constant: pad).isActive = true
                row.trailingAnchor.constraint(equalTo: docView.trailingAnchor, constant: -pad).isActive = true
                prev = row.bottomAnchor
            }
            gap = 10
        }

        // 末尾留白撑起文档高度
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(spacer)
        spacer.topAnchor.constraint(equalTo: prev, constant: 8).isActive = true
        spacer.leadingAnchor.constraint(equalTo: docView.leadingAnchor).isActive = true
        spacer.trailingAnchor.constraint(equalTo: docView.trailingAnchor).isActive = true
        spacer.heightAnchor.constraint(equalToConstant: 1).isActive = true
        spacer.bottomAnchor.constraint(equalTo: docView.bottomAnchor).isActive = true

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        screenshotManager?.showFeedback(text: text)
        close()
    }

    // MARK: - 时间分级

    private func groupHistoryByDate(_ items: [HistoryManager.Item]) -> [(String, [HistoryManager.Item])] {
        let cal = Calendar.current
        let now = Date()
        var today: [HistoryManager.Item] = [], yesterday: [HistoryManager.Item] = []
        var thisWeek: [HistoryManager.Item] = [], thisMonth: [HistoryManager.Item] = []
        var earlier: [HistoryManager.Item] = []
        for item in items {
            if cal.isDateInToday(item.timestamp) { today.append(item) }
            else if cal.isDateInYesterday(item.timestamp) { yesterday.append(item) }
            else if let days = cal.dateComponents([.day], from: item.timestamp, to: now).day, days < 7 { thisWeek.append(item) }
            else if cal.isDate(item.timestamp, equalTo: now, toGranularity: .month) { thisMonth.append(item) }
            else { earlier.append(item) }
        }
        return [("今天", today), ("昨天", yesterday), ("本周", thisWeek), ("本月", thisMonth), ("更早", earlier)]
            .filter { !$0.1.isEmpty }
    }
}

/// 单条历史行：悬停高亮 + 点击复制。
private class HistoryRowView: NSView {
    var onCopy: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private let label = NSTextField(labelWithString: "")

    init(text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6

        let preview = text.replacingOccurrences(of: "\n", with: " ⏎ ")
        label.stringValue = preview.count > 52 ? String(preview.prefix(52)) + "…" : preview
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func handleClick() { onCopy?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.18).cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    func resetHighlight() {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

// MARK: - Settings Window


class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 370),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "设置"
        window.isReleasedWhenClosed = false
        window.center()
        let vc = SettingsViewController()
        window.contentViewController = vc
        self.init(window: window)
    }
}

class SettingsViewController: NSViewController {
    private var hotkeyLabel: NSTextField!
    private var recordButton: NSButton!
    private var isRecording = false
    private var storedMonitor: Any?
    private var globalMonitor: Any?
    private var settings = AppSettings.load()

    private var soundCheckbox: NSButton!
    private var notifCheckbox: NSButton!
    private var borderSlider: NSSlider!
    private var borderLabel: NSTextField!

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 370))

        // Section: 快捷键
        let section1 = NSTextField(labelWithString: "快捷键")
        section1.font = NSFont.boldSystemFont(ofSize: 14)
        section1.frame = NSRect(x: 20, y: 330, width: 200, height: 22)
        view.addSubview(section1)

        hotkeyLabel = NSTextField(labelWithString: settings.displayString)
        hotkeyLabel.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .medium)
        hotkeyLabel.alignment = .center
        hotkeyLabel.wantsLayer = true
        hotkeyLabel.layer?.cornerRadius = 8
        hotkeyLabel.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        hotkeyLabel.frame = NSRect(x: 20, y: 285, width: 120, height: 32)
        view.addSubview(hotkeyLabel)

        recordButton = NSButton(title: "录制新快捷键", target: self, action: #selector(toggleRecording))
        recordButton.bezelStyle = .rounded
        recordButton.frame = NSRect(x: 150, y: 285, width: 130, height: 32)
        view.addSubview(recordButton)

        let resetBtn = NSButton(title: "恢复默认", target: self, action: #selector(resetToDefault))
        resetBtn.bezelStyle = .rounded
        resetBtn.frame = NSRect(x: 290, y: 285, width: 100, height: 32)
        view.addSubview(resetBtn)

        let hint = NSTextField(labelWithString: "录制后按下新的快捷键组合（至少含一个修饰键），按 Esc 取消")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 20, y: 265, width: 380, height: 16)
        view.addSubview(hint)

        // Separator
        let sep1 = NSBox(frame: NSRect(x: 20, y: 250, width: 380, height: 1))
        sep1.boxType = .separator
        view.addSubview(sep1)

        // Section: 提示
        let section2 = NSTextField(labelWithString: "提示")
        section2.font = NSFont.boldSystemFont(ofSize: 14)
        section2.frame = NSRect(x: 20, y: 225, width: 200, height: 22)
        view.addSubview(section2)

        soundCheckbox = NSButton(checkboxWithTitle: "成功时显示弹窗提示", target: self, action: #selector(toggleSetting))
        soundCheckbox.state = settings.soundEnabled ? .on : .off
        soundCheckbox.frame = NSRect(x: 20, y: 195, width: 200, height: 22)
        view.addSubview(soundCheckbox)

        notifCheckbox = NSButton(checkboxWithTitle: "显示系统通知", target: self, action: #selector(toggleSetting))
        notifCheckbox.state = settings.notificationEnabled ? .on : .off
        notifCheckbox.frame = NSRect(x: 20, y: 170, width: 200, height: 22)
        view.addSubview(notifCheckbox)

        // Separator
        let sep2 = NSBox(frame: NSRect(x: 20, y: 155, width: 380, height: 1))
        sep2.boxType = .separator
        view.addSubview(sep2)

        // Section: 截图选框
        let section3 = NSTextField(labelWithString: "截图选框")
        section3.font = NSFont.boldSystemFont(ofSize: 14)
        section3.frame = NSRect(x: 20, y: 130, width: 200, height: 22)
        view.addSubview(section3)

        let borderHint = NSTextField(labelWithString: "边框粗细：")
        borderHint.font = NSFont.systemFont(ofSize: 13)
        borderHint.frame = NSRect(x: 20, y: 100, width: 80, height: 20)
        view.addSubview(borderHint)

        borderSlider = NSSlider(value: Double(settings.borderWidth), minValue: 1, maxValue: 8, target: self, action: #selector(borderChanged))
        borderSlider.frame = NSRect(x: 100, y: 100, width: 200, height: 20)
        view.addSubview(borderSlider)

        borderLabel = NSTextField(labelWithString: "\(Int(settings.borderWidth)) pt")
        borderLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        borderLabel.frame = NSRect(x: 310, y: 100, width: 60, height: 20)
        view.addSubview(borderLabel)

        let borderDesc = NSTextField(labelWithString: "边框颜色根据底色自动适配（浅底用黑，深底用白）")
        borderDesc.font = NSFont.systemFont(ofSize: 11)
        borderDesc.textColor = .secondaryLabelColor
        borderDesc.frame = NSRect(x: 20, y: 78, width: 380, height: 16)
        view.addSubview(borderDesc)

        // Done button
        let doneBtn = NSButton(title: "完成", target: self, action: #selector(closeWindow))
        doneBtn.bezelStyle = .rounded
        doneBtn.keyEquivalent = "\r"
        doneBtn.frame = NSRect(x: 320, y: 20, width: 80, height: 32)
        view.addSubview(doneBtn)

        self.view = view
    }

    @objc func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            recordButton.title = "按下快捷键..."
            recordButton.highlight(true)
            hotkeyLabel.stringValue = "等待输入..."
            storedMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyEvent(event)
                return nil
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyEvent(event)
            }
        } else {
            stopRecording()
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Shift) || event.keyCode == UInt16(kVK_Command) ||
           event.keyCode == UInt16(kVK_Option) || event.keyCode == UInt16(kVK_Control) { return }

        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            hotkeyLabel.stringValue = settings.displayString
            return
        }

        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !mods.isEmpty else { NSSound.beep(); return }

        settings.keyCode = UInt32(event.keyCode)
        settings.modifiers = UInt(mods.rawValue)
        settings.save()
        hotkeyLabel.stringValue = settings.displayString
        stopRecording()
        (NSApp.delegate as? AppDelegate)?.settingsDidChange()
    }

    private func stopRecording() {
        isRecording = false
        recordButton.title = "录制新快捷键"
        recordButton.highlight(false)
        if let m = storedMonitor { NSEvent.removeMonitor(m); storedMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }

    @objc func resetToDefault() {
        settings.keyCode = AppSettings.default.keyCode
        settings.modifiers = AppSettings.default.modifiers
        settings.save()
        hotkeyLabel.stringValue = settings.displayString
        (NSApp.delegate as? AppDelegate)?.settingsDidChange()
    }

    @objc func toggleSetting() {
        settings.soundEnabled = soundCheckbox.state == .on
        settings.notificationEnabled = notifCheckbox.state == .on
        settings.save()
        (NSApp.delegate as? AppDelegate)?.settingsDidChange()
    }

    @objc func borderChanged() {
        let w = round(borderSlider.doubleValue * 2) / 2
        settings.borderWidth = CGFloat(w)
        borderLabel.stringValue = "\(Int(w)) pt"
        settings.save()
        (NSApp.delegate as? AppDelegate)?.settingsDidChange()
    }

    @objc func closeWindow() {
        stopRecording()
        view.window?.orderOut(nil)
    }
}

// MARK: - Global Hotkey Manager

class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private static var shared: HotkeyManager?
    private static let hotkeyId = EventHotKeyID(signature: OSType(0x4F435252), id: 1)
    private var eventHandler: EventHandlerRef?
    private var currentKeyCode: UInt32 = 0
    private var currentModifiers: NSEvent.ModifierFlags = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func applyConfig(_ settings: AppSettings) {
        if let ref = hotkeyRef { UnregisterEventHotKey(ref); hotkeyRef = nil }
        currentKeyCode = settings.keyCode
        currentModifiers = NSEvent.ModifierFlags(rawValue: settings.modifiers)
        registerHotkey(keyCode: settings.keyCode, modifiers: currentModifiers)
        setupCGEventTap()
    }

    private func registerHotkey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> Bool {
        HotkeyManager.shared = self
        if eventHandler == nil {
            var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { (_, _, userData) -> OSStatus in
                    guard let userData = userData else { return noErr }
                    let m = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                    DispatchQueue.main.async { m.onHotkeyTriggered() }
                    return noErr
                },
                1, &eventSpec, selfPtr, &eventHandler
            )
            guard status == noErr else { return false }
        }

        var carbonMods: UInt32 = 0
        if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbonMods |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbonMods |= UInt32(shiftKey) }

        let status = RegisterEventHotKey(keyCode, carbonMods, HotkeyManager.hotkeyId, GetApplicationEventTarget(), 0, &hotkeyRef)
        NSLog("🔑 RegisterEventHotKey status: \(status), keyCode: \(keyCode), mods: \(carbonMods)")
        return status == noErr
    }

    private func onHotkeyTriggered() {
        NSLog("🔑 Hotkey triggered via Carbon!")
        NotificationCenter.default.post(name: NSNotification.Name("HotkeyTriggered"), object: nil)
    }

    // CGEventTap: system-wide keyboard interception
    private func setupCGEventTap() {
        // Clean up old tap
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .defaultMode) }
            eventTap = nil
            runLoopSource = nil
        }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (_, type, event, userInfo) -> Unmanaged<CGEvent>? in
                guard let userInfo = userInfo else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

                let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags

                // Check modifier match
                var needCmd = false, needShift = false, needOpt = false, needCtrl = false
                if manager.currentModifiers.contains(.command) { needCmd = true }
                if manager.currentModifiers.contains(.shift) { needShift = true }
                if manager.currentModifiers.contains(.option) { needOpt = true }
                if manager.currentModifiers.contains(.control) { needCtrl = true }

                let hasCmd = flags.contains(.maskCommand)
                let hasShift = flags.contains(.maskShift)
                let hasOpt = flags.contains(.maskAlternate)
                let hasCtrl = flags.contains(.maskControl)

                if keyCode == manager.currentKeyCode && hasCmd == needCmd && hasShift == needShift && hasOpt == needOpt && hasCtrl == needCtrl {
                    NSLog("🔑 Hotkey triggered via CGEventTap! keyCode=\(keyCode)")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: NSNotification.Name("HotkeyTriggered"), object: nil)
                    }
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("🔑 CGEventTap creation FAILED - need Input Monitoring permission")
            return
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .defaultMode)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = src
        NSLog("🔑 CGEventTap installed successfully")
        
        // Start a timer to keep the tap alive
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                NSLog("🔑 EventTap was disabled, re-enabling...")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
    }
}

// MARK: - Selection View (auto contrast border + live OCR preview)

class SelectionView: NSView {
    var selectionRect: NSRect = .zero
    var isSelecting = false
    var borderWidth: CGFloat = 2
    var liveText: String? = nil
    var onSelectionComplete: ((NSRect) -> Void)?
    var onSelectionCancel: (() -> Void)?
    var onSelectionDrag: ((NSRect) -> Void)?
    private var startPoint: NSPoint = .zero
    private var trackingTimer: Timer?

    override func draw(_ dirtyRect: NSRect) {
        // Dim background
        NSColor(white: 0, alpha: 0.3).setFill()
        dirtyRect.fill()

        if isSelecting && selectionRect.width > 0 && selectionRect.height > 0 {
            // Clear selection area
            NSColor.clear.setFill()
            selectionRect.fill()

            // Auto-contrast border: sample average brightness of the selection area
            // For simplicity, use white border (visible on most content during dim overlay)
            let borderColor = NSColor.white
            borderColor.setStroke()
            let path = NSBezierPath(rect: selectionRect)
            path.lineWidth = borderWidth
            path.stroke()

            // Draw live OCR text preview if available (auto-sizing)
            if let text = liveText, !text.isEmpty {
                let font = NSFont.systemFont(ofSize: 12)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.white,
                ]

                // Truncate to 200 chars for preview
                let previewText = text.count > 200 ? String(text.prefix(200)) + "…" : text
                let attributed = NSAttributedString(string: previewText, attributes: attrs)

                // Calculate text size with wrapping
                let maxTextWidth: CGFloat = 280
                let textContainerHeight: CGFloat = 400
                let textStorage = NSTextStorage(attributedString: attributed)
                let layoutManager = NSLayoutManager()
                textStorage.addLayoutManager(layoutManager)
                let textContainer = NSTextContainer(containerSize: NSSize(width: maxTextWidth, height: textContainerHeight))
                textContainer.lineFragmentPadding = 0
                layoutManager.addTextContainer(textContainer)
                layoutManager.glyphRange(for: textContainer)
                let usedRect = layoutManager.usedRect(for: textContainer)

                let padding: CGFloat = 10
                let boxWidth: CGFloat = 300
                let boxHeight: CGFloat = min(usedRect.height + padding * 2, selectionRect.height, 400)

                // Position: right of selection, fallback to left, fallback to inside-top
                var boxX = selectionRect.maxX + 8
                var boxY = selectionRect.maxY - boxHeight

                if boxX + boxWidth > self.bounds.maxX {
                    boxX = selectionRect.minX - boxWidth - 8
                }
                if boxX < 0 {
                    // Not enough space on either side — show inside selection at top
                    boxX = selectionRect.minX + 8
                    boxY = selectionRect.maxY - boxHeight - 8
                }
                if boxY < 0 { boxY = selectionRect.minY }

                let drawRect = NSRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight)

                // Background
                NSColor(white: 0, alpha: 0.88).setFill()
                NSBezierPath(roundedRect: drawRect, xRadius: 8, yRadius: 8).fill()

                // Draw text
                let textRect = drawRect.insetBy(dx: padding, dy: padding / 2)
                attributed.draw(in: textRect)
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() {
        addCursorRect(self.bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = NSEvent.mouseLocation
        selectionRect = NSRect(origin: .zero, size: .zero)
        isSelecting = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isSelecting else { return }
        let current = NSEvent.mouseLocation
        let x = min(startPoint.x, current.x)
        let y = min(startPoint.y, current.y)
        let w = abs(current.x - startPoint.x)
        let h = abs(current.y - startPoint.y)
        selectionRect = NSRect(x: x, y: y, width: w, height: h)
        needsDisplay = true
        onSelectionDrag?(selectionRect)
    }

    override func mouseUp(with event: NSEvent) {
        guard isSelecting else { return }
        isSelecting = false
        let rect = selectionRect
        if rect.width > 5 && rect.height > 5 {
            onSelectionComplete?(rect)
        } else {
            onSelectionCancel?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onSelectionCancel?()
        }
    }
}

// MARK: - Keyable Panel

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Screenshot Manager

class ScreenshotManager: NSObject {
    private var panel: NSPanel?
    private var selectionView: SelectionView?
    private var currentRect: NSRect = .zero
    private var liveOCRTask: Task<Void, Never>?
    private var isOCRRunning = false
    private var cachedOCRText: String? = nil
    private var cachedOCRRect: NSRect = .zero

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(startCapture), name: NSNotification.Name("HotkeyTriggered"), object: nil)
    }

    @objc func startCapture() {
        guard panel == nil else { return }
        cachedOCRText = nil
        cachedOCRRect = .zero
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let settings = AppSettings.load()

        let selView = SelectionView(frame: frame)
        selView.autoresizingMask = [.width, .height]
        selView.borderWidth = settings.borderWidth
        selectionView = selView

        let p = KeyablePanel(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = selView
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.worksWhenModal = true
        p.becomesKeyOnlyIfNeeded = false
        panel = p

        p.makeKeyAndOrderFront(nil)
        selView.window?.makeFirstResponder(selView)
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
        selView.window?.invalidateCursorRects(for: selView)
        NSLog("📷 Panel shown, frame=\(frame)")

        // Use callback-based mouse handling instead of NSEvent monitor
        selView.onSelectionDrag = { [weak self] rect in
            guard let self = self else { return }
            self.currentRect = rect
            if rect.width > 50 && rect.height > 20 {
                self.scheduleLiveOCR()
            }
        }
        selView.onSelectionComplete = { [weak self] rect in
            guard let self = self else { return }
            self.handleSelectionComplete(rect)
        }
        selView.onSelectionCancel = { [weak self] in
            guard let self = self else { return }
            self.cancelLiveOCR()
            self.cleanupPanel()
        }
    }

    private func handleSelectionComplete(_ rect: NSRect) {
        let rect = currentRect
        cancelLiveOCR()
        cleanupPanel()
        if rect.width > 5 && rect.height > 5 {
            if let cached = cachedOCRText, !cached.isEmpty,
               abs(cachedOCRRect.width - rect.width) < 5,
               abs(cachedOCRRect.height - rect.height) < 5 {
                NSLog("📷 Using cached OCR result")
                liveOCRTask?.cancel()
                liveOCRTask = nil
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.copyToClipboard(cached)
                    HistoryManager.shared.add(cached)
                    (NSApp.delegate as? AppDelegate)?.ocrCompleted()
                    self.showResult(success: true, text: cached)
                }
            } else if liveOCRTask != nil {
                NSLog("📷 OCR still running, will copy when done")
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.captureRegion(rect)
                }
            }
        }
    }

    private var lastLiveOCRTime: Date = .distantPast

    private func scheduleLiveOCR() {
        // Throttle: at most once per 300ms
        let now = Date()
        guard now.timeIntervalSince(lastLiveOCRTime) > 0.6 else { return }
        lastLiveOCRTime = now

        let rect = currentRect

        // Only cancel previous task if it's still in debounce wait,
        // NOT if it's already running OCR
        if !isOCRRunning {
            liveOCRTask?.cancel()
        } else {
            return  // OCR in progress, don't start a new one
        }

        liveOCRTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms debounce
            guard !Task.isCancelled else { return }

            // Mark OCR as running — won't be cancelled by new scheduleLiveOCR
            self.isOCRRunning = true

            let image = await self.quickCapture(rect)
            guard let image = image else { self.isOCRRunning = false; return }

            let text = await self.quickOCR(image)
            self.isOCRRunning = false
            guard !Task.isCancelled, !text.isEmpty else { return }

            await MainActor.run {
                // Cache result for potential reuse
                self.cachedOCRText = text
                self.cachedOCRRect = rect
                // Update preview if panel still open
                if self.panel != nil, let sv = self.selectionView {
                    sv.liveText = text
                    sv.needsLayout = true
                    sv.needsDisplay = true
                } else {
                    // Panel already closed (user released) — copy result now
                    NSLog("📷 Late OCR result, copying now")
                    self.copyToClipboard(text)
                    HistoryManager.shared.add(text)
                    (NSApp.delegate as? AppDelegate)?.ocrCompleted()
                    self.showResult(success: true, text: text)
                }
            }
        }
    }

    private func cancelLiveOCR() {
        liveOCRTask?.cancel()
        liveOCRTask = nil
    }

    private func cleanupPanel() {
        panel?.orderOut(nil)
        panel = nil
        selectionView = nil
        // Restore cursor
        NSCursor.pop()
    }

    // MARK: - Capture

    private func quickCapture(_ region: NSRect) async -> CGImage? {
        guard let screen = NSScreen.main else { return nil }
        let screenFrame = screen.frame
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()

        let xInDisplay = region.origin.x - screenFrame.origin.x
        let yInDisplay = screenFrame.maxY - region.maxY
        let captureRect = CGRect(x: xInDisplay, y: yInDisplay, width: region.width, height: region.height)

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else { return nil }

            let config = SCStreamConfiguration()
            config.width = Int(captureRect.width) * 2
            config.height = Int(captureRect.height) * 2
            config.sourceRect = captureRect
            config.scalesToFit = false
            config.showsCursor = false

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let captured = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            // 已禁用 maskEmojiRegions：该方案会把深色背景整体判为 emoji 涂白，
            // 导致深色 UI（终端/代码/AI对话）截图的准确率暴跌。emoji 误读为小概率，
            // 弃保：恢复正常准确率，emoji 偶发误读容忍之。
            return captured
        } catch {
            NSLog("📷 quickCapture error: \(error)")
            return nil
        }
    }

    private func captureRegion(_ region: NSRect) {
        NSLog("📷 captureRegion: \(region)")
        Task {
            guard let image = await quickCapture(region) else {
                await MainActor.run { self.showResult(success: false, text: "") }
                return
            }
            await MainActor.run { self.performOCR(cgImage: image) }
        }
    }

    // MARK: - OCR

    private func quickOCR(_ cgImage: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                let text = self.cleanText(self.processObservations(observations))
                continuation.resume(returning: text)
            }
            // .fast mode does NOT support Chinese — must use .accurate for zh recognition
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }

    private func performOCR(cgImage: CGImage) {
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                NSLog("OCR error: \(error)")
                DispatchQueue.main.async { self.showResult(success: false, text: "") }
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async { self.showResult(success: false, text: "") }
                return
            }

            let fullText = self.cleanText(self.processObservations(observations))

            DispatchQueue.main.async {
                if fullText.isEmpty {
                    self.showResult(success: false, text: "")
                } else {
                    self.copyToClipboard(fullText)
                    HistoryManager.shared.add(fullText)
                    (NSApp.delegate as? AppDelegate)?.ocrCompleted()
                    self.showResult(success: true, text: fullText)
                }
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do { try handler.perform([request]) }
            catch { NSLog("Vision error: \(error)") }
        }
    }

    /// 在 OCR 前屏蔽图像中的 emoji：检测「非白色的实心色块」并涂白。
    /// 原理：Vision 无法识别 emoji，会把 emoji 与相邻文字合并成同一个 observation，
    /// 因此按 observation 整体检测必然失效。改为在图像层面直接抹除 emoji 像素，
    /// 让 Vision 根本看不到它。判据：emoji 是实心方块(填充率高)，
    /// 文字是笔画(填充率低)。连通区域填充率 > 0.75 且近正方形即视为 emoji。
    /// 可同时处理彩色和灰色(如🔲)实心 emoji；非实心 emoji(如📈图表)可能漏网。
    private func maskEmojiRegions(_ image: CGImage) -> CGImage {
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let provider = image.dataProvider,
              let dataRef = provider.data,
              let base = CFDataGetBytePtr(dataRef) else { return image }
        let bpp = image.bitsPerPixel / 8
        let bpr = image.bytesPerRow
        let totalBytes = CFDataGetLength(dataRef)
        guard bpp >= 3, image.bitsPerComponent == 8 else { return image }

        var nonwhite = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let o = y * bpr + x * bpp
                guard o + 2 < totalBytes else { continue }
                let r = Int(base[o]), g = Int(base[o + 1]), b = Int(base[o + 2])
                if min(r, min(g, b)) < 225 { nonwhite[y * w + x] = true }
            }
        }

        // 4-连通区域标记，统计每块面积与边界框
        var label = [Int](repeating: 0, count: w * h)
        var comps: [(px: Int, minX: Int, maxX: Int, minY: Int, maxY: Int)] = []
        let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        for sy in 0..<h {
            for sx in 0..<w {
                let si = sy * w + sx
                guard nonwhite[si] && label[si] == 0 else { continue }
                var queue = [(sx, sy)]
                var head = 0
                label[si] = comps.count + 1
                var px = 0, minX = sx, maxX = sx, minY = sy, maxY = sy
                while head < queue.count {
                    let (cx, cy) = queue[head]; head += 1
                    px += 1
                    if cx < minX { minX = cx }
                    if cx > maxX { maxX = cx }
                    if cy < minY { minY = cy }
                    if cy > maxY { maxY = cy }
                    for (dx, dy) in dirs {
                        let nx = cx + dx, ny = cy + dy
                        if nx >= 0 && nx < w && ny >= 0 && ny < h {
                            let ni = ny * w + nx
                            if nonwhite[ni] && label[ni] == 0 {
                                label[ni] = comps.count + 1
                                queue.append((nx, ny))
                            }
                        }
                    }
                }
                comps.append((px, minX, maxX, minY, maxY))
            }
        }

        // 实心色块(emoji)判定：填充率高 + 近正方形 + 面积足够
        var maskComps = Set<Int>()
        for (i, c) in comps.enumerated() {
            let bw = c.maxX - c.minX + 1
            let bh = c.maxY - c.minY + 1
            let fill = Double(c.px) / Double(bw * bh)
            let asp = bw < bh ? Double(bw) / Double(bh) : Double(bh) / Double(bw)
            if fill > 0.75 && asp > 0.4 && c.px > 200 {
                maskComps.insert(i + 1)
            }
        }
        if maskComps.isEmpty { return image }

        NSLog("📷 屏蔽 \(maskComps.count) 个 emoji 区域")
        var buf = [UInt8](repeating: 0, count: bpr * h)
        memcpy(&buf, base, bpr * h)
        for y in 0..<h {
            for x in 0..<w {
                let li = label[y * w + x]
                if li > 0 && maskComps.contains(li) {
                    let o = y * bpr + x * bpp
                    buf[o] = 255; buf[o + 1] = 255; buf[o + 2] = 255
                }
            }
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &buf, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: bpr,
                                   space: cs, bitmapInfo: image.bitmapInfo.rawValue),
              let out = ctx.makeImage() else { return image }
        return out
    }

    /// Smart line-join: distinguishes paragraph breaks from soft line wraps.
    /// - Lines with large vertical gaps between them = different paragraphs → keep \n
    /// - Lines close together with similar indentation = same paragraph soft-wrap → join with no separator
    private func processObservations(_ observations: [VNRecognizedTextObservation]) -> String {
        guard !observations.isEmpty else { return "" }

        // Sort top-to-bottom, left-to-right
        let sorted = observations.sorted { a, b in
            let ay = a.boundingBox.origin.y
            let by = b.boundingBox.origin.y
            if abs(ay - by) > 0.02 { return ay > by }  // higher Y = higher on screen
            return a.boundingBox.origin.x < b.boundingBox.origin.x
        }

        // Group into lines based on Y proximity
        struct Line {
            var text: String
            var x: CGFloat
            var width: CGFloat
            var y: CGFloat
            var height: CGFloat
        }

        var lines: [Line] = []
        for obs in sorted {
            let y = obs.boundingBox.origin.y
            let h = obs.boundingBox.height
            let x = obs.boundingBox.origin.x
            let w = obs.boundingBox.width

            guard let candidate = obs.topCandidates(1).first else { continue }
            let candidateText = candidate.string
            let conf = candidate.confidence

            // Skip low-confidence observations — often emoji/icon misreads
            // that produce single symbols like *, #, @, etc.
            if conf < 0.3 { continue }

           // Detect single-symbol "junk" that is likely an emoji misread:
            // Vision 无法可靠识别 emoji，常将其误读为单个符号（* # @ ※ ★ ● ■ 等）。
            // 启发式：方形选框（emoji 近正方形，真实标点通常窄）+ 符号类字符
            // （排除字母/数字/汉字）+ 置信度非极高 → 判定为 emoji 误读并丢弃。
            let isSquareish = w > 0 && h > 0 && (min(w, h) / max(w, h)) > 0.55
            func isSymbolJunk(_ s: String) -> Bool {
                // emoji 误读通常是 1~2 个符号字符
                guard s.count <= 2 else { return false }
                return s.unicodeScalars.allSatisfy { scalar in
                    let v = scalar.value
                    if v >= 0x4E00 && v <= 0x9FFF { return false }   // 汉字保留
                    if scalar >= "a" && scalar <= "z" { return false }  // 字母保留
                    if scalar >= "A" && scalar <= "Z" { return false }
                    if scalar >= "0" && scalar <= "9" { return false }  // 数字保留
                    return true  // 其余符号视为可疑
                }
            }
            if isSquareish && isSymbolJunk(candidateText) && conf < 0.85 { continue }

            // Try to append to current line if Y is close
            if let lastIdx = lines.indices.last {
                let last = lines[lastIdx]
                // Same line if Y difference < 30% of line height
                if abs(y - last.y) < max(h, last.height) * 0.3 {
                    lines[lastIdx].text += candidateText
                    lines[lastIdx].width = max(last.width, x + w - last.x)
                    continue
                }
            }
            lines.append(Line(text: candidateText, x: x, width: w, y: y, height: h))
        }

        // Smart line joining using multiple signals:
        // 1. Large vertical gap → paragraph break
        // 2. Line starts at far left (x near 0 or near first line's x) → new line
        // 3. Line starts mid-way (continuation indent) → soft wrap, join
        var result: [String] = []

        // Find the leftmost x (the "margin" — most lines start here)
        let minX = lines.map { $0.x }.min() ?? 0

        for (i, line) in lines.enumerated() {
            if i == 0 {
                result.append(line.text)
                continue
            }

            let prev = lines[i - 1]
            let gap = prev.y - line.y
            let avgHeight = max((line.height + prev.height) / 2, 0.01)

            // How far is this line's start from the left margin?
            let indentFromMargin = line.x - minX

            // Signal 1: Large vertical gap → definitely a paragraph break
            let largeGap = gap > avgHeight * 1.8

            // Signal 2: This line starts at/near the left margin → new line/paragraph
            let startsAtMargin = indentFromMargin < avgHeight * 0.5

            // Signal 3: Previous line is short (doesn't reach right edge) AND this line
            // starts at margin → likely a real line break (user pressed Enter)
            let prevRightEdge = prev.x + prev.width
            let prevIsShort = prevRightEdge < (minX + prev.width * 1.5) && prev.width < avgHeight * 10

            if largeGap {
                // Big gap → paragraph break
                result.append(line.text)
            } else if startsAtMargin && prevIsShort {
                // Previous line was short and this starts at margin → intentional line break
                result.append(line.text)
            } else if startsAtMargin {
                // Starts at margin, normal gap → new line (keep newline)
                result.append(line.text)
            } else {
                // Starts mid-line → soft wrap, join without separator
                result[result.count - 1] += line.text
            }
        }

        return result.joined(separator: "\n")
    }

    /// Filter out garbled characters that Vision produces when it tries to read emoji/icons.
    /// Removes: control chars, non-printable, private-use-area, lone combining marks, and
    /// common Vision misreads of emoji (square/box chars, replacement chars).
    private func cleanText(_ text: String) -> String {
        // Define allowed Unicode scalar ranges
        func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
            let v = scalar.value
            // ASCII printable + common whitespace
            if v == 0x09 || v == 0x0A || v == 0x0D { return true }  // tab, newline, CR
            if v >= 0x20 && v <= 0x7E { return true }  // ASCII printable
            // CJK Unified Ideographs + extensions A/B (common Chinese)
            if v >= 0x4E00 && v <= 0x9FFF { return true }
            if v >= 0x3400 && v <= 0x4DBF { return true }
            if v >= 0x20000 && v <= 0x2A6DF { return true }
            // CJK punctuation, fullwidth forms
            if v >= 0x3000 && v <= 0x303F { return true }  // CJK Symbols and Punctuation
            if v >= 0xFF00 && v <= 0xFFEF { return true }  // Halfwidth/Fullwidth Forms
            // General punctuation (quotes, dashes, ellipsis, etc.)
            if v >= 0x2000 && v <= 0x206F { return true }
            // Latin Extended + Latin-1 Supplement (accented chars)
            if v >= 0x00A0 && v <= 0x024F { return true }
            // Greek and Cyrillic
            if v >= 0x0370 && v <= 0x03FF { return true }
            if v >= 0x0400 && v <= 0x04FF { return true }
            // Common currency symbols
            if v >= 0x20A0 && v <= 0x20BF { return true }
            // Letterlike symbols (℃ ℉ № etc.)
            if v >= 0x2100 && v <= 0x214F { return true }
            // Math operators (common ones)
            if v >= 0x2200 && v <= 0x22FF { return true }
            return false
        }

        var result = ""
        for char in text {
            // Keep newlines explicitly
            if char == "\n" || char == "\r" {
                result.append(char)
                continue
            }
            // Check all scalars of the character
            let allAllowed = char.unicodeScalars.allSatisfy { isAllowed($0) }
            if allAllowed {
                result.append(char)
            }
            // else: skip (likely emoji garbage)
        }

        // Clean up: collapse 3+ consecutive spaces/newlines into 2
        while result.contains("  \n") { result = result.replacingOccurrences(of: "  \n", with: "\n") }
        while result.contains("\n ") { result = result.replacingOccurrences(of: "\n ", with: "\n") }
        // Trim trailing whitespace per line
        result = result.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    // MARK: - Output

    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// 弹窗 + 音效双重提示。受「弹窗提示」开关控制。
    func showFeedback(success: Bool = true, text: String = "") {
        let settings = AppSettings.load()
        guard settings.soundEnabled else { return }
        playFeedbackSound(success: success)
        FeedbackToast.shared.show(success: success, text: text)
    }

    /// 播放音效：成功用 Hero（上扬悦耳），失败用 Basso（低沉）。比原 Glass 更有辨识度。
    private func playFeedbackSound(success: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            let path = success ? "/System/Library/Sounds/Hero.aiff" : "/System/Library/Sounds/Basso.aiff"
            guard let sound = NSSound(contentsOfFile: path, byReference: true) else { return }
            sound.volume = 0.75
            sound.play()
        }
    }

    private func showResult(success: Bool, text: String) {
        showFeedback(success: success, text: text)

        let settings = AppSettings.load()

        if settings.notificationEnabled {
            let center = UNUserNotificationCenter.current()
            center.getNotificationSettings { status in
                if status.authorizationStatus == .notDetermined {
                    center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
                }
                guard status.authorizationStatus == .authorized || status.authorizationStatus == .provisional else { return }

                let content = UNMutableNotificationContent()
                content.title = success ? "已复制到剪贴板" : "未能识别到文字"
                content.body = success ? (text.count > 50 ? String(text.prefix(50)) + "..." : text) : ""
                content.sound = nil  // we play our own sound
                center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
        }
    }
}

// MARK: - Feedback Toast（轻量弹窗提示，替代提示音）

/// 从屏幕右上角弹出的浮动卡片，显示复制/识别结果，约 2 秒后自动淡出。
/// 无边框 NSPanel，不抢焦点、不阻塞，跨 Space 显示。
private class FeedbackToast {
    static let shared = FeedbackToast()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(success: Bool, text: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.show(success: success, text: text) }
            return
        }
        hideWork?.cancel()
        panel?.orderOut(nil)

        let width: CGFloat = 300
        let height: CGFloat = 64

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.borderless], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.backgroundColor = .clear
        p.isOpaque = false
        p.isMovable = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.level = .floating
        panel = p

        let blur = NSVisualEffectView()
        blur.blendingMode = .behindWindow
        blur.material = .popover
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        p.contentView = blur

        let icon = NSTextField(labelWithString: success ? "✅" : "⚠️")
        icon.font = .systemFont(ofSize: 22)
        icon.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(icon)

        let title = NSTextField(labelWithString: success ? "已复制到剪贴板" : "未能识别到文字")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(title)

        let preview = success ? (text.count > 60 ? String(text.prefix(60)) + "…" : text) : ""
        let body = NSTextField(labelWithString: preview)
        body.font = .systemFont(ofSize: 11)
        body.textColor = .secondaryLabelColor
        body.lineBreakMode = .byTruncatingTail
        body.maximumNumberOfLines = 1
        body.cell?.truncatesLastVisibleLine = true
        body.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(body)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: blur.centerYAnchor, constant: preview.isEmpty ? 0 : 6),
            icon.widthAnchor.constraint(equalToConstant: 26),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            title.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -14),
            title.topAnchor.constraint(equalTo: blur.topAnchor, constant: preview.isEmpty ? 22 : 12),

            body.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
        ])

        // 定位：主屏右上角（菜单栏下方）
        if let screen = (NSScreen.main ?? NSScreen.screens.first) {
            let vf = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: vf.maxX - width - 16, y: vf.maxY - height - 8))
        }

        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            p.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let cur = self.panel, cur === p else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                cur.animator().alphaValue = 0
            }, completionHandler: {
                cur.orderOut(nil)
                if self.panel === cur { self.panel = nil }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }
}

// MARK: - Main Entry Point

// Listen for Darwin notification to trigger screenshot (cross-process, reliable)
CFNotificationCenterAddObserver(
    CFNotificationCenterGetDarwinNotifyCenter(),
    nil,
    { _, _, _, _, _ in
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("HotkeyTriggered"), object: nil)
        }
    },
    "com.local.screenshot-ocr-copy.trigger" as CFString,
    nil,
    .deliverImmediately
)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
