import SwiftUI
import PhotoLayoutCore

/// フェーズ0の仮ルート画面。Coreパッケージとのリンクが機能していることを画面上で示す。
struct RootView: View {
    private let igPortrait = AspectRatio(width: 4, height: 5)

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("PhotoLayout")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("root.title")
            Text("Core linked: 4:5 ratio = \(igPortrait.ratio, format: .number.precision(.fractionLength(2)))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("root.coreCheck")
        }
        .padding()
    }
}

#Preview {
    RootView()
}
