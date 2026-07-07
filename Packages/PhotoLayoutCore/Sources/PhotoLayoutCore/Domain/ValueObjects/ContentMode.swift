/// 写真をセルへどう収めるか。クロップと枠付けの対になる本質的トレードオフ。
public enum ContentMode: String, Codable, Hashable, Sendable, CaseIterable {
    /// 切ってはめる。cropRectで指定された領域がセルを完全に覆う
    case fill
    /// 余白で収める（マット仕上げ）。写真全体が見え、余白は背景色で埋まる
    case fit
}
