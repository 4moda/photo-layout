import Foundation

/// ページ1枚分の描画計画を生成する純粋関数。
/// プレビュー（画面pt）にも書き出し（実px）にも同じ関数を使うこと（CLAUDE.md ルール5）。
/// 比率(0..1)で保持されている余白・枠太さ・角丸をpx化するのはここだけ（ルール4）。
public enum RenderPlanBuilder {
    /// - Parameters:
    ///   - page: 対象ページ
    ///   - placements: このページに属する配置（destRectは配置領域の正規化0..1座標）
    ///   - defaultFrame: placement.frameOverrideがnilのときに使うフレーム
    ///   - pagePixelSize: 出力先のピクセル（またはポイント）サイズ。ページのアスペクト比と一致している前提
    public static func build(
        page: PageEntity,
        placements: [PlacementEntity],
        defaultFrame: PhotoFrameStyle,
        pagePixelSize: LayoutSize
    ) -> [DrawCommand] {
        let ref = pagePixelSize.referenceDimension
        let pageRect = LayoutRect(x: 0, y: 0, width: pagePixelSize.width, height: pagePixelSize.height)

        var commands: [DrawCommand] = [
            .fillRect(color: page.background.color, rect: pageRect)
        ]

        // 余白を差し引いた配置領域（px）。ジェスチャ層と同じ計算を共有する
        let contentRect = PageGeometry.contentRect(page: page, pageSize: pagePixelSize)
        guard contentRect.width > 0, contentRect.height > 0 else { return commands }

        for placement in placements.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            let frame = placement.frameOverride ?? defaultFrame
            let cornerRadiusPx = frame.cornerRadiusRatio * ref
            let borderWidthPx = frame.borderWidthRatio * ref

            // destRect（配置領域の正規化座標）→ 写真の表示矩形（px）。配置領域からはみ出しうる
            let imageRect = PageGeometry.imageRect(destRect: placement.destRect, in: contentRect)
            guard imageRect.width > 0, imageRect.height > 0 else { continue }

            // 不変条件（destRectのpxアスペクト==cropのpxアスペクト）は配置ヘルパが維持するが、
            // 浮動小数の揺れや不整合データに備えて防御的に正規化する（画像が歪んで描かれることはない）
            let sourceRect = CropMath.subCrop(
                placement.cropRect,
                photo: placement.photo,
                targetPixelAspect: imageRect.aspectRatio
            )

            // はみ出した写真は配置領域内の見える部分だけ描く。
            // 描画矩形を切ると同時にsourceRectも同比率で切ることで、拡縮・平行移動が
            // そのままクロップ調整として振る舞う（プレビューと書き出しで同一の計算）
            let visibleRect = imageRect.intersection(contentRect)
            guard visibleRect.width > 0, visibleRect.height > 0 else { continue }
            let visibleSource = LayoutRect(
                x: sourceRect.x + (visibleRect.x - imageRect.x) / imageRect.width * sourceRect.width,
                y: sourceRect.y + (visibleRect.y - imageRect.y) / imageRect.height * sourceRect.height,
                width: visibleRect.width / imageRect.width * sourceRect.width,
                height: visibleRect.height / imageRect.height * sourceRect.height
            )

            commands.append(.drawImage(
                placementID: placement.id,
                photo: placement.photo,
                sourceRect: visibleSource,
                destRect: visibleRect,
                cornerRadiusPx: cornerRadiusPx
            ))

            if borderWidthPx > 0, frame.borderColor.alpha > 0 {
                // 線は中心線基準で描かれるため、写真の内側に収まるよう半分だけinsetする
                let inset = borderWidthPx / 2
                commands.append(.strokeBorder(
                    color: frame.borderColor,
                    lineWidthPx: borderWidthPx,
                    cornerRadiusPx: max(0, cornerRadiusPx - inset),
                    rect: LayoutRect(
                        x: visibleRect.x + inset,
                        y: visibleRect.y + inset,
                        width: visibleRect.width - borderWidthPx,
                        height: visibleRect.height - borderWidthPx
                    )
                ))
            }
        }
        return commands
    }
}
