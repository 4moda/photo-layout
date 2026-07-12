import SwiftUI

extension View {
    /// 選択中バッジ（アクセントカラーの強調枠＋チェックマーク）。
    /// 枠比率／枠（縁）／テンプレート／S03比率／S03背景色の5つの選択UIで共通の見た目に使う。
    @ViewBuilder
    func selectionHighlight<S: InsettableShape>(_ isSelected: Bool, in shape: S) -> some View {
        overlay { if isSelected { shape.strokeBorder(Color.accentColor, lineWidth: 2.5) } }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.accentColor)
                        .background(Circle().fill(Color.white))
                        .offset(x: 5, y: -5)
                }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
