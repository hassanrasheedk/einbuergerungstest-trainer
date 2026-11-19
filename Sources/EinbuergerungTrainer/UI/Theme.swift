import SwiftUI
import UIKit

extension Color {
    /// Königsblau school ink. One tint, interactive elements only.
    static let ink = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x4F / 255, green: 0x72 / 255, blue: 0xF0 / 255, alpha: 1)
            : UIColor(red: 0x23 / 255, green: 0x48 / 255, blue: 0xC9 / 255, alpha: 1)
    })

    static func mastery(_ m: Mastery) -> Color {
        switch m {
        case .solid: .green
        case .learning: .ink
        case .shaky: .orange
        case .new: Color(uiColor: .tertiarySystemFill)
        }
    }
}

@MainActor
enum Haptics {
    static func answer(correct: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(correct ? .success : .error)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// Subtle press feedback for any tappable surface.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Full-width primary action pinned above the home indicator.
struct PrimaryActionBar<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

/// One capsule across a set of questions, segmented by mastery.
struct MasteryBar: View {
    let counts: [Mastery: Int]
    var height: CGFloat = 10

    private var total: Int { counts.values.reduce(0, +) }
    private let order: [Mastery] = [.solid, .learning, .shaky, .new]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(order, id: \.self) { m in
                    let n = counts[m] ?? 0
                    if n > 0 {
                        Rectangle()
                            .fill(Color.mastery(m))
                            .frame(width: max(2, (geo.size.width - 6) * CGFloat(n) / CGFloat(max(total, 1))))
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel(order.map { "\(counts[$0] ?? 0) \($0.title)" }.joined(separator: ", "))
    }
}

struct MasteryLegend: View {
    let counts: [Mastery: Int]

    var body: some View {
        HStack(spacing: 14) {
            ForEach([Mastery.solid, .learning, .shaky, .new], id: \.self) { m in
                HStack(spacing: 5) {
                    Circle().fill(Color.mastery(m)).frame(width: 8, height: 8)
                    Text("\(counts[m] ?? 0) \(m.title)")
                        .monospacedDigit()
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

extension Store {
    func masteryCounts(_ questions: [Question] = Catalog.all) -> [Mastery: Int] {
        var result: [Mastery: Int] = [:]
        for q in questions { result[mastery(of: q.id), default: 0] += 1 }
        return result
    }
}

/// "12 Min 05 Sek", German regardless of device language.
func minutesText(_ t: TimeInterval) -> String {
    let total = Int(t.rounded())
    let m = total / 60, s = total % 60
    return m == 0 ? "\(s) Sek" : String(format: "%d Min %02d Sek", m, s)
}
