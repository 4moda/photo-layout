import SwiftUI

/// デザイン刷新のタイポグラフィトークン。カスタムフォントは同梱しない
/// （Apple標準のsystem font design切り替えのみなので、ライセンス確認・アセット追加が不要）。
enum PLFont {
    /// 見出し・ワードマーク用の「刻印」書体（フィルム缶やコンタクトシートのスタンプ文字のイメージ）。
    /// 単体では大文字化・トラッキングを行わないため、見出しには`View.plStamp(size:weight:)`を使う
    static func stamp(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// 枚数・px・日付など、桁を揃えたい数値表示用（stampと同じ等幅書体）
    static func data(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// 本文・ボタン・ラベル用の書体
    static func body(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }
}

extension View {
    /// 見出し・ワードマークの「刻印」スタイル: 等幅＋大文字＋トラッキング。
    /// 本文中で多用するとうるさくなるため、画面タイトル・ワードマークなど限られた箇所にのみ使う
    func plStamp(size: CGFloat, weight: Font.Weight = .bold) -> some View {
        font(PLFont.stamp(size, weight: weight))
            .textCase(.uppercase)
            .tracking(size * 0.08)
    }
}
