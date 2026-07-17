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
    private var screenshotManager: ScreenshotManager!
    private var loginItem: NSMenuItem!
    private var settingsController: SettingsWindowController?
    private var historyMenu: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prompt for Accessibility permission (needed for global key monitoring)
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

        menu.addItem(withTitle: "开始截图OCR  (\(settings.displayString))", action: #selector(triggerScreenshot), keyEquivalent: "")

        menu.addItem(NSMenuItem.separator())

        historyMenu = menu.addItem(withTitle: "历史记录", action: nil, keyEquivalent: "")
        rebuildHistorySubmenu()

        menu.addItem(NSMenuItem.separator())

        loginItem = menu.addItem(withTitle: "开机自启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        menu.addItem(withTitle: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出", action: #selector(quitApp), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func rebuildHistorySubmenu() {
        let submenu = NSMenu()
        let items = HistoryManager.shared.load()

        if items.isEmpty {
            submenu.addItem(withTitle: "（暂无记录）", action: nil, keyEquivalent: "")
        } else {
            for (i, item) in items.enumerated() {
                let preview = item.text.replacingOccurrences(of: "\n", with: " ")
                let title = preview.count > 30 ? String(preview.prefix(30)) + "..." : preview
                let menuItem = submenu.addItem(withTitle: title, action: #selector(copyHistoryItem(_:)), keyEquivalent: "")
                menuItem.tag = i
                menuItem.toolTip = item.text
            }
            submenu.addItem(NSMenuItem.separator())
            submenu.addItem(withTitle: "清空历史记录", action: #selector(clearHistory), keyEquivalent: "")
        }
        historyMenu.submenu = submenu
    }

    @objc func triggerScreenshot() { screenshotManager.startCapture() }

    @objc func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true {
            statusItem.menu = nil
            rebuildMenu()
            statusItem.button?.performClick(nil)
        } else {
            screenshotManager.startCapture()
        }
    }

    @objc func copyHistoryItem(_ sender: NSMenuItem) {
        if let text = HistoryManager.shared.text(at: sender.tag) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            screenshotManager.playFeedback()
        }
    }

    @objc func clearHistory() {
        HistoryManager.shared.clear()
        rebuildHistorySubmenu()
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
        rebuildHistorySubmenu()
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

        soundCheckbox = NSButton(checkboxWithTitle: "成功时播放提示音", target: self, action: #selector(toggleSetting))
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
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
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
                let text = self.cleanText(self.processObservations(observations, cgImage: cgImage))
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

            let fullText = self.cleanText(self.processObservations(observations, cgImage: cgImage))

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

    /// Smart line-join: distinguishes paragraph breaks from soft line wraps.
    /// - Lines with large vertical gaps between them = different paragraphs → keep \n
    /// - Lines close together with similar indentation = same paragraph soft-wrap → join with no separator
    /// 检测图像指定归一化区域是否为彩色图形（emoji）。
    /// Vision bbox 原点在左下、归一化；CGImage 原点在左上、像素坐标。
    /// 判据：emoji 是彩色图形，真实文字几乎都是单色（灰阶）。
    /// 网格采样像素，统计高饱和度像素占比，>25% 即判定为彩色图形。
    private func isColorfulRegion(_ cgImage: CGImage, bbox: CGRect) -> Bool {
        let imgW = cgImage.width
        let imgH = cgImage.height
        guard imgW > 0, imgH > 0 else { return false }

        // Vision 坐标(左下原点) → CGImage 像素坐标(左上原点)
        let px = Int((bbox.origin.x * CGFloat(imgW)).rounded())
        let py = Int(((1.0 - bbox.origin.y - bbox.height) * CGFloat(imgH)).rounded())
        let pw = Int((bbox.width * CGFloat(imgW)).rounded())
        let ph = Int((bbox.height * CGFloat(imgH)).rounded())
        guard pw >= 2, ph >= 2 else { return false }

        guard let provider = cgImage.dataProvider,
              let data = provider.data,
              let ptr = CFDataGetBytePtr(data) else { return false }
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        guard bytesPerPixel >= 3 else { return false }

        // 网格采样，最多 ~8x8 点，避免大区域过慢
        let samplesX = min(8, pw)
        let samplesY = min(8, ph)
        var colorful = 0
        var total = 0
        for iy in 0..<samplesY {
            for ix in 0..<samplesX {
                let pixelX = min(imgW - 1, max(0, px + (pw * ix) / max(1, samplesX - 1)))
                let pixelY = min(imgH - 1, max(0, py + (ph * iy) / max(1, samplesY - 1)))
                let offset = pixelY * bytesPerRow + pixelX * bytesPerPixel
                guard offset + 2 < CFDataGetLength(data) else { continue }
                let r = ptr[offset], g = ptr[offset + 1], b = ptr[offset + 2]
                let mx = Int(max(r, max(g, b)))
                let mn = Int(min(r, min(g, b)))
                let diff = mx - mn
                total += 1
                // 彩色：RGB 通道差大(非灰阶) 且 非极暗/极亮（排除黑白文字边缘）
                if diff > 30 && mx > 40 && mn < 220 { colorful += 1 }
            }
        }
        return total > 0 && colorful * 4 > total  // >25% 像素为彩色
    }

    private func processObservations(_ observations: [VNRecognizedTextObservation]) -> String {
        return processObservations(observations, cgImage: nil)
    }

    private func processObservations(_ observations: [VNRecognizedTextObservation], cgImage: CGImage?) -> String {
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

            // 源头拦截：检测 boundingBox 区域是否为彩色图形（emoji）。
            // emoji 是彩色图形，真实文字几乎都是单色；Vision 无法识别 emoji，
            // 会把它误读成汉字（口/困/图）、符号（★●※）或乱码。用像素颜色判定最可靠。
            if let cg = cgImage, isColorfulRegion(cg, bbox: obs.boundingBox) {
                continue
            }

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

    private var audioPlayer: NSObject? = nil  // keep reference alive

    func playFeedback() {
        let settings = AppSettings.load()
        guard settings.soundEnabled else { return }
        // Dispatch to main thread for reliable playback
        DispatchQueue.main.async {
            let sound = NSSound(contentsOfFile: "/System/Library/Sounds/Glass.aiff", byReference: true)
            sound?.volume = 1.0
            sound?.play()
        }
    }

    private func showResult(success: Bool, text: String) {
        if success { playFeedback() }

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
