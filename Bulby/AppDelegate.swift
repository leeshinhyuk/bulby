import SwiftUI
import AppKit
import ScreenCaptureKit
import UserNotifications
import Combine

@main
struct BulbyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate, ObservableObject {
    var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()
    private let modeStore = ModeStore()
    private let historyStore = HistoryStore()
    private let ollamaClient = OllamaClient()
    private let screenCaptureService = ScreenCaptureService()

    var notchWindow: BulbyPanel?
    var resultWindow: BulbyPanel?
    var historyWindow: BulbyPanel?

    @Published var isExpanded = false
    @Published var showPicker = false
    @Published var showModeList = false
    @Published var showAddModeSheet = false
    @Published var conversations: [Conversation] = []
    @Published var currentConversationID: UUID?
    @Published var selectedMode: CustomMode
    @Published var customModes: [CustomMode] = []
    @Published var installedModels: [String] = []
    @Published var availableWindows: [SCWindow] = []
    @Published var selectedWindowIDs: Set<CGWindowID> = []
    @Published var lastErrorMessage: String?
    @Published var isOllamaReachable = false
    @Published var pendingContinuation: PendingContinuation?
    @Published var notchFocusRequest = 0
    @Published var screenCaptureAccessConfirmed = false
    @Published var unreadConversationID: UUID?

    var selectedModel = AppPreferences.selectedModel {
        didSet { AppPreferences.selectedModel = selectedModel }
    }
    var currentConversation: Conversation? {
        guard let currentConversationID else { return nil }
        return conversations.first { $0.id == currentConversationID }
    }
    var lastAnswer: String { conversations.first?.latestAnswer ?? "" }
    @Published var currentState: BulbyState = .idle { didSet { updateStatusIcon() } }

    private var flashTimer: Timer?
    private var isFlashingOn = false
    private var lastNotchTriggerTime: Date = .distantPast
    private var globalNotchMouseMonitor: Any?
    private var localNotchMouseMonitor: Any?

    override init() {
        selectedMode = BulbyPrompts.generalMode
        super.init()
        loadModes()
        loadHistory()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupNotifications()
        setupNotchTrigger()
        screenCaptureAccessConfirmed = screenCaptureService.hasScreenCapturePermission
        fetchOllamaModels()
        warnIfRunningFromDiskImage()
    }

    func saveModes() {
        modeStore.save(customModes)
    }

    func loadModes() {
        customModes = modeStore.load()
    }

    func addMode(name: String, prompt: String, guide: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        let finalPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalGuide = guide.trimmingCharacters(in: .whitespacesAndNewlines)
        customModes.append(CustomMode(
            name: cleanName,
            systemPrompt: BulbyPrompts.customPrompt(finalPrompt),
            guideText: finalGuide.isEmpty ? cleanName : finalGuide
        ))
        saveModes()
    }

    func deleteMode(_ mode: CustomMode) {
        customModes.removeAll { $0.id == mode.id }
        if selectedMode == mode { selectedMode = BulbyPrompts.generalMode }
        saveModes()
    }

    private func loadHistory() {
        conversations = historyStore.load()
        currentConversationID = conversations.first?.id
    }

    private func createConversation(question: String, answer: String, sourceWindowTitles: [String]) -> UUID {
        let turn = ConversationTurn(
            question: historyStore.trimmedField(question),
            answer: historyStore.trimmedField(answer),
            sourceWindowTitles: sourceWindowTitles
        )
        let conversation = Conversation(
            modeName: selectedMode.name,
            modelName: selectedModel,
            turns: [turn]
        )
        conversations.insert(conversation, at: 0)
        if conversations.count > HistoryStore.maxItems {
            conversations.removeLast(conversations.count - HistoryStore.maxItems)
        }
        currentConversationID = conversation.id
        unreadConversationID = conversation.id
        historyStore.save(conversations)
        return conversation.id
    }

    private func appendTurn(to conversationID: UUID, question: String, answer: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        var conversation = conversations.remove(at: index)
        conversation.turns.append(ConversationTurn(
            question: historyStore.trimmedField(question),
            answer: historyStore.trimmedField(answer)
        ))
        conversation.turns = Array(conversation.turns.suffix(HistoryStore.maxTurnsPerConversation))
        conversation.updatedAt = Date()
        conversations.insert(conversation, at: 0)
        currentConversationID = conversation.id
        historyStore.save(conversations)
    }

    private func updatePendingContinuationAnswer(_ answer: String, for conversationID: UUID) {
        guard let pendingContinuation,
              pendingContinuation.conversationID == conversationID else {
            return
        }

        self.pendingContinuation = PendingContinuation(
            conversationID: pendingContinuation.conversationID,
            question: pendingContinuation.question,
            answer: answer
        )
    }

    func deleteHistoryItem(at index: Int) {
        guard conversations.indices.contains(index) else { return }
        let removed = conversations.remove(at: index)
        if currentConversationID == removed.id {
            currentConversationID = conversations.first?.id
        }
        historyStore.save(conversations)
    }

    func clearHistory() {
        conversations.removeAll()
        currentConversationID = nil
        historyStore.save(conversations)
    }

    private func warnIfRunningFromDiskImage() {
        guard Bundle.main.bundlePath.hasPrefix("/Volumes/") else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = "Bulby를 Applications 폴더로 옮긴 뒤 실행하세요"
            alert.informativeText = "DMG 안에서 직접 실행하면 macOS 화면 캡처 권한이 매번 다시 요청되거나 꼬일 수 있습니다. DMG를 열고 Bulby.app을 Applications 폴더로 복사한 뒤, 복사된 앱을 실행하세요."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Applications 열기")
            alert.addButton(withTitle: "계속 실행")

            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
            }
        }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusBarClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusMenu.delegate = self
        updateStatusIcon()
    }

    @objc func statusBarClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showStatusMenu()
        } else if currentState == .done,
                  let unreadConversationID,
                  conversations.contains(where: { $0.id == unreadConversationID }) {
            showConversationWindow(unreadConversationID)
        } else {
            showStatusMenu()
        }
    }

    private func showStatusMenu() {
        fetchOllamaModels()
        refreshScreenCaptureStatus()
        if screenCaptureAccessConfirmed {
            fetchAvailableWindows()
        }
        refreshMenu()
        statusItem.menu = statusMenu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async {
            self.statusItem.menu = nil
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        fetchOllamaModels()
        refreshScreenCaptureStatus()
        if screenCaptureAccessConfirmed {
            fetchAvailableWindows()
        }
        refreshMenu()
    }

    private func refreshMenu() {
        statusMenu.removeAllItems()

        let titleItem = NSMenuItem(title: "Bulby", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        statusMenu.addItem(titleItem)

        let hasScreenCaptureAccess = screenCaptureAccessConfirmed || screenCaptureService.hasScreenCapturePermission
        let captureStatus = hasScreenCaptureAccess ? "화면 캡처: 사용 가능" : "화면 캡처: 권한 필요"
        let captureItem = NSMenuItem(title: captureStatus, action: nil, keyEquivalent: "")
        captureItem.isEnabled = false
        statusMenu.addItem(captureItem)

        let ollamaStatus = isOllamaReachable ? "Ollama: 연결됨" : "Ollama: 연결 필요"
        let ollamaItem = NSMenuItem(title: ollamaStatus, action: nil, keyEquivalent: "")
        ollamaItem.isEnabled = false
        statusMenu.addItem(ollamaItem)
        statusMenu.addItem(NSMenuItem.separator())

        if currentState == .error, let lastErrorMessage {
            let item = NSMenuItem(title: "오류: \(lastErrorMessage)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            statusMenu.addItem(item)
            statusMenu.addItem(NSMenuItem.separator())
        }

        if !conversations.isEmpty {
            addMenuItem("최근 결과 보기", action: #selector(menuActionShowLatest), key: "v")
        }
        addMenuItem("결과 목록 보기", action: #selector(menuActionShowHistory), key: "h")
        statusMenu.addItem(NSMenuItem.separator())

        if !hasScreenCaptureAccess {
            addMenuItem("화면 캡처 권한 허용", action: #selector(menuActionRequestScreenCapturePermission), key: "")
        }
        addMenuItem("권한 설정 열기", action: #selector(menuActionOpenScreenCaptureSettings), key: "")
        statusMenu.addItem(NSMenuItem.separator())

        if !isOllamaReachable {
            addMenuItem("Ollama 열기", action: #selector(menuActionOpenOllama), key: "")
            statusMenu.addItem(NSMenuItem.separator())
        }

        if !selectedWindowIDs.isEmpty {
            addMenuItem("선택한 창 초기화", action: #selector(menuActionClearWindowSelection), key: "")
            statusMenu.addItem(NSMenuItem.separator())
        }

        let modelMenu = NSMenuItem(title: "모델: \(selectedModel)", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        if installedModels.isEmpty {
            sub.addItem(NSMenuItem(title: "설치된 Ollama 모델 없음", action: nil, keyEquivalent: ""))
        } else {
            for model in installedModels {
                let item = NSMenuItem(title: model, action: #selector(menuActionSelectModel(_:)), keyEquivalent: "")
                item.target = self
                item.state = model == selectedModel ? .on : .off
                item.representedObject = model
                sub.addItem(item)
            }
        }

        modelMenu.submenu = sub
        statusMenu.addItem(modelMenu)
        statusMenu.addItem(NSMenuItem.separator())
        addMenuItem("종료", action: #selector(menuActionQuit), key: "q")
    }

    private func addMenuItem(_ title: String, action: Selector, key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        statusMenu.addItem(item)
    }

    @objc func menuActionShowLatest() {
        guard let latestID = conversations.first?.id else { return }
        showConversationWindow(latestID)
    }
    @objc func menuActionShowHistory() { showHistoryWindow() }
    @objc func menuActionSelectModel(_ sender: NSMenuItem) {
        if let model = sender.representedObject as? String { selectedModel = model }
    }
    @objc func menuActionRequestScreenCapturePermission() {
        if screenCaptureService.hasScreenCapturePermission || screenCaptureService.requestScreenCapturePermission() {
            refreshScreenCaptureStatus()
        } else {
            openScreenCaptureSettings()
        }
    }
    @objc func menuActionOpenScreenCaptureSettings() { openScreenCaptureSettings() }
    @objc func menuActionOpenOllama() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Ollama.app"))
    }
    @objc func menuActionClearWindowSelection() {
        selectedWindowIDs.removeAll()
    }
    @objc func menuActionQuit() { NSApp.terminate(nil) }

    private func setupNotchTrigger() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

        globalNotchMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            self?.handleNotchMouseTracking()
        }

        localNotchMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.handleNotchMouseTracking()
            return event
        }
    }

    private func handleNotchMouseTracking() {
        guard let screen = NSScreen.main else { return }
        let mouse = NSEvent.mouseLocation
        let screenMaxY = screen.frame.maxY

        if isExpanded {
            if !visibleNotchFrame(on: screen).contains(mouse) {
                DispatchQueue.main.async { self.hideNotchInput() }
            }
            return
        }

        guard mouse.y > screenMaxY - 200 else { return }

        let isNearNotch = mouse.y > screenMaxY - 1 && abs(mouse.x - screen.frame.midX) < 75
        if isNearNotch && Date().timeIntervalSince(lastNotchTriggerTime) > 0.8 {
            lastNotchTriggerTime = Date()
            DispatchQueue.main.async { self.showNotchInput() }
        }
    }

    private func visibleNotchFrame(on screen: NSScreen) -> NSRect {
        let height: CGFloat = (showPicker || showModeList) ? 360 : 160
        return NSRect(
            x: screen.frame.midX - 250,
            y: screen.frame.maxY - height,
            width: 500,
            height: height
        ).insetBy(dx: -8, dy: -8)
    }

    func showNotchInput() {
        if notchWindow == nil {
            let panel = BulbyPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 420), styleMask: [], backing: .buffered, defer: false)
            panel.contentViewController = NSHostingController(rootView: NotchExtensionView(delegate: self))
            notchWindow = panel
        }

        guard let window = notchWindow, let screen = NSScreen.main else { return }
        window.setAllowsKeyFocus(true)
        window.makeFirstResponder(nil)
        window.ignoresMouseEvents = false
        window.setFrameOrigin(NSPoint(x: screen.frame.midX - 250, y: screen.frame.maxY - window.frame.height))
        window.orderFrontRegardless()
        isExpanded = true
        activateNotchInputFocus()
        notchFocusRequest += 1
    }

    func activateNotchInputFocus() {
        guard isExpanded, let window = notchWindow else { return }
        window.setAllowsKeyFocus(true)
        window.makeKey()
    }

    func hideNotchInput() {
        isExpanded = false
        showPicker = false
        showModeList = false
        showAddModeSheet = false
        notchWindow?.makeFirstResponder(nil)
        notchWindow?.setAllowsKeyFocus(false)
        notchWindow?.resignKey()
        notchWindow?.ignoresMouseEvents = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.isExpanded else { return }
            self.notchWindow?.orderOut(nil)
        }
    }

    func showConversationWindow(_ conversationID: UUID) {
        guard conversations.contains(where: { $0.id == conversationID }) else { return }
        currentConversationID = conversationID
        if unreadConversationID == conversationID {
            unreadConversationID = nil
        }

        if let screen = NSScreen.main {
            let width: CGFloat = 680
            let frame = screen.visibleFrame
            if resultWindow == nil {
                let panel = BulbyPanel(contentRect: .zero, styleMask: [.borderless, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
                panel.contentView = NSHostingView(rootView: ResultView(delegate: self))
                resultWindow = panel
            }
            resultWindow?.setFrame(NSRect(x: frame.maxX - width, y: frame.minY, width: width, height: frame.height), display: true)
        }

        resultWindow?.alphaValue = 1
        resultWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if currentState != .generating {
            currentState = .done
        }
    }

    func hideResultWindow() {
        guard let window = resultWindow else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        } completionHandler: {
            DispatchQueue.main.async {
                window.orderOut(nil)
                window.alphaValue = 1
                if self.currentState == .done {
                    self.currentState = .idle
                }
            }
        }
    }

    func showHistoryWindow() {
        historyWindow?.close()
        historyWindow = nil

        let panel = BulbyPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 640), styleMask: [.borderless, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.center()
        panel.contentView = NSHostingView(rootView: HistoryView(delegate: self))

        historyWindow = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideHistoryWindow() {
        historyWindow?.close()
        historyWindow = nil
    }

    func startNewQuestion() {
        resultWindow?.orderOut(nil)
        hideHistoryWindow()
        if currentState != .generating {
            currentState = .idle
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.showNotchInput()
        }
    }

    func captureAndProcess(prompt: String) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty, currentState != .generating else { return }

        hideNotchInput()
        lastErrorMessage = nil
        currentState = .generating

        let selectedWindowIDs = selectedWindowIDs
        let selectedMode = selectedMode
        let selectedModel = selectedModel
        let myID = Bundle.main.bundleIdentifier ?? ""

        Task {
            do {
                let capture = try await screenCaptureService.capture(selectedWindowIDs: selectedWindowIDs, excludingBundleID: myID)
                let finalPrompt = BulbyPrompts.build(mode: selectedMode, userPrompt: cleanPrompt)
                let answer = try await ollamaClient.generate(model: selectedModel, prompt: finalPrompt, base64Images: capture.base64Images)
                let cleanAnswer = LatexSanitizer.sanitize(answer)

                await MainActor.run {
                    self.screenCaptureAccessConfirmed = true
                    let conversationID = self.createConversation(
                        question: cleanPrompt,
                        answer: cleanAnswer,
                        sourceWindowTitles: capture.sourceWindowTitles
                    )
                    self.lastErrorMessage = nil
                    self.currentConversationID = conversationID
                    self.currentState = .done
                }
            } catch let error as ScreenCaptureError {
                await MainActor.run { self.fail(error.userMessage) }
            } catch let error as OllamaClientError {
                await MainActor.run { self.fail(error.userMessage) }
            } catch {
                await MainActor.run { self.fail("요청 처리에 실패했습니다") }
            }
        }
    }

    @MainActor
    func continueConversation(in conversationID: UUID, prompt: String) async {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty,
              let conversation = conversations.first(where: { $0.id == conversationID }),
              currentState != .generating else { return }

        lastErrorMessage = nil
        currentConversationID = conversationID
        pendingContinuation = PendingContinuation(conversationID: conversationID, question: cleanPrompt, answer: "")
        currentState = .generating
        showConversationWindow(conversationID)

        let selectedMode = selectedMode
        let selectedModel = selectedModel
        let finalPrompt = BulbyPrompts.buildFollowUp(
            mode: selectedMode,
            conversation: conversation,
            userPrompt: cleanPrompt
        )

        do {
            let answer = try await ollamaClient.generateStreaming(model: selectedModel, prompt: finalPrompt, base64Images: []) { [weak self] partialAnswer in
                self?.updatePendingContinuationAnswer(LatexSanitizer.sanitize(partialAnswer), for: conversationID)
            }
            let cleanAnswer = LatexSanitizer.sanitize(answer)
            appendTurn(to: conversationID, question: cleanPrompt, answer: cleanAnswer)
            pendingContinuation = nil
            lastErrorMessage = nil
            currentState = .done
        } catch let error as OllamaClientError {
            pendingContinuation = nil
            fail(error.userMessage)
        } catch {
            pendingContinuation = nil
            fail("이어지는 질문 처리에 실패했습니다")
        }
    }

    func setupNotifications() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func fetchOllamaModels() {
        Task {
            do {
                let names = try await ollamaClient.fetchModels()
                await MainActor.run {
                    self.isOllamaReachable = true
                    self.installedModels = names
                    if !names.contains(self.selectedModel), let first = names.first {
                        self.selectedModel = first
                    }
                }
            } catch {
                await MainActor.run {
                    self.isOllamaReachable = false
                    self.installedModels = []
                }
            }
        }
    }

    func fetchAvailableWindows() {
        guard screenCaptureAccessConfirmed || screenCaptureService.hasScreenCapturePermission else {
            availableWindows = []
            screenCaptureAccessConfirmed = false
            return
        }

        let myID = Bundle.main.bundleIdentifier ?? ""
        Task {
            guard let windows = try? await screenCaptureService.availableWindows(excludingBundleID: myID) else { return }
            await MainActor.run {
                self.screenCaptureAccessConfirmed = true
                self.availableWindows = windows
                let liveWindowIDs = Set(windows.map(\.windowID))
                self.selectedWindowIDs.formIntersection(liveWindowIDs)
            }
        }
    }

    private func refreshScreenCaptureStatus() {
        screenCaptureAccessConfirmed = screenCaptureService.hasScreenCapturePermission
    }

    private func fail(_ message: String) {
        lastErrorMessage = message
        currentState = .error
    }

    private func openScreenCaptureSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private func updateStatusIcon() {
        DispatchQueue.main.async {
            self.stopFlashing()
            self.statusItem.button?.image = NSImage(systemSymbolName: self.currentState.iconName, accessibilityDescription: "Bulby")
            if self.currentState == .generating { self.startFlashing() }
        }
    }

    private func startFlashing() {
        guard flashTimer == nil else { return }
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let button = self.statusItem.button else { return }
            self.isFlashingOn.toggle()
            button.image = NSImage(systemSymbolName: self.isFlashingOn ? "lightbulb.fill" : "lightbulb", accessibilityDescription: "Bulby")
        }
    }

    private func stopFlashing() {
        flashTimer?.invalidate()
        flashTimer = nil
    }
}
