import Foundation

/// ページ1枚分の描画計画を生成する純粋関数。
/// プレビュー（画面pt）にも書き出し（実px）にも同じ関数を使うこと（CLAUDE.md ルール5）。
/// 比率(0..1)で保持されている余白・枠太さ・角丸をpx化するのはここだけ（ルール4）。
public enum RenderPlanBuilder {
    /// - Parameters:
    ///   - page: 対象ページ
    ///   - placements: このページに属する配置（destRectはページ正規化0..1座標）
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

        // 余白を差し引いた配置領域（px）
        let margins = page.background.margins
        let contentRect = LayoutRect(
            x: margins.leading * ref,
            y: margins.top * ref,
            width: max(0, pagePixelSize.width - (margins.leading + margins.trailing) * ref),
            height: max(0, pagePixelSize.height - (margins.top + margins.bottom) * ref)
        )
        guard contentRect.width > 0, contentRect.height > 0 else { return commands }

        for placement in placements.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            let frame = placement.frameOverride ?? defaultFrame
            let cornerRadiusPx = frame.cornerRadiusRatio * ref
            let borderWidthPx = frame.borderWidthRatio * ref

            // destRect（ページ正規化）→ 配置セル（px）
            let cell = LayoutRect(
                x: contentRect.x + placement.destRect.x * contentRect.width,
                y: contentRect.y + placement.destRect.y * contentRect.height,
                width: placement.destRect.width * contentRect.width,
                height: placement.destRect.height * contentRect.height
            )

            // クロップ領域の実ピクセルアスペクト
            let cropPxW = placement.cropRect.width * Double(placement.photo.pixelWidth)
            let cropPxH = placement.cropRect.height * Double(placement.photo.pixelHeight)
            guard cropPxW > 0, cropPxH > 0 else { continue }
            let cropAspect = cropPxW / cropPxH

            let sourceRect: LayoutRect
            let imageRect: LayoutRect
            switch placement.contentMode {
            case .fill:
                // セルのアスペクトに合わせてクロップ矩形を中央でさらに絞り込み、
                // レンダラ側のクリッピングを不要にする
                sourceRect = subCrop(placement.cropRect, sourceAspect: cropAspect, targetAspect: cell.aspectRatio)
                imageRect = cell
            case .fit:
                // クロップ全体を見せ、セル内に収める（マット仕上げ）
                sourceRect = placement.cropRect
                imageRect = cell.fitting(AspectRatio(width: cropPxW, height: cropPxH))
            }

            commands.append(.drawImage(
                placementID: placement.id,
                photo: placement.photo,
                sourceRect: sourceRect,
                destRect: imageRect,
                cornerRadiusPx: cornerRadiusPx
            ))

            if borderWidthPx > 0, frame.borderColor.alpha > 0 {
                // 線は中心線基準で描かれるため、画像の内側に収まるよう半分だけinsetする
                let inset = borderWidthPx / 2
                commands.append(.strokeBorder(
                    color: frame.borderColor,
                    lineWidthPx: borderWidthPx,
                    cornerRadiusPx: max(0, cornerRadiusPx - inset),
                    rect: LayoutRect(
                        x: imageRect.x + inset,
                        y: imageRect.y + inset,
                        width: imageRect.width - borderWidthPx,
                        height: imageRect.height - borderWidthPx
                    )
                ))
            }
        }
        return commands
    }

    /// cropRect（元画像正規化）を、実ピクセルアスペクトがtargetAspectになるよう中央で絞り込む。
    private static func subCrop(_ crop: LayoutRect, sourceAspect: Double, targetAspect: Double) -> LayoutRect {
        if sourceAspect > targetAspect {
            // 横に余る → 幅を削る
            let scale = targetAspect / sourceAspect
            let newWidth = crop.width * scale
            return LayoutRect(x: crop.midX - newWidth / 2, y: crop.y, width: newWidth, height: crop.height)
        } else if sourceAspect < targetAspect {
            let scale = sourceAspect / targetAspect
            let newHeight = crop.height * scale
            return LayoutRect(x: crop.x, y: crop.midY - newHeight / 2, width: crop.width, height: newHeight)
        }
        return crop
    }
}
