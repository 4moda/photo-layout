/// X（旧Twitter）タイムラインの組写真表示を1枚のキャンバスに再現するスロット表。
/// エディタはこの配置で全ページを1画面に並べ、ユーザーは「実際にタイムラインでどう見えるか」を
/// 見ながら各スロット（＝各ページ）のクロップを調整する。
///
/// スロット順はXの表示順＝ページindex順:
/// 2枚=左・右 / 3枚=左大・右上・右下 / 4枚=左上・右上・左下・右下
public enum XTimelineComposite {
    /// 合成キャンバス全体のアスペクト比（1枚は単独表示なのでページと同じ）
    public static func canvasAspect(photoCount: Int) -> AspectRatio {
        photoCount <= 1
            ? PlatformSpecTable.xPageAspects(photoCount: 1)[0]
            : AspectRatio(width: 16, height: 9)
    }

    /// 各ページが占めるスロット矩形（合成キャンバスの正規化0..1座標、ページindex順）。
    /// - Parameter gutter: スロット間隙間（キャンバス幅に対する比率。縦方向は同じ実寸になるよう換算）
    public static func slots(photoCount: Int, gutter: Double = 0.008) -> [LayoutRect] {
        let aspect = canvasAspect(photoCount: photoCount)
        let gx = gutter
        let gy = gutter * aspect.ratio // 正方形の隙間になるよう縦横で実寸を揃える
        let halfW = (1 - gx) / 2
        let halfH = (1 - gy) / 2
        let rightX = (1 + gx) / 2
        let bottomY = (1 + gy) / 2

        switch photoCount {
        case ...1:
            return [.unit]
        case 2:
            return [
                LayoutRect(x: 0, y: 0, width: halfW, height: 1),
                LayoutRect(x: rightX, y: 0, width: halfW, height: 1)
            ]
        case 3:
            return [
                LayoutRect(x: 0, y: 0, width: halfW, height: 1),
                LayoutRect(x: rightX, y: 0, width: halfW, height: halfH),
                LayoutRect(x: rightX, y: bottomY, width: halfW, height: halfH)
            ]
        default:
            return [
                LayoutRect(x: 0, y: 0, width: halfW, height: halfH),
                LayoutRect(x: rightX, y: 0, width: halfW, height: halfH),
                LayoutRect(x: 0, y: bottomY, width: halfW, height: halfH),
                LayoutRect(x: rightX, y: bottomY, width: halfW, height: halfH)
            ]
        }
    }
}
