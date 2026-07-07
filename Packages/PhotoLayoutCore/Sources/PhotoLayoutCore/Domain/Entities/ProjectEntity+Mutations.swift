import Foundation

/// 画面操作に対応するエンティティ変更ヘルパ。ロジックはCoreに置き、ViewModelは呼ぶだけにする。
extension ProjectEntity {
    /// 写真を追加する。フェーズ2では単写真前提でページ全面（destRect=unit）に配置する。
    public mutating func addPhoto(_ photo: PhotoRef) {
        let placement = PlacementEntity(
            sortIndex: placements.count,
            photo: photo,
            destRect: .unit
        )
        placements.append(placement)
    }

    /// 全ページのアスペクト比を変更する（フェーズ2は単ページ）。
    public mutating func setPageAspect(_ aspect: AspectRatio) {
        for index in pages.indices {
            pages[index].aspect = aspect
        }
    }

    /// 全placementのfill/fitを切り替える。
    public mutating func setContentMode(_ mode: ContentMode) {
        for index in placements.indices {
            placements[index].contentMode = mode
        }
    }

    /// FramePresetを背景・デフォルトフレームへ適用する（個別上書きはクリア）。
    public mutating func applyFramePreset(_ preset: FramePreset) {
        defaultPhotoFrame = preset.photoFrame
        for index in pages.indices {
            pages[index].background = preset.background
        }
        for index in placements.indices {
            placements[index].frameOverride = nil
        }
    }
}
