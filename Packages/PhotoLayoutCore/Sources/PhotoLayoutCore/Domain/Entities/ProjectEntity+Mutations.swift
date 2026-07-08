import Foundation

/// 画面操作に対応するエンティティ変更ヘルパ。ロジックはCoreに置き、ViewModelは呼ぶだけにする。
///
/// 配置の不変条件「destRectのピクセルアスペクト == cropRectのピクセルアスペクト」は
/// ここで維持する。fill/fitのような永続モードは存在せず、すべてジオメトリで表現する。
extension ProjectEntity {
    /// 写真を追加する。既定は全面配置（ページの配置領域いっぱいに敷く）。
    public mutating func addPhoto(_ photo: PhotoRef, toPage pageIndex: Int = 0) {
        let placement = PlacementEntity(
            sortIndex: placements.count,
            pageIndex: pageIndex,
            photo: photo,
            destRect: .unit
        )
        placements.append(placement)
        placeFillingPage(placementID: placement.id)
    }

    /// 配置（写真）を削除し、sortIndexを0からの連番に詰め直す。
    public mutating func removePlacement(id: UUID) {
        guard placements.contains(where: { $0.id == id }) else { return }
        placements.removeAll { $0.id == id }
        let orderedIDs = orderedPlacements.map(\.id)
        for (newIndex, placementID) in orderedIDs.enumerated() {
            if let index = placements.firstIndex(where: { $0.id == placementID }) {
                placements[index].sortIndex = newIndex
            }
        }
    }

    /// 重なり順: 同一ページ内で1段前面へ（sortIndexを隣と入替）。最前面なら何もしない
    public mutating func bringForward(placementID: UUID) {
        guard let placement = placements.first(where: { $0.id == placementID }) else { return }
        let samePage = placements(onPage: placement.pageIndex)
        guard let position = samePage.firstIndex(where: { $0.id == placementID }),
              position + 1 < samePage.count else { return }
        swapSortIndex(placementID, samePage[position + 1].id)
    }

    /// 重なり順: 同一ページ内で1段背面へ。最背面なら何もしない
    public mutating func sendBackward(placementID: UUID) {
        guard let placement = placements.first(where: { $0.id == placementID }) else { return }
        let samePage = placements(onPage: placement.pageIndex)
        guard let position = samePage.firstIndex(where: { $0.id == placementID }),
              position > 0 else { return }
        swapSortIndex(placementID, samePage[position - 1].id)
    }

    private mutating func swapSortIndex(_ a: UUID, _ b: UUID) {
        guard let indexA = placements.firstIndex(where: { $0.id == a }),
              let indexB = placements.firstIndex(where: { $0.id == b }) else { return }
        let temp = placements[indexA].sortIndex
        placements[indexA].sortIndex = placements[indexB].sortIndex
        placements[indexB].sortIndex = temp
    }

    /// 全面配置: クロップを配置領域のアスペクトに絞り込み、領域いっぱいに敷く。
    public mutating func placeFillingPage(placementID: UUID) {
        guard let index = placements.firstIndex(where: { $0.id == placementID }),
              let page = page(at: placements[index].pageIndex) else { return }
        placements[index].cropRect = CropMath.subCrop(
            .unit,
            photo: placements[index].photo,
            targetPixelAspect: page.contentAspect
        )
        placements[index].destRect = .unit
    }

    /// マット配置: 写真全体を見せ、余白を残して中央に置く。
    /// - Parameter coverage: 配置領域に対する写真の占有率（0..1）
    public mutating func placeMatted(placementID: UUID, coverage: Double = 0.9) {
        guard let index = placements.firstIndex(where: { $0.id == placementID }),
              let page = page(at: placements[index].pageIndex) else { return }
        let photo = placements[index].photo
        placements[index].cropRect = .unit
        // destRectは配置領域の正規化座標なので、ピクセルアスペクトを正規化アスペクトへ変換して収める
        let normalizedAspect = photo.aspectRatio.ratio / page.contentAspect
        placements[index].destRect = LayoutRect.unit
            .fitting(AspectRatio(width: normalizedAspect, height: 1))
            .scaled(by: coverage)
    }

    /// 枠（destRect）の変更を適用し、pxアスペクトの変化に合わせてcropRectを再計算する。
    /// 画像は決して歪まない — 枠の中で見せる範囲（クロップ窓）が変わるだけ。
    /// - Parameter baseCrop: 再クロップの基準（ジェスチャ開始時のcropRect。ドラッグ中に
    ///   毎フレーム現在値から絞ると単調に狭まってしまうため、基準を固定して渡す）
    public mutating func resizeFrame(placementID: UUID, to rect: LayoutRect, recroppingFrom baseCrop: LayoutRect) {
        guard let index = placements.firstIndex(where: { $0.id == placementID }),
              let page = page(at: placements[index].pageIndex),
              rect.width > 0, rect.height > 0 else { return }
        placements[index].destRect = rect
        // destRect（配置領域の正規化座標）の実ピクセルアスペクト
        let targetPixelAspect = rect.aspectRatio * page.contentAspect
        placements[index].cropRect = CropMath.subCrop(
            baseCrop,
            photo: placements[index].photo,
            targetPixelAspect: targetPixelAspect
        )
    }

    /// 枠のpxアスペクトを指定値に変更する（中心・幅は維持、高さで調整）。
    /// クロップは元画像全体から中央で取り直す。
    public mutating func setFramePixelAspect(_ pixelAspect: Double, placementID: UUID) {
        guard let index = placements.firstIndex(where: { $0.id == placementID }),
              let page = page(at: placements[index].pageIndex),
              pixelAspect > 0 else { return }
        let dest = placements[index].destRect
        let normalizedAspect = pixelAspect / page.contentAspect
        let height = dest.width / normalizedAspect
        let rect = LayoutRect(
            x: dest.midX - dest.width / 2,
            y: dest.midY - height / 2,
            width: dest.width,
            height: height
        )
        resizeFrame(placementID: placementID, to: rect, recroppingFrom: .unit)
    }

    public mutating func placeAllFillingPage() {
        for placement in placements { placeFillingPage(placementID: placement.id) }
    }

    public mutating func placeAllMatted(coverage: Double = 0.9) {
        for placement in placements { placeMatted(placementID: placement.id, coverage: coverage) }
    }

    /// 全ページのアスペクト比を変更し、既存配置を新しい配置領域に合わせて再配置する。
    public mutating func setPageAspect(_ aspect: AspectRatio) {
        for index in pages.indices {
            pages[index].aspect = aspect
        }
        replaceAllPlacements()
    }

    /// FramePresetを背景・デフォルトフレームへ適用する（個別上書きはクリア）。
    /// 余白が変わると配置領域のアスペクトも変わるため再配置する。
    public mutating func applyFramePreset(_ preset: FramePreset) {
        defaultPhotoFrame = preset.photoFrame
        for index in pages.indices {
            pages[index].background = preset.background
        }
        for index in placements.indices {
            placements[index].frameOverride = nil
        }
        replaceAllPlacements()
    }

    /// 現在の配置意図を保ったまま再配置する:
    /// 全面（destRect≒unit）は全面のまま、それ以外はマットとして現在の占有率を概ね維持する。
    private mutating func replaceAllPlacements() {
        for placement in placements {
            if placement.destRect.isApproximatelyEqual(to: .unit) {
                placeFillingPage(placementID: placement.id)
            } else {
                let coverage = max(placement.destRect.width, placement.destRect.height)
                placeMatted(placementID: placement.id, coverage: min(coverage, 1.0))
            }
        }
    }
}
