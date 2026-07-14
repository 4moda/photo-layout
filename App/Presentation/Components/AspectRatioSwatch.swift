import SwiftUI

/// アスペクト比を正方形の枠内に縮尺表示するプレビュー。`aspect: nil` は元画像の比率（形を問わない）を表す。
/// 枠比率シート（`PageEditorView`）・俯瞰の比率メニュー（`PageOverviewView`）・
/// 新規作成の用紙サイズメニュー（`ProjectListView`）の3箇所で同一実装として共有する。
struct AspectRatioSwatch: View {
    let aspect: Double?
    /// 可視化された枠の中央に表示するラベル（比率文字列など）。nilなら枠のみ
    var centerLabel: String?

    var body: some View {
        GeometryReader { g in
            let ratio = CGFloat(max(aspect ?? 1, 0.01))
            let maxWidth = g.size.width * 0.78
            let maxHeight = g.size.height * 0.78
            let fittedWidth = min(maxWidth, maxHeight * ratio)
            let fittedHeight = fittedWidth / ratio

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(.systemGray4), lineWidth: 0.5)

                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.accentColor, lineWidth: 1)
                    )
                    .overlay {
                        if let centerLabel {
                            Text(centerLabel)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .padding(.horizontal, 2)
                        }
                    }
                    .frame(width: fittedWidth, height: fittedHeight)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
