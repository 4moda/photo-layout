/// スロット付きテンプレートフレーム。1ページ内に写真を当てはめる矩形（スロット）の定数定義。
/// 写真を落とすと各スロットへ全面配置相当で収まり、良い感じの余白・分割になる。
/// Xの組写真（2〜4枚）も「専用モード」ではなくこのテンプレートの一種として表現する。
public struct LayoutTemplate: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// スロット矩形（ページ配置領域の正規化0..1座標、表示順）
    public let slots: [LayoutRect]
    /// このテンプレートが想定するページの推奨アスペクト（適用時にページへ設定してよい）
    public let recommendedAspect: AspectRatio?

    public init(id: String, name: String, slots: [LayoutRect], recommendedAspect: AspectRatio? = nil) {
        self.id = id
        self.name = name
        self.slots = slots
        self.recommendedAspect = recommendedAspect
    }

    public var slotCount: Int { slots.count }
}

/// テンプレートの定数テーブル。枚数別に代表的なバリエーションを持つ。
public enum LayoutTemplateTable {
    /// マット無し全面（1枚）
    public static let single = LayoutTemplate(
        id: "single-full", name: "全面", slots: [.unit]
    )

    /// 中央マット（1枚・余白広め）
    public static func singleMatted(coverage: Double) -> LayoutTemplate {
        LayoutTemplate(
            id: "single-mat-\(Int(coverage * 100))",
            name: "中央マット\(Int(coverage * 100))%",
            slots: [LayoutRect.unit.scaled(by: coverage)]
        )
    }

    /// 2枚: 左右50:50 / 上下50:50 / 大小(黄金比)
    public static func twoUp(gutter: Double = 0.01) -> [LayoutTemplate] {
        let g = gutter
        let half = (1 - g) / 2
        return [
            LayoutTemplate(id: "two-lr", name: "左右2分割", slots: [
                LayoutRect(x: 0, y: 0, width: half, height: 1),
                LayoutRect(x: half + g, y: 0, width: half, height: 1)
            ]),
            LayoutTemplate(id: "two-tb", name: "上下2分割", slots: [
                LayoutRect(x: 0, y: 0, width: 1, height: half),
                LayoutRect(x: 0, y: half + g, width: 1, height: half)
            ])
        ]
    }

    /// 3枚: 左1大＋右2小 / 縦3列
    public static func threeUp(gutter: Double = 0.01) -> [LayoutTemplate] {
        let g = gutter
        let half = (1 - g) / 2
        let third = (1 - 2 * g) / 3
        return [
            LayoutTemplate(id: "three-left-big", name: "左大＋右2", slots: [
                LayoutRect(x: 0, y: 0, width: half, height: 1),
                LayoutRect(x: half + g, y: 0, width: half, height: half),
                LayoutRect(x: half + g, y: half + g, width: half, height: half)
            ]),
            LayoutTemplate(id: "three-strip", name: "縦3列", slots: [
                LayoutRect(x: 0, y: 0, width: third, height: 1),
                LayoutRect(x: third + g, y: 0, width: third, height: 1),
                LayoutRect(x: 2 * (third + g), y: 0, width: third, height: 1)
            ])
        ]
    }

    /// 4枚: 田の字 / 横4段
    public static func fourUp(gutter: Double = 0.01) -> [LayoutTemplate] {
        let g = gutter
        let half = (1 - g) / 2
        let quarter = (1 - 3 * g) / 4
        return [
            LayoutTemplate(id: "four-grid", name: "田の字", slots: [
                LayoutRect(x: 0, y: 0, width: half, height: half),
                LayoutRect(x: half + g, y: 0, width: half, height: half),
                LayoutRect(x: 0, y: half + g, width: half, height: half),
                LayoutRect(x: half + g, y: half + g, width: half, height: half)
            ]),
            LayoutTemplate(id: "four-rows", name: "横4段", slots: (0..<4).map { i in
                LayoutRect(x: 0, y: Double(i) * (quarter + g), width: 1, height: quarter)
            })
        ]
    }

    /// Xタイムライン合成（2〜4枚。スロットはXTimelineCompositeを流用）。
    /// 推奨ページアスペクトは16:9で、書き出しはスロット個別画像で行う。
    public static func xTimeline(photoCount: Int) -> LayoutTemplate {
        LayoutTemplate(
            id: "x-timeline-\(photoCount)",
            name: "X組写真\(photoCount)枚",
            slots: XTimelineComposite.slots(photoCount: photoCount),
            recommendedAspect: XTimelineComposite.canvasAspect(photoCount: photoCount)
        )
    }

    /// 枚数に対する代表テンプレート一覧（UIのピッカー用）
    public static func templates(forPhotoCount count: Int) -> [LayoutTemplate] {
        switch count {
        case ...1:
            return [single, singleMatted(coverage: 0.9), singleMatted(coverage: 0.8)]
        case 2:
            return twoUp() + [xTimeline(photoCount: 2)]
        case 3:
            return threeUp() + [xTimeline(photoCount: 3)]
        default:
            return fourUp() + [xTimeline(photoCount: 4)]
        }
    }
}
