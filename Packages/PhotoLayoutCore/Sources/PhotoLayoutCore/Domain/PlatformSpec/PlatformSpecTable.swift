/// X / Instagram の表示仕様を集約した定数テーブル。
/// プラットフォーム側の仕様変更・諸説はこのテーブルの更新だけで吸収する（コードに散らさない）。
public enum PlatformSpecTable {
    /// Xの枚数別タイムライン表示アスペクト（2026-07時点のユーザー実測値）。
    /// - 1枚: 3:4（縦長。横長/1:1も可だが既定は3:4）
    /// - 2枚: 8:9 × 2（左右並び）
    /// - 3枚: 8:9（左大）+ 16:9 × 2（右上下）
    /// - 4枚: 16:9 × 4（2×2）
    public static func xPageAspects(photoCount: Int) -> [AspectRatio] {
        switch photoCount {
        case 1: return [AspectRatio(width: 3, height: 4)]
        case 2: return Array(repeating: AspectRatio(width: 8, height: 9), count: 2)
        case 3: return [AspectRatio(width: 8, height: 9),
                        AspectRatio(width: 16, height: 9),
                        AspectRatio(width: 16, height: 9)]
        case 4: return Array(repeating: AspectRatio(width: 16, height: 9), count: 4)
        default: return []
        }
    }

    public static let xMaxPhotoCount = 4

    public static func instagramAspect(_ aspect: InstagramAspect) -> AspectRatio {
        switch aspect {
        case .square: return AspectRatio(width: 1, height: 1)
        case .portrait: return AspectRatio(width: 4, height: 5)
        case .landscape: return AspectRatio(width: 1.91, height: 1)
        }
    }

    public static let instagramMaxPageCount = 20

    /// プリセットに対応するページアスペクト列を返す。
    public static func pageAspects(for preset: PlatformPreset) -> [AspectRatio] {
        switch preset {
        case .x(let count):
            return xPageAspects(photoCount: count)
        case .instagram(let aspect, let pageCount):
            let clamped = max(1, min(pageCount, instagramMaxPageCount))
            return Array(repeating: instagramAspect(aspect), count: clamped)
        }
    }
}
