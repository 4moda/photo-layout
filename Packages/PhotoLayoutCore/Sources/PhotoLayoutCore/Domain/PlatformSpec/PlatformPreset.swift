/// 投稿先プラットフォームのプリセット。ページ構成の初期値を決める。
public enum PlatformPreset: Codable, Hashable, Sendable {
    /// X（旧Twitter）の1〜4枚投稿。枚数と位置でページアスペクトが決まる
    case x(photoCount: Int)
    /// Instagram単ページ or カルーセル。全ページ同一アスペクト
    case instagram(aspect: InstagramAspect, pageCount: Int)
}

/// Instagramで投稿可能なアスペクト比。
public enum InstagramAspect: String, Codable, Hashable, Sendable, CaseIterable {
    case square      // 1:1
    case portrait    // 4:5（縦長最大）
    case landscape   // 1.91:1（横長）
}
