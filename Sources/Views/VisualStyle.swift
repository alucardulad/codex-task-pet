import SwiftUI

enum PetPalette {
    static let mint = Color(red: 0.42, green: 1.0, blue: 0.74)
    static let mintDeep = Color(red: 0.08, green: 0.58, blue: 0.40)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.24)
    static let red = Color(red: 1.0, green: 0.37, blue: 0.38)
    static let ink = Color(red: 0.045, green: 0.075, blue: 0.085)
    static let panel = Color(red: 0.055, green: 0.075, blue: 0.08)
    static let panelRaised = Color(red: 0.085, green: 0.115, blue: 0.12)
    static let text = Color(red: 0.93, green: 0.97, blue: 0.96)
    static let secondaryText = Color(red: 0.62, green: 0.71, blue: 0.70)
}

struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct PanelBackground: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PetPalette.panel.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.20), PetPalette.mint.opacity(0.12), Color.white.opacity(0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 18, y: 10)
            )
    }
}

extension View {
    func petPanel(cornerRadius: CGFloat = 22) -> some View {
        modifier(PanelBackground(cornerRadius: cornerRadius))
    }
}
