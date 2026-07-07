import Foundation

/// 画面操作に対応するエンティティ変更ヘルパ。ロジックはCoreに置き、ViewModelは呼ぶだけにする。
///
/// 配置の不変条件「destRectのピクセルアスペクト == cropRectのピクセルアスペクト」は
/// ここで維持する。fill/fitのような永続モードは存在せず、すべてジオメトリで表現する。
extension ProjectEntity {
    /// 写真を追加する。既定は全面配置（ページの配置領域いっぱいに敷く）。
    public mutating func addPhoto(_ photo: PhotoRef) {
        let placement = PlacementEntity(
            sortIndex: placements.count,
            photo: photo,
            destRect: .unit
        )
        placements.append(placement)
        placeFillingPage(placementID: placement.id)
    }

    /// 全面配置: クロップを配置領域のアスペクトに絞り込み、領域いっぱいに敷く。
    public mutating func placeFillingPage(placementID: UUID) {
        guard let page = orderedPages.first,
              let index = placements.firstIndex(where: { $0.id == placementID }) else { return }
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
        guard let page = orderedPages.first,
              let index = placements.firstIndex(where: { $0.id == placementID }) else { return }
        let photo = placements[index].photo
        placements[index].cropRect = .unit
        // destRectは配置領域の正規化座標なので、ピクセルアスペクトを正規化アスペクトへ変換して収める
        let normalizedAspect = photo.aspectRatio.ratio / page.contentAspect
        placements[index].destRect = LayoutRect.unit
            .fitting(AspectRatio(width: normalizedAspect, height: 1))
            .scaled(by: coverage)
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
