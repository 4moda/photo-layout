/// ワンタップで適用できる枠/背景の組み合わせプリセット。
/// 適用は「この数値をスタイルに代入する」だけなので、適用後の微調整に制約はない。
public enum FramePreset: String, Codable, Hashable, Sendable, CaseIterable {
    case none
    case whiteMargin
    case thinBlackBorder
    case whiteMarginBlackBorder
    case blackBackgroundWhiteBorder

    public var photoFrame: PhotoFrameStyle {
        switch self {
        case .none, .whiteMargin:
            return .none
        case .thinBlackBorder, .whiteMarginBlackBorder:
            return PhotoFrameStyle(borderColor: .black, borderWidthRatio: 0.004, cornerRadiusRatio: 0)
        case .blackBackgroundWhiteBorder:
            return PhotoFrameStyle(borderColor: .white, borderWidthRatio: 0.008, cornerRadiusRatio: 0)
        }
    }

    public var background: CanvasBackgroundStyle {
        switch self {
        case .none, .thinBlackBorder:
            return CanvasBackgroundStyle(color: .white, margins: .zero)
        case .whiteMargin, .whiteMarginBlackBorder:
            return CanvasBackgroundStyle(color: .white, margins: EdgeInsetsRatio(uniform: 0.05))
        case .blackBackgroundWhiteBorder:
            return CanvasBackgroundStyle(color: .black, margins: EdgeInsetsRatio(uniform: 0.05))
        }
    }
}
