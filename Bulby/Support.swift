import AppKit
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct CustomMode: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var systemPrompt: String
    var guideText: String
}

struct ConversationTurn: Identifiable, Codable, Equatable {
    var id = UUID()
    var question: String
    var answer: String
    var createdAt = Date()
    var sourceWindowTitles: [String] = []
}

struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var updatedAt = Date()
    var modeName: String
    var modelName: String
    var turns: [ConversationTurn]

    var title: String {
        turns.first?.question.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Untitled"
    }

    var latestAnswer: String {
        turns.last?.answer ?? ""
    }

    var latestQuestion: String {
        turns.last?.question ?? ""
    }
}

struct PendingContinuation: Equatable {
    let conversationID: UUID
    let question: String
    let answer: String
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

enum BulbyState {
    case idle, generating, done, error

    var iconName: String {
        switch self {
        case .idle: return "lightbulb"
        case .generating: return "lightbulb.fill"
        case .done: return "lightbulb.max.fill"
        case .error: return "lightbulb.slash"
        }
    }
}

class BulbyPanel: NSPanel {
    var allowsKeyFocus = true

    override var canBecomeKey: Bool { allowsKeyFocus }
    override var canBecomeMain: Bool { allowsKeyFocus }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        let resolvedStyle: NSWindow.StyleMask = style.isEmpty
            ? [.nonactivatingPanel, .borderless, .resizable]
            : style
        super.init(contentRect: contentRect, styleMask: resolvedStyle, backing: backingStoreType, defer: flag)
        isFloatingPanel = true
        level = .mainMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    func setAllowsKeyFocus(_ allowed: Bool) {
        allowsKeyFocus = allowed
        if !allowed {
            makeFirstResponder(nil)
            resignKey()
        }
    }
}

enum AppPreferences {
    private static let selectedModelKey = "SelectedModel"
    private static let defaultModel = "gemma4:e4b"

    static var selectedModel: String {
        get { UserDefaults.standard.string(forKey: selectedModelKey) ?? defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: selectedModelKey) }
    }
}

enum BulbyPrompts {
    static let noLatexRule = "절대 LaTeX 문법을 사용하지 마세요. $, \\( \\), \\[ \\], \\frac, \\sqrt, \\mathbb, \\text 같은 LaTeX 표현을 쓰지 말고 일반 텍스트와 유니코드 기호만 사용하세요."

    static let generalMode = CustomMode(
        name: "General",
        systemPrompt: "사용자의 질문이나 요청에 정확하고 간결하게 답변하세요. \(noLatexRule)",
        guideText: "Bulby에게 질문하기"
    )

    static let defaultTranslateMode = CustomMode(
        name: "Translate",
        systemPrompt: "제공된 화면의 내용을 한국어로 자연스럽게 번역하세요. \(noLatexRule) 수식은 ℝ, ⁿ, ±, √, θ 같은 유니코드 기호와 일반 텍스트로만 표현하세요.",
        guideText: "번역 요청..."
    )

    static func customPrompt(_ prompt: String) -> String {
        prompt.isEmpty ? noLatexRule : "\(prompt)\n\(noLatexRule)"
    }

    static func build(mode: CustomMode, userPrompt: String) -> String {
        let systemPrompt = mode.systemPrompt.contains(noLatexRule)
            ? mode.systemPrompt
            : "\(mode.systemPrompt)\n\(noLatexRule)"

        return """
        System Instruction:
        \(systemPrompt)

        User Question:
        \(userPrompt)
        """
    }

    static func buildFollowUp(mode: CustomMode, previousAnswer: String, userPrompt: String) -> String {
        let systemPrompt = mode.systemPrompt.contains(noLatexRule)
            ? mode.systemPrompt
            : "\(mode.systemPrompt)\n\(noLatexRule)"

        return """
        System Instruction:
        \(systemPrompt)
        이전 Bulby 답변을 대화 맥락으로 삼아 이어서 답하세요.
        새 화면 캡처는 제공되지 않았으므로 이전 답변에 없는 화면 내용은 추측하지 마세요.

        Previous Bulby Answer:
        \(previousAnswer)

        Follow-up Question:
        \(userPrompt)
        """
    }

    static func buildFollowUp(mode: CustomMode, conversation: Conversation, userPrompt: String) -> String {
        let systemPrompt = mode.systemPrompt.contains(noLatexRule)
            ? mode.systemPrompt
            : "\(mode.systemPrompt)\n\(noLatexRule)"
        let context = conversation.turns.enumerated().map { index, turn in
            """
            Turn \(index + 1)
            User:
            \(turn.question)

            Bulby:
            \(turn.answer)
            """
        }.joined(separator: "\n\n")

        return """
        System Instruction:
        \(systemPrompt)
        아래의 이전 대화 전체를 맥락으로 삼아 이어서 답하세요.
        새 화면 캡처는 제공되지 않았으므로 이전 대화에 없는 화면 내용은 추측하지 마세요.

        Conversation So Far:
        \(context)

        Follow-up Question:
        \(userPrompt)
        """
    }
}

struct ModeStore {
    private let key = "CustomModes"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [CustomMode] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CustomMode].self, from: data) else {
            return [BulbyPrompts.defaultTranslateMode]
        }
        return decoded
    }

    func save(_ modes: [CustomMode]) {
        guard let encoded = try? JSONEncoder().encode(modes) else { return }
        defaults.set(encoded, forKey: key)
    }
}

struct HistoryStore {
    static let maxItems = 50
    static let maxTurnsPerConversation = 30
    static let maxCharactersPerField = 20_000

    private let key = "ConversationHistory"
    private let legacyKey = "ResponseHistory"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [Conversation] {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Conversation].self, from: data) {
            return Array(decoded.prefix(Self.maxItems)).map(trimmedConversation)
        }

        guard let legacyItems = defaults.stringArray(forKey: legacyKey) else { return [] }
        return Array(legacyItems.prefix(Self.maxItems)).map { answer in
            Conversation(
                modeName: "General",
                modelName: AppPreferences.selectedModel,
                turns: [ConversationTurn(question: "이전 답변", answer: trimmedField(answer))]
            )
        }
    }

    func save(_ conversations: [Conversation]) {
        let bounded = Array(conversations.prefix(Self.maxItems)).map(trimmedConversation)
        guard let encoded = try? JSONEncoder().encode(bounded) else { return }
        defaults.set(encoded, forKey: key)
    }

    func trimmedField(_ text: String) -> String {
        guard text.count > Self.maxCharactersPerField else { return text }
        return String(text.prefix(Self.maxCharactersPerField))
    }

    func trimmedConversation(_ conversation: Conversation) -> Conversation {
        var copy = conversation
        copy.turns = Array(copy.turns.prefix(Self.maxTurnsPerConversation)).map { turn in
            ConversationTurn(
                id: turn.id,
                question: trimmedField(turn.question),
                answer: trimmedField(turn.answer),
                createdAt: turn.createdAt,
                sourceWindowTitles: turn.sourceWindowTitles
            )
        }
        return copy
    }
}

struct ScreenCaptureResult {
    let base64Images: [String]
    let sourceWindowTitles: [String]
}

enum LatexSanitizer {
    static func sanitize(_ text: String) -> String {
        guard text.contains("\\") || text.contains("$") else { return text }

        var result = String()
        result.reserveCapacity(text.count)

        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "$" {
                index = text.index(after: index)
                continue
            }

            guard text[index] == "\\" else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }

            let slashIndex = index
            let nextIndex = text.index(after: index)
            guard nextIndex < text.endIndex else {
                result.append(text[slashIndex])
                index = nextIndex
                continue
            }

            switch text[nextIndex] {
            case "(", ")", "[", "]":
                index = text.index(after: nextIndex)
                continue
            default:
                break
            }

            var commandEnd = nextIndex
            while commandEnd < text.endIndex, text[commandEnd].isLetter {
                commandEnd = text.index(after: commandEnd)
            }

            guard commandEnd > nextIndex else {
                result.append(text[slashIndex])
                index = nextIndex
                continue
            }

            let command = text[nextIndex..<commandEnd]
            if command == "mathbb",
               commandEnd < text.endIndex,
               text[commandEnd] == "{",
               let groupEnd = text[commandEnd...].firstIndex(of: "}") {
                let lookupEnd = text.index(after: groupEnd)
                let groupedCommand = text[nextIndex..<lookupEnd]
                if let replacement = replacement(for: groupedCommand) {
                    result.append(replacement)
                    index = lookupEnd
                    continue
                }
            }

            if let replacement = replacement(for: command) {
                result.append(replacement)
            } else {
                result.append(contentsOf: text[slashIndex..<commandEnd])
            }
            index = commandEnd
        }

        return result
    }

    private static func replacement(for command: Substring) -> String? {
        switch command {
        case "mathbb{R}": return "ℝ"
        case "mathbb{N}": return "ℕ"
        case "mathbb{Z}": return "ℤ"
        case "mathbb{Q}": return "ℚ"
        case "frac": return "분수"
        case "sqrt": return "√"
        case "theta": return "θ"
        case "alpha": return "α"
        case "beta": return "β"
        case "pi": return "π"
        case "times": return "×"
        case "cdot": return "·"
        case "leq": return "≤"
        case "geq": return "≥"
        case "neq": return "≠"
        default: return nil
        }
    }
}

enum OllamaClientError: Error {
    case invalidURL
    case badResponse
    case connectionFailed
    case serverError(String)

    var userMessage: String {
        switch self {
        case .invalidURL: return "Ollama 주소가 올바르지 않습니다"
        case .badResponse: return "Ollama 응답을 읽지 못했습니다"
        case .connectionFailed: return "Ollama에 연결하지 못했습니다"
        case .serverError(let message): return message
        }
    }
}

struct OllamaClient {
    private let baseURL = URL(string: "http://127.0.0.1:11434")

    func fetchModels() async throws -> [String] {
        guard let url = baseURL?.appendingPathComponent("api/tags") else {
            throw OllamaClientError.invalidURL
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["models"] as? [[String: Any]] else {
                throw OllamaClientError.badResponse
            }
            return list.compactMap { $0["name"] as? String }
        } catch let error as OllamaClientError {
            throw error
        } catch {
            throw OllamaClientError.connectionFailed
        }
    }

    func generate(model: String, prompt: String, base64Images: [String]) async throws -> String {
        guard let url = baseURL?.appendingPathComponent("api/generate") else {
            throw OllamaClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "keep_alive": 0
        ]
        if !base64Images.isEmpty {
            payload["images"] = base64Images
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["response"] as? String else {
                throw OllamaClientError.badResponse
            }
            return text
        } catch let error as OllamaClientError {
            throw error
        } catch {
            throw OllamaClientError.connectionFailed
        }
    }

    func generateStreaming(
        model: String,
        prompt: String,
        base64Images: [String],
        onPartialResponse: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard let url = baseURL?.appendingPathComponent("api/generate") else {
            throw OllamaClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": true,
            "keep_alive": 0
        ]
        if !base64Images.isEmpty {
            payload["images"] = base64Images
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw OllamaClientError.badResponse
            }

            var accumulated = ""

            for try await line in bytes.lines {
                guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw OllamaClientError.badResponse
                }

                if let message = json["error"] as? String {
                    throw OllamaClientError.serverError(message)
                }

                if let token = json["response"] as? String, !token.isEmpty {
                    accumulated += token
                    onPartialResponse(accumulated)
                }

                if (json["done"] as? Bool) == true {
                    break
                }
            }

            return accumulated
        } catch let error as OllamaClientError {
            throw error
        } catch {
            throw OllamaClientError.connectionFailed
        }
    }
}

enum ScreenCaptureError: Error {
    case permissionDenied
    case noTargets
    case noImages
    case captureFailed

    var userMessage: String {
        switch self {
        case .permissionDenied: return "화면 캡처 권한이 필요합니다. 허용 후 Bulby를 완전히 종료하고 다시 실행하세요"
        case .noTargets: return "캡처할 창을 찾지 못했습니다"
        case .noImages: return "화면 이미지를 만들지 못했습니다"
        case .captureFailed: return "화면 캡처 권한 또는 캡처에 실패했습니다"
        }
    }
}

struct ScreenCaptureService {
    var hasScreenCapturePermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenCapturePermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func availableWindows(excludingBundleID myID: String) async throws -> [SCWindow] {
        guard hasScreenCapturePermission else {
            throw ScreenCaptureError.permissionDenied
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            return validWindows(from: content.windows, excludingBundleID: myID)
        } catch {
            throw hasScreenCapturePermission ? ScreenCaptureError.captureFailed : ScreenCaptureError.permissionDenied
        }
    }

    func capture(selectedWindowIDs: Set<CGWindowID>, excludingBundleID myID: String) async throws -> ScreenCaptureResult {
        guard hasScreenCapturePermission else {
            throw ScreenCaptureError.permissionDenied
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let targets = resolveCaptureTargets(from: content.windows, selectedWindowIDs: selectedWindowIDs, excludingBundleID: myID)
            guard !targets.isEmpty else { throw ScreenCaptureError.noTargets }

            var base64Images: [String] = []
            var sourceWindowTitles: [String] = []
            let config = SCStreamConfiguration()
            config.showsCursor = false

            for target in targets {
                let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: config)
                if let data = jpegData(from: image) {
                    base64Images.append(data.base64EncodedString())
                    let title = target.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let appName = target.owningApplication?.applicationName ?? ""
                    sourceWindowTitles.append(title.isEmpty ? appName : "\(appName) - \(title)")
                }
            }

            guard !base64Images.isEmpty else { throw ScreenCaptureError.noImages }
            return ScreenCaptureResult(base64Images: base64Images, sourceWindowTitles: sourceWindowTitles)
        } catch let error as ScreenCaptureError {
            throw error
        } catch {
            throw ScreenCaptureError.captureFailed
        }
    }

    private func resolveCaptureTargets(from windows: [SCWindow], selectedWindowIDs: Set<CGWindowID>, excludingBundleID myID: String) -> [SCWindow] {
        let validWindows = validWindows(from: windows, excludingBundleID: myID)

        if !selectedWindowIDs.isEmpty {
            return validWindows.filter { selectedWindowIDs.contains($0.windowID) }
        }

        if let activeAppID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           activeAppID != myID,
           let activeWindow = validWindows.first(where: { $0.owningApplication?.bundleIdentifier == activeAppID }) {
            return [activeWindow]
        }

        return validWindows.first.map { [$0] } ?? []
    }

    private func validWindows(from windows: [SCWindow], excludingBundleID myID: String) -> [SCWindow] {
        let blockedBundleIDs: Set<String> = [
            myID,
            "com.apple.dock",
            "com.apple.WindowManager",
            "com.apple.controlcenter",
            "com.apple.notificationcenterui",
            "com.apple.systemuiserver",
            "com.apple.Spotlight",
            "com.apple.loginwindow",
            "com.apple.wallpaper",
            "com.apple.ScreenSaver.Engine"
        ]

        return windows
            .filter { window in
                guard window.isOnScreen,
                      let app = window.owningApplication else {
                    return false
                }

                let bundleID = app.bundleIdentifier
                guard !blockedBundleIDs.contains(bundleID) else {
                    return false
                }

                let title = (window.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard isUserFacingWindowTitle(title) else { return false }

                let frame = window.frame
                guard frame.width >= 100, frame.height >= 80 else { return false }
                return true
            }
            .sorted { lhs, rhs in
                let leftApp = lhs.owningApplication?.applicationName ?? ""
                let rightApp = rhs.owningApplication?.applicationName ?? ""
                if leftApp != rightApp {
                    return leftApp.localizedCaseInsensitiveCompare(rightApp) == .orderedAscending
                }
                return (lhs.title ?? "").localizedCaseInsensitiveCompare(rhs.title ?? "") == .orderedAscending
            }
    }

    private func isUserFacingWindowTitle(_ title: String) -> Bool {
        guard !title.isEmpty else { return false }

        let lowercased = title.lowercased()
        if lowercased == "item" ||
            lowercased.hasPrefix("item ") ||
            lowercased.hasPrefix("item-") ||
            lowercased == "dock" ||
            lowercased == "desktop" ||
            lowercased == "window" {
            return false
        }

        return true
    }

    private func jpegData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let options: CFDictionary = [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
