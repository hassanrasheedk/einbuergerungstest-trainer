import SwiftUI

/// How a question's answers behave.
enum AnswerMode {
    /// Practice: tapping locks in and reveals right/wrong.
    case practice(chosen: Int?)
    /// Exam: tapping selects, nothing is revealed.
    case exam(chosen: Int?)
    /// Catalog / review: correct answer (and optionally the user's pick) shown.
    case review(chosen: Int?)
}

struct QuestionView: View {
    let question: Question
    let mode: AnswerMode
    var onChoose: (Int) -> Void = { _ in }

    @AppStorage("showEnglish") private var showEnglish = false
    @Environment(Store.self) private var store
    @State private var zoomImage = false

    private var isRevealed: Bool {
        switch mode {
        case .practice(let c): c != nil
        case .exam: false
        case .review: true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 6) {
                Text(question.question)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if showEnglish {
                    Text(question.en.question)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }

            if let image = question.uiImage {
                Button { zoomImage = true } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 280)
                        .padding(10)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Bild vergrößern")
                if let credit = question.credit {
                    Text(credit).font(.caption2).foregroundStyle(.tertiary)
                }
            } else if question.image != nil {
                // Press photos are not stored in the repo; tools/fetch_photos.sh recreates them.
                Label("Bild fehlt. Vor dem Build tools/fetch_photos.sh ausführen.", systemImage: "photo")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(spacing: 10) {
                ForEach(question.answers.indices, id: \.self) { i in
                    AnswerRow(
                        text: question.answers[i],
                        english: showEnglish ? question.en.answers[i] : nil,
                        state: state(for: i),
                        action: { onChoose(i) }
                    )
                    .disabled(isLocked)
                }
            }

            if isRevealed, !question.en.explanation.isEmpty {
                ExplanationView(text: question.en.explanation)
            }
        }
        .animation(.easeOut(duration: 0.18), value: showEnglish)
        .sheet(isPresented: $zoomImage) { ImageZoomView(question: question) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(question.label).monospacedDigit()
            Text("·")
            Text(question.topic).lineLimit(1)
            Spacer(minLength: 8)
            Button {
                showEnglish.toggle()
            } label: {
                Text("EN")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 26)
                    .foregroundStyle(showEnglish ? Color.white : Color.ink)
                    .background(showEnglish ? Color.ink : Color.ink.opacity(0.12), in: Capsule())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showEnglish ? "Englische Übersetzung ausblenden" : "Englische Übersetzung zeigen")

            let marked = store.progress(for: question.id).bookmarked
            Button {
                store.toggleBookmark(question.id)
                Haptics.tap()
            } label: {
                Image(systemName: marked ? "bookmark.fill" : "bookmark")
                    .font(.body)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ink)
            .accessibilityLabel(marked ? "Markierung entfernen" : "Frage markieren")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.vertical, -10)
    }

    private var isLocked: Bool {
        switch mode {
        case .practice(let c): c != nil
        case .exam: false
        case .review: true
        }
    }

    private func state(for i: Int) -> AnswerRow.RowState {
        switch mode {
        case .exam(let chosen):
            return chosen == i ? .selected : .idle
        case .practice(let chosen):
            guard let chosen else { return .idle }
            if i == question.correct { return .correct }
            return i == chosen ? .wrong : .dimmed
        case .review(let chosen):
            if i == question.correct { return .correct }
            return i == chosen ? .wrong : .dimmed
        }
    }
}

struct AnswerRow: View {
    enum RowState { case idle, selected, correct, wrong, dimmed }

    let text: String
    let english: String?
    let state: RowState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(symbolColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let english {
                        Text(english)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(stroke, lineWidth: state == .idle || state == .dimmed ? 0 : 1)
            }
            .opacity(state == .dimmed ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .animation(.easeOut(duration: 0.18), value: state)
        .accessibilityLabel(text)
        .accessibilityValue(accessibilityState)
    }

    private var symbol: String {
        switch state {
        case .idle, .dimmed: "circle"
        case .selected: "largecircle.fill.circle"
        case .correct: "checkmark.circle.fill"
        case .wrong: "xmark.circle.fill"
        }
    }

    private var symbolColor: Color {
        switch state {
        case .idle, .dimmed: Color(uiColor: .tertiaryLabel)
        case .selected: .ink
        case .correct: .green
        case .wrong: .red
        }
    }

    private var fill: Color {
        switch state {
        case .idle, .dimmed: Color(uiColor: .secondarySystemGroupedBackground)
        case .selected: Color.ink.opacity(0.12)
        case .correct: Color.green.opacity(0.14)
        case .wrong: Color.red.opacity(0.14)
        }
    }

    private var stroke: Color {
        switch state {
        case .selected: .ink
        case .correct: .green
        case .wrong: .red
        default: .clear
        }
    }

    private var accessibilityState: String {
        switch state {
        case .selected: "ausgewählt"
        case .correct: "richtige Antwort"
        case .wrong: "falsch"
        default: ""
        }
    }
}

struct ExplanationView: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Label("Why? (English)", systemImage: "lightbulb")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ink)

            if expanded {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ImageZoomView: View {
    let question: Question
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                if let image = question.uiImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 360 * scale)
                        .padding()
                        .background(Color.white)
                }
            }
            .gesture(MagnifyGesture().onChanged { scale = min(max($0.magnification, 1), 4) })
            .navigationTitle(question.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
