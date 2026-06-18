import AppKit
import ScreenCaptureKit
import SwiftUI

enum BulbyTheme {
    static let canvas = Color(red: 0.985, green: 0.976, blue: 0.946)
    static let surface = Color(red: 1.0, green: 0.996, blue: 0.982)
    static let elevated = Color(red: 1.0, green: 1.0, blue: 0.992)
    static let accent = Color(red: 0.20, green: 0.34, blue: 0.82)
    static let accentSoft = Color(red: 0.90, green: 0.92, blue: 0.99)
    static let ink = Color(red: 0.13, green: 0.13, blue: 0.12)
    static let muted = Color(red: 0.46, green: 0.44, blue: 0.39)
    static let warmShadow = Color.black.opacity(0.12)
    static let hairlineShadow = Color.black.opacity(0.06)
}

extension View {
    func bulbyFloatingShadow(radius: CGFloat = 18, y: CGFloat = 10) -> some View {
        shadow(color: BulbyTheme.warmShadow, radius: radius, x: 0, y: y)
            .shadow(color: BulbyTheme.hairlineShadow, radius: 2, x: 0, y: 1)
    }
}

struct NotchExtensionView: View {
    @ObservedObject var delegate: AppDelegate
    @State private var prompt = ""
    @State private var newName = ""
    @State private var newPrompt = ""
    @State private var newGuide = ""

    var currentHeight: CGFloat {
        if !delegate.isExpanded { return 32 }
        if delegate.showModeList || delegate.showPicker { return 360 }
        return 160
    }

    var body: some View {
        ZStack(alignment: .top) {
            VisualEffectView(material: .hudWindow)
                .clipShape(CustomNotchShape(radius: 35))
                .frame(width: delegate.isExpanded ? 500 : 160, height: currentHeight)
                .bulbyFloatingShadow(radius: 18, y: 8)

            VStack(spacing: 0) {
                header
                if delegate.showModeList { modeList }
                else if delegate.showPicker { windowPicker }

                Spacer()

                NotchPromptField(
                    placeholder: delegate.selectedMode.guideText,
                    text: $prompt,
                    focusRequest: delegate.notchFocusRequest,
                    onFocusIntent: { delegate.activateNotchInputFocus() }
                ) {
                    delegate.captureAndProcess(prompt: prompt)
                    prompt = ""
                }
                .padding(.horizontal, 35)
                .padding(.bottom, 30)
            }
            .frame(width: 500, height: currentHeight, alignment: .top)
            .opacity(delegate.isExpanded ? 1 : 0)
        }
        .frame(width: 500, height: currentHeight, alignment: .top)
        .clipShape(CustomNotchShape(radius: 35))
        .animation(.easeInOut(duration: 0.2), value: delegate.isExpanded)
        .animation(.easeInOut(duration: 0.2), value: currentHeight)
        .frame(width: 500, height: 420, alignment: .top)
        .sheet(isPresented: $delegate.showAddModeSheet) { addModeSheet }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                ModeButton(title: "General", isSelected: delegate.selectedMode.name == "General") {
                    delegate.selectedMode = BulbyPrompts.generalMode
                    delegate.showModeList = false
                }

                let isCustom = delegate.selectedMode.name != "General"
                Button {
                    delegate.showModeList.toggle()
                    delegate.showPicker = false
                } label: {
                    HStack {
                        Text(isCustom ? delegate.selectedMode.name : "MODE")
                            .font(.system(size: 9, weight: .black))
                        Image(systemName: delegate.showModeList ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isCustom ? BulbyTheme.accent : Color.primary.opacity(0.1))
                    .foregroundColor(isCustom ? .white : .primary.opacity(0.5))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                delegate.fetchAvailableWindows()
                delegate.showPicker.toggle()
                delegate.showModeList = false
            } label: {
                Image(systemName: delegate.selectedWindowIDs.isEmpty ? "macwindow" : "macwindow.badge.plus")
                    .font(.system(size: 14))
                    .foregroundColor(delegate.selectedWindowIDs.isEmpty ? .primary.opacity(0.6) : BulbyTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 30)
        .padding(.top, 25)
    }

    private var modeList: some View {
        VStack(alignment: .center, spacing: 10) {
            Button {
                delegate.activateNotchInputFocus()
                delegate.showAddModeSheet.toggle()
            } label: {
                Text("+ ADD MODE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(BulbyTheme.accent)
            }
            .buttonStyle(.plain)

            ScrollView {
                VStack(alignment: .center, spacing: 6) {
                    ForEach(delegate.customModes) { mode in
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            ModeButton(title: mode.name, isSelected: delegate.selectedMode == mode) {
                                delegate.selectedMode = mode
                                delegate.showModeList = false
                            }
                            Button { delegate.deleteMode(mode) } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.red.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .padding(.horizontal, 30)
        .padding(.top, 15)
    }

    private var windowPicker: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(delegate.availableWindows, id: \.windowID) { window in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(window.title ?? "Unknown")
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                if let appName = window.owningApplication?.applicationName, !appName.isEmpty {
                                    Text(appName)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if delegate.selectedWindowIDs.contains(window.windowID) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(BulbyTheme.accent)
                            }
                        }
                        .padding(8)
                        .background(BulbyTheme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .bulbyFloatingShadow(radius: 5, y: 2)
                        .onTapGesture {
                            if delegate.selectedWindowIDs.contains(window.windowID) {
                                delegate.selectedWindowIDs.remove(window.windowID)
                            } else {
                                delegate.selectedWindowIDs.insert(window.windowID)
                            }
                        }
                    }
                }
            }
            .frame(height: 160)

            Button("DONE") { delegate.showPicker = false }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 30)
        .padding(.top, 15)
    }

    private var addModeSheet: some View {
        VStack(spacing: 15) {
            Text("나만의 업무 모드 만들기").font(.headline)
            TextField("모드 이름", text: $newName).textFieldStyle(.roundedBorder)
            TextField("시스템 프롬프트", text: $newPrompt).textFieldStyle(.roundedBorder)
            TextField("가이드 텍스트", text: $newGuide).textFieldStyle(.roundedBorder)
            HStack {
                Button("취소") { delegate.showAddModeSheet = false }
                Button("저장") {
                    delegate.addMode(name: newName, prompt: newPrompt, guide: newGuide)
                    newName = ""
                    newPrompt = ""
                    newGuide = ""
                    delegate.showAddModeSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

final class FocusIntentTextField: NSTextField {
    var onFocusIntent: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onFocusIntent?()
        super.mouseDown(with: event)
    }
}

struct NotchPromptField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let focusRequest: Int
    let onFocusIntent: () -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> FocusIntentTextField {
        let field = FocusIntentTextField()
        field.delegate = context.coordinator
        field.onFocusIntent = onFocusIntent
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 16, weight: .semibold)
        field.textColor = .labelColor
        field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ nsView: FocusIntentTextField, context: Context) {
        context.coordinator.parent = self
        nsView.onFocusIntent = onFocusIntent
        nsView.placeholderString = placeholder
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if context.coordinator.appliedFocusRequest != focusRequest {
            context.coordinator.appliedFocusRequest = focusRequest
            DispatchQueue.main.async {
                onFocusIntent()
                nsView.window?.makeFirstResponder(nsView)
                nsView.currentEditor()?.selectedRange = NSRange(location: nsView.stringValue.count, length: 0)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NotchPromptField
        var appliedFocusRequest = 0

        init(_ parent: NotchPromptField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.text = control.stringValue
            parent.onSubmit()
            return true
        }
    }
}

struct ResultView: View {
    @ObservedObject var delegate: AppDelegate

    private var conversation: Conversation? {
        delegate.currentConversation
    }

    private var pendingContinuation: PendingContinuation? {
        guard let conversation,
              let pending = delegate.pendingContinuation,
              pending.conversationID == conversation.id else {
            return nil
        }
        return pending
    }

    var body: some View {
        ZStack {
            BulbyTheme.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                resultHeader

                if let conversation {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                ForEach(conversation.turns) { turn in
                                    ConversationTurnView(turn: turn)
                                }

                                if let pendingContinuation {
                                    PendingConversationTurnView(
                                        question: pendingContinuation.question,
                                        answer: pendingContinuation.answer
                                    )
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id("conversation-bottom")
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 18)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear { scrollToBottom(proxy) }
                        .onChange(of: conversation.turns.count) { _, _ in scrollToBottom(proxy) }
                        .onChange(of: pendingContinuation?.question) { _, _ in scrollToBottom(proxy) }
                        .onChange(of: pendingContinuation?.answer) { _, _ in scrollToBottom(proxy) }
                    }

                    bottomComposer(for: conversation)
                } else {
                    Spacer()
                    Text("No conversation selected")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(BulbyTheme.muted)
                        .frame(maxWidth: .infinity)
                    Spacer()
                }

                if delegate.currentState == .error, let message = delegate.lastErrorMessage {
                    Text(message)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.red.opacity(0.85))
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                }
            }
            .padding(14)
        }
        .frame(minWidth: 680, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var resultHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(BulbyTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .bulbyFloatingShadow(radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Bulby Insight")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(BulbyTheme.muted)

                    ResultStatusBadge(state: delegate.currentState, hasPending: pendingContinuation != nil)
                }

                Text(pendingContinuation?.question ?? conversation?.title ?? "최근 답변")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(BulbyTheme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let conversation {
                    HStack(spacing: 6) {
                        MetadataPill(text: conversation.modeName, systemImage: "slider.horizontal.3")
                        MetadataPill(text: conversation.modelName, systemImage: "cpu")
                        MetadataPill(text: "\(conversation.turns.count + (pendingContinuation == nil ? 0 : 1))턴", systemImage: "bubble.left.and.bubble.right")
                    }
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button {
                    delegate.showHistoryWindow()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .frame(width: 32, height: 32)
                        .background(BulbyTheme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .bulbyFloatingShadow(radius: 7, y: 3)
                }
                .buttonStyle(.plain)
                .help("히스토리")

                Button { delegate.hideResultWindow() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 32)
                        .background(BulbyTheme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .bulbyFloatingShadow(radius: 7, y: 3)
                }
                .buttonStyle(.plain)
                .foregroundColor(BulbyTheme.muted)
                .help("닫기")
            }
            .font(.system(size: 13, weight: .bold))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BulbyTheme.surface)
        )
        .bulbyFloatingShadow(radius: 18, y: 8)
    }

    private func bottomComposer(for conversation: Conversation) -> some View {
        VStack(spacing: 10) {
            FollowUpComposer(
                placeholder: "이 대화에서 이어 묻기...",
                isBusy: delegate.currentState == .generating
            ) { prompt in
                await delegate.continueConversation(in: conversation.id, prompt: prompt)
            }

            if delegate.currentState == .generating, pendingContinuation != nil {
                Text("답변창에서 계속 생성 중입니다.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(BulbyTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BulbyTheme.surface)
        )
        .bulbyFloatingShadow(radius: 16, y: 7)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
        }
    }
}

struct ConversationTurnView: View {
    let turn: ConversationTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Spacer(minLength: 70)
                VStack(alignment: .leading, spacing: 7) {
                    Label("질문", systemImage: "person.crop.circle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(BulbyTheme.accent)
                    Text(turn.question)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(BulbyTheme.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(BulbyTheme.accentSoft)
                )
                .bulbyFloatingShadow(radius: 9, y: 4)
            }

            if !turn.sourceWindowTitles.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "macwindow")
                    Text(turn.sourceWindowTitles.joined(separator: ", "))
                        .lineLimit(1)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(BulbyTheme.muted)
                .padding(.horizontal, 2)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("답변", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(BulbyTheme.accent)
                Text(turn.answer)
                    .font(.system(size: 15))
                    .foregroundColor(BulbyTheme.ink)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(BulbyTheme.elevated)
            )
            .bulbyFloatingShadow(radius: 12, y: 6)
        }
    }
}

struct PendingConversationTurnView: View {
    let question: String
    let answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Spacer(minLength: 70)
                VStack(alignment: .leading, spacing: 7) {
                    Label("질문", systemImage: "person.crop.circle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(BulbyTheme.accent)
                    Text(question)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(BulbyTheme.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(BulbyTheme.accentSoft)
                )
                .bulbyFloatingShadow(radius: 9, y: 4)
            }

            HStack(spacing: 10) {
                if answer.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("답변 생성 중", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(BulbyTheme.accent)

                    if answer.isEmpty {
                        Text("이 창에서 이어지는 답변을 준비하고 있습니다.")
                            .font(.system(size: 13))
                            .foregroundColor(BulbyTheme.muted)
                    } else {
                        Text(answer)
                            .font(.system(size: 15))
                            .foregroundColor(BulbyTheme.ink)
                            .lineSpacing(6)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(BulbyTheme.elevated)
            )
            .bulbyFloatingShadow(radius: 12, y: 6)
        }
    }
}

struct ResultStatusBadge: View {
    let state: BulbyState
    let hasPending: Bool

    private var text: String {
        if hasPending { return "생성 중" }
        switch state {
        case .idle: return "대기"
        case .generating: return "생성 중"
        case .done: return "완료"
        case .error: return "오류"
        }
    }

    private var color: Color {
        if hasPending { return BulbyTheme.accent }
        switch state {
        case .error: return .red
        case .generating: return BulbyTheme.accent
        case .done: return .green
        case .idle: return BulbyTheme.muted
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

struct MetadataPill: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(BulbyTheme.muted)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(BulbyTheme.elevated)
        .clipShape(Capsule())
        .bulbyFloatingShadow(radius: 5, y: 2)
    }
}

struct HistoryView: View {
    @ObservedObject var delegate: AppDelegate

    var body: some View {
        ZStack {
            BulbyTheme.canvas.ignoresSafeArea()

            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(BulbyTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Answer History")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(BulbyTheme.ink)
                        Text("\(delegate.conversations.count) conversations")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(BulbyTheme.muted)
                    }

                    Spacer()

                    if !delegate.conversations.isEmpty {
                        Button("Clear") { delegate.clearHistory() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.red.opacity(0.78))
                    }

                    Button { delegate.hideHistoryWindow() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(BulbyTheme.muted)
                            .frame(width: 32, height: 32)
                            .background(BulbyTheme.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .bulbyFloatingShadow(radius: 7, y: 3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(BulbyTheme.surface)
                )
                .bulbyFloatingShadow(radius: 18, y: 8)

                if delegate.conversations.isEmpty {
                    Spacer()
                    Text("No history yet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(BulbyTheme.muted)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(Array(delegate.conversations.enumerated()), id: \.element.id) { index, conversation in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(alignment: .top, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(conversation.title)
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(BulbyTheme.ink)
                                                .lineLimit(2)

                                            Text(conversation.latestAnswer)
                                                .font(.system(size: 12))
                                                .lineSpacing(3)
                                                .lineLimit(4)
                                                .foregroundColor(BulbyTheme.muted)
                                        }

                                        Spacer(minLength: 12)

                                        Text("\(conversation.turns.count)턴")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(BulbyTheme.accent)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(BulbyTheme.accentSoft)
                                            .clipShape(Capsule())
                                    }

                                    FollowUpComposer(
                                        placeholder: "이 대화에서 이어 묻기...",
                                        isBusy: delegate.currentState == .generating
                                    ) { prompt in
                                        await delegate.continueConversation(in: conversation.id, prompt: prompt)
                                    }

                                    HStack(spacing: 8) {
                                        Button("열기") { delegate.showConversationWindow(conversation.id) }
                                            .buttonStyle(.plain)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(BulbyTheme.accent)
                                            .clipShape(Capsule())
                                            .bulbyFloatingShadow(radius: 6, y: 3)

                                        Button("삭제") { delegate.deleteHistoryItem(at: index) }
                                            .buttonStyle(.plain)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(BulbyTheme.muted)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(BulbyTheme.elevated)
                                            .clipShape(Capsule())
                                            .bulbyFloatingShadow(radius: 6, y: 3)

                                        Spacer()
                                    }
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(BulbyTheme.surface)
                                )
                                .bulbyFloatingShadow(radius: 14, y: 7)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(14)
        }
        .frame(minWidth: 600, minHeight: 640)
        .ignoresSafeArea()
    }
}

struct ModeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .black))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? BulbyTheme.accent : Color.primary.opacity(0.1))
                .foregroundColor(isSelected ? .white : .primary.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct FollowUpComposer: View {
    let placeholder: String
    let isBusy: Bool
    let action: (String) async -> Void

    @State private var prompt = ""
    @State private var isSending = false

    private var cleanPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !cleanPrompt.isEmpty && !isBusy && !isSending
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $prompt)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .onSubmit(submit)
                .disabled(isBusy || isSending)
                .padding(.leading, 12)
                .padding(.vertical, 10)

            if isSending {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 30, height: 30)
                    .padding(.trailing, 6)
            } else {
                Button(action: submit) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(canSend ? BulbyTheme.accent : Color.primary.opacity(0.06))
                        .foregroundColor(canSend ? .white : .secondary.opacity(0.55))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("이어 묻기")
                .padding(.trailing, 6)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BulbyTheme.elevated)
        )
        .bulbyFloatingShadow(radius: 8, y: 3)
    }

    private func submit() {
        let promptToSend = cleanPrompt
        guard canSend else { return }

        prompt = ""
        isSending = true
        Task {
            await action(promptToSend)
            await MainActor.run {
                isSending = false
            }
        }
    }
}

struct CustomNotchShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
