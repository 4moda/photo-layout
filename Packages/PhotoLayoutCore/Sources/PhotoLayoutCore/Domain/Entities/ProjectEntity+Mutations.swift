import Foundation

/// 画面操作に対応するエンティティ変更ヘルパ。ロジックはCoreに置き、ViewModelは呼ぶだけにする。
///
/// 配置の不変条件「destRectのピクセルアスペクト == cropRectのピクセルアスペクト」は
/// ここで維持する。fill/fitのような永続モードは存在せず、すべてジオメトリで表現する。
extension ProjectEntity {
    /// 写真を追加する。既定は「元のアスペクト比のまま中央付近に配置」（クロップしない）。
    /// 同じページに複数追加すると完全には重ならないよう少しずつずらす（カスケード）。
    public mutating func addPhoto(_ photo: PhotoRef, toPage pageIndex: Int = 0) {
        let cascade = placements(onPage: pageIndex).count
        let placement = PlacementEntity(
            sortIndex: placements.count,
            pageIndex: pageIndex,
            photo: photo,
            destRect: .unit
        )
        placements.append(placement)
        placePhotoNatural(placementID: placement.id, cascadeIndex: cascade)
    }

    /// 元画像全体を歪めず、配置領域にフィットさせて中央付近へ置く（既定の追加配置）。
    /// - Parameter cascadeIndex: 同ページ内の何枚目か。1枚ごとに少しずらして重なりを避ける。
    public mutating func placePhotoNatural(placementID: UUID, cascadeIndex: Int = 0) {
        guard let index = placements.firstIndex(where: { $0.id == placementID }),
              let page = page(at: placements[index].pageIndex) else { return }
        let photo = placements[index].photo
        placements[index].cropRect = .unit // 元画像全体（クロップしない）
        let normalizedAspect = photo.aspectRatio.ratio / page.contentAspect
        let base = LayoutRect.unit
            .fitting(AspectRatio(width: normalizedAspect, height: 1))
            .scaled(by: 0.85)
        let shift = Double(cascadeIndex % 5) * 0.05
        placements[index].destRect = LayoutRect(
            x: base.x + shift, y: base.y + shift, width: base.width, height: base.height
        )
    }

    /// 配置（写真）を削除し、sortIndexを0からの連番に詰め直す。ロック中の写真は無視する。
    public mutating func removePlacement(id: UUID) {
        guard let placement = placements.first(where: { $0.id == id }), !placement.isLocked else { return }
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

    /// 重なり順: レイヤー順シートのドラッグ並べ替え。`.onMove` が渡す表示順（前面が先）の
    /// fromOffsets/toOffsetを重なり順（sortIndex、背面が先）に変換して反映し、
    /// 対象ページの配置のsortIndexを0からの連番に振り直す。
    public mutating func movePlacements(onPage pageIndex: Int, fromOffsets: IndexSet, toOffset: Int) {
        var frontFirstIDs = placements(onPage: pageIndex).reversed().map(\.id)
        frontFirstIDs.movingElements(fromOffsets: fromOffsets, toOffset: toOffset)
        for (newIndex, placementID) in frontFirstIDs.reversed().enumerated() {
            if let index = placements.firstIndex(where: { $0.id == placementID }) {
                placements[index].sortIndex = newIndex
            }
        }
    }

    /// テンプレート（スロット型枠）をページに敷く。スロット先行モデル:
    /// - ページに `slots` を保持させ、写真が無くても「空スロット」が存在できるようにする
    /// - 既存の写真は sortIndex 順にスロット0,1,2… へ当てはめ、スロット数を超えた分は外す
    /// - 写真が少なければ余ったスロットは空のまま（`assignPhoto` で後から充填する）
    /// - Parameter template: 適用するテンプレート（スロットはページ配置領域の正規化座標）
    public mutating func applyTemplate(_ template: LayoutTemplate, toPage pageIndex: Int) {
        guard let pageArrayIndex = pages.firstIndex(where: { $0.index == pageIndex }) else { return }
        pages[pageArrayIndex].slots = template.slots
        let page = pages[pageArrayIndex]
        let ordered = placements(onPage: pageIndex)
        for (offset, placement) in ordered.enumerated() {
            guard let index = placements.firstIndex(where: { $0.id == placement.id }) else { continue }
            if offset < template.slots.count {
                placements[index].slotIndex = offset
                fitPlacementToSlot(placementArrayIndex: index, slot: template.slots[offset], page: page)
            } else {
                // スロットからあふれた写真は外す
                placements.remove(at: index)
            }
        }
    }

    /// 空スロットに写真を1枚当てはめる（スロット比に中央クロップして全面配置）。
    /// 既にそのスロットに写真があれば置き換える。
    public mutating func assignPhoto(_ photo: PhotoRef, toPage pageIndex: Int, slot slotIndex: Int) {
        guard let page = page(at: pageIndex),
              let slots = page.slots, slots.indices.contains(slotIndex) else { return }
        placements.removeAll { $0.pageIndex == pageIndex && $0.slotIndex == slotIndex }
        let slot = slots[slotIndex]
        let slotPixelAspect = slot.aspectRatio * page.contentAspect
        placements.append(PlacementEntity(
            sortIndex: placements.count,
            pageIndex: pageIndex,
            slotIndex: slotIndex,
            photo: photo,
            cropRect: CropMath.subCrop(.unit, photo: photo, targetPixelAspect: slotPixelAspect),
            destRect: slot
        ))
    }

    /// ページの空スロット（写真が入っていないスロット）のindex一覧。
    public func emptySlotIndices(onPage pageIndex: Int) -> [Int] {
        guard let slots = page(at: pageIndex)?.slots else { return [] }
        let filled = Set(placements(onPage: pageIndex).compactMap { $0.slotIndex })
        return slots.indices.filter { !filled.contains($0) }
    }

    /// 1枚の写真をカルーセルの全スライドへシームレスに分割する（SCRL型）。
    /// ページを count 枚に作り直し、各スライドに元画像の i 番目の縦スライスを全面配置する。
    /// 各スライドは1スロットの型枠として保持する（空にすれば別写真を当てはめ可）。
    public mutating func splitPhoto(
        _ photo: PhotoRef,
        intoSlides count: Int,
        slideAspect: AspectRatio,
        background: CanvasBackgroundStyle = .plainWhite
    ) {
        let n = max(1, min(count, 20))
        pages = (0..<n).map { PageEntity(index: $0, aspect: slideAspect, background: background, slots: [.unit]) }
        // 余白込みの配置領域アスペクト × n が仮想キャンバスのアスペクト
        let slideContentAspect = pages[0].contentAspect
        let totalAspect = slideContentAspect * Double(n)
        let fillCrop = CropMath.subCrop(.unit, photo: photo, targetPixelAspect: totalAspect)
        let sliceWidth = fillCrop.width / Double(n)
        placements = (0..<n).map { i in
            let cropRect = LayoutRect(
                x: fillCrop.x + Double(i) * sliceWidth,
                y: fillCrop.y,
                width: sliceWidth,
                height: fillCrop.height
            )
            return PlacementEntity(
                sortIndex: i, pageIndex: i, slotIndex: 0,
                photo: photo, cropRect: cropRect, destRect: .unit
            )
        }
    }

    /// 配置をスロット矩形へ全面配置する（destRect=スロット、cropRectをスロット比へ中央クロップ）。
    private mutating func fitPlacementToSlot(placementArrayIndex index: Int, slot: LayoutRect, page: PageEntity) {
        placements[index].destRect = slot
        let slotPixelAspect = slot.aspectRatio * page.contentAspect
        placements[index].cropRect = CropMath.subCrop(
            .unit,
            photo: placements[index].photo,
            targetPixelAspect: slotPixelAspect
        )
    }

    /// スライドを複製し、直後に挿入する（写真・スタイルごとコピー）。「ページ選択」メニュー用。
    public mutating func duplicatePage(at pageIndex: Int) {
        guard let source = page(at: pageIndex) else { return }
        let newIndex = pageIndex + 1
        for i in pages.indices where pages[i].index >= newIndex { pages[i].index += 1 }
        for i in placements.indices where placements[i].pageIndex >= newIndex { placements[i].pageIndex += 1 }
        var newPage = source
        newPage.id = UUID()
        newPage.index = newIndex
        pages.append(newPage)
        var nextSort = (placements.map(\.sortIndex).max() ?? -1) + 1
        for original in placements(onPage: pageIndex) {
            var copy = original
            copy.id = UUID()
            copy.pageIndex = newIndex
            copy.sortIndex = nextSort
            nextSort += 1
            placements.append(copy)
        }
    }

    /// 指定スライドの背景/余白と枠プリセットを設定する（「ページ選択」メニュー用・そのページだけ）。
    public mutating func setPageStyle(_ preset: FramePreset, pageIndex: Int) {
        guard let idx = pages.firstIndex(where: { $0.index == pageIndex }) else { return }
        pages[idx].background = preset.background
        for i in placements.indices where placements[i].pageIndex == pageIndex {
            placements[i].frameOverride = preset.photoFrame
        }
    }

    /// 指定スライドの「背景色」だけを設定する（余白は維持）。
    public mutating func setPageBackgroundColor(_ color: LayoutColor, pageIndex: Int) {
        guard let idx = pages.firstIndex(where: { $0.index == pageIndex }) else { return }
        pages[idx].background = CanvasBackgroundStyle(color: color, margins: pages[idx].background.margins)
    }

    /// プロジェクト全スライドの背景色を設定する（背景はプロジェクト共通）。
    public mutating func setAllPagesBackgroundColor(_ color: LayoutColor) {
        for i in pages.indices {
            pages[i].background = CanvasBackgroundStyle(color: color, margins: pages[i].background.margins)
        }
    }

    /// 選択中の写真1枚の「枠（縁）」を設定する。nilでプロジェクト既定に戻す。写真選択コンテキスト用。
    public mutating func setPlacementFrame(_ frame: PhotoFrameStyle?, placementID: UUID) {
        guard let idx = placements.firstIndex(where: { $0.id == placementID }) else { return }
        placements[idx].frameOverride = frame
    }

    /// 写真1枚のロック状態を設定する。ロック中はジオメトリ操作（移動/拡縮/クロップ突入）と
    /// 削除を禁止する（重なり順変更・枠スタイル変更は対象外）。写真選択メニュー・レイヤーシート両方から呼ぶ。
    public mutating func setPlacementLocked(_ isLocked: Bool, placementID: UUID) {
        guard let idx = placements.firstIndex(where: { $0.id == placementID }) else { return }
        placements[idx].isLocked = isLocked
    }

    /// 1枚を全スライドにまたがせて敷く（プロジェクト配置モデル: 手動シームレスカルーセル用）。
    /// 等幅スライド前提で、アンカーページ正規化での全幅＝ページ数。画像は歪まない（中央クロップ）。
    public mutating func placeSpanningAllSlides(placementID: UUID) {
        guard let index = placements.firstIndex(where: { $0.id == placementID }),
              let anchor = page(at: placements[index].pageIndex) else { return }
        let dest = LayoutRect(x: 0, y: 0, width: Double(pages.count), height: 1)
        placements[index].slotIndex = nil
        placements[index].destRect = dest
        let targetPixelAspect = dest.aspectRatio * anchor.contentAspect
        placements[index].cropRect = CropMath.subCrop(
            .unit, photo: placements[index].photo, targetPixelAspect: targetPixelAspect
        )
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

/// SwiftUIの `RangeReplaceableCollection.move(fromOffsets:toOffset:)` はApple framework側の拡張で
/// Apple framework非依存のCoreからは使えないため、`List.onMove` と同じ意味論を素のSwiftで再実装する。
private extension Array {
    mutating func movingElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let itemsToMove = source.map { self[$0] }
        for offset in source.sorted(by: >) {
            remove(at: offset)
        }
        let itemsBeforeDestination = source.filter { $0 < destination }.count
        insert(contentsOf: itemsToMove, at: destination - itemsBeforeDestination)
    }
}
