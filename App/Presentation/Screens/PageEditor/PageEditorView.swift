import SwiftUI
import PhotosUI
import UIKit
import PhotoLayoutCore

/// ページ編集画面。プロジェクト種別で編集面が変わる:
/// - X投稿: タイムライン合成ビュー（Issue #15 でテンプレートへ統合予定）
/// - Instagram/自由: シームレスキャンバス — 全ページを隙間ゼロで横に連結し、
///   パンで移動・写真非選択時のピンチでビューポートをズームする（Issue #9）。
///   写真操作は ドラッグ=移動（スナップ）、ピンチ/角ハンドル=アスペクト固定拡縮、
///   ダブルタップ=クロップモード（枠外タップで完了）
struct PageEditorView: View {
    @State private var viewModel: PageEditorViewModel
    @State private var photoPickerPresented = false
    @State private var pickerItems: [PhotosPickerItem] = []
    // スロット充填ピッカー（空スロットのタップで開く）
    @State private var slotPickerPresented = false
    @State private var slotFillItem: PhotosPickerItem?
    /// 写真差し替え用ピッカー（選択中の写真を入れ替える）
    @State private var replacePickerPresented = false
    @State private var replaceItem: PhotosPickerItem?
    @State private var pendingSlotFill: (page: Int, slot: Int)?
    // フッターから開くビジュアル選択シート（テンプレ/枠比率/レイヤー/枠）は1枚に集約
    @State private var activeSheet: EditorSheet?
    // 枠シート（S02-F16）の微調整ドラフト値。プリセットタップで初期化し、スライダー/色選択で更新する
    @State private var frameSheetBorderWidthRatio: Double = 0
    @State private var frameSheetCornerRadiusRatio: Double = 0
    @State private var frameSheetColor: LayoutColor = .white
    // 書き出しプレビュー画面
    @State private var previewPresented = false

    enum EditorSheet: Int, Identifiable {
        case template, frameAspect, layers, frame
        var id: Int { rawValue }
    }
    /// 角ハンドルドラッグ開始時の角と中心（拡縮中に選択枠が動いても基準がぶれないよう固定）
    @State private var handleDragBase: (corner: CGPoint, center: CGPoint)?

    // シームレスキャンバスのビューポート状態
    @State private var viewZoom: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var pinchBase: (zoom: CGFloat, pan: CGSize)?
    @State private var dragMode: SpreadDragMode?
    /// ユーザーが手でビューポートをパン/ズームしたか。falseの間はgeoサイズの変化に追随して
    /// 現在ページを中央へフィットし直す（onAppear時点のgeoはナビゲーションバー等の確定前で
    /// 高さが違うことがあり、その値で計算したpanOffsetのままだとページが左・上へずれるため）
    @State private var didUserAdjustViewport = false
    private let controlsOverlayBaseHeight: CGFloat = 110
    private let cropRotationBarHeight: CGFloat = 90

    private enum SpreadDragMode {
        case photo(id: UUID, isCrop: Bool, denom: CGSize)
        case text(id: UUID, denom: CGSize)
        case pan(base: CGSize)
        case suppressed // 角ハンドル付近から始まったドラッグはハンドル側に譲る
    }

    init(viewModel: PageEditorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            spreadCanvas
                .frame(maxHeight: .infinity)
                .accessibilityIdentifier("pageEditor.canvas")
                // 空スロット充填ピッカーはキャンバスに付ける（複数モーダルを1ノードに積まない）
                .photosPicker(isPresented: $slotPickerPresented, selection: $slotFillItem, matching: .images)
                .onChange(of: slotFillItem) { _, newItem in
                    guard let newItem, let target = pendingSlotFill else { return }
                    slotFillItem = nil
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self) {
                            await viewModel.assignPhotoToSlot(
                                pageIndex: target.page, slotIndex: target.slot, data: data
                            )
                        }
                        pendingSlotFill = nil
                    }
                }

            VStack(spacing: 10) {
                if viewModel.cropModePlacementID == nil {
                    controls
                } else {
                    cropRotationBar
                }
            }
            .padding(.bottom, 8)
            // 差し替えピッカーはフッターに付ける（キャンバス・ルートと同一ノードに
            // 複数モーダルを積まない方針に合わせる）
            .photosPicker(isPresented: $replacePickerPresented, selection: $replaceItem, matching: .images)
            .onChange(of: replaceItem) { _, newItem in
                guard let newItem else { return }
                replaceItem = nil
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        await viewModel.replaceSelectedPhoto(data: data)
                    }
                }
            }
            // フッターのビジュアル選択シート（1枚に集約）
            .sheet(item: $activeSheet) { sheet in
                Group {
                    switch sheet {
                    case .template: templatePickerSheet
                    case .frameAspect: frameAspectPickerSheet
                    case .layers: layerSheet
                    case .frame: framePickerSheet
                    }
                }
                // 既定のガラス素材は背後のキャンバスが強く透けて文字が読みにくいため不透明寄りに
                .presentationBackground(.regularMaterial)
            }
            // 書き出しプレビュー（俯瞰カバーと別ノードに付けて多重モーダル競合を避ける）
            .fullScreenCover(isPresented: $previewPresented) {
                PreviewView(viewModel: viewModel)
            }
        }
        .padding(.vertical)
        // プロジェクトに名前は付けない方針（一覧はサムネイル識別）のため、タイトルは表示しない
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await viewModel.undo() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canUndo)
                .accessibilityIdentifier("pageEditor.undo")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await viewModel.redo() }
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!viewModel.canRedo)
                .accessibilityIdentifier("pageEditor.redo")
            }
            ToolbarItem(placement: .topBarLeading) {
                // 現在スライド番号（写真追加は下部中央の⊕へ集約）
                Text(viewModel.pageCount > 1 ? "\(viewModel.currentPageIndex + 1)/\(viewModel.pageCount)" : "")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pageEditor.pageLabel")
            }
            ToolbarItem(placement: .topBarTrailing) {
                exportToolbarButton
            }
        }
        // 俯瞰はフッター、書き出しは右上へ集約（上部バーは戻る/undo/redo/番号/保存）
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.isOverviewMode },
            set: { if !$0 { viewModel.cancelOverview() } }
        )) {
            PageOverviewView(viewModel: viewModel)
        }
        .photosPicker(isPresented: $photoPickerPresented, selection: $pickerItems, matching: .images)
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            let items = newItems
            pickerItems = []
            Task {
                var datas: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        datas.append(data)
                    }
                }
                await viewModel.addPhotosData(datas)
            }
        }
        .task { await viewModel.onAppear() }
    }

    // MARK: - シームレスキャンバス（スプレッド表示）

    /// 全ページを SpreadGeometry の座標で隙間なく連結して描画する。
    /// パン=ドラッグ（空き地から開始）、ズーム=写真非選択時のピンチ。
    private var spreadCanvas: some View {
        GeometryReader { geo in
            let project = viewModel.project
            let stripHeight = geo.size.height * viewZoom
            let stripWidth = CGFloat(SpreadGeometry.totalWidth(project: project)) * stripHeight

            ZStack(alignment: .topLeading) {
                ForEach(project.orderedPages, id: \.id) { page in
                    if let frame = SpreadGeometry.pageFrame(project: project, pageIndex: page.index) {
                        CanvasRenderView(
                            page: page,
                            // 隣スライドからはみ出して重なる写真も描く（プロジェクト配置モデル）
                            placements: SpreadGeometry.visiblePlacements(onPage: page.index, project: project),
                            textItems: project.textItems(onPage: page.index),
                            defaultFrame: project.defaultPhotoFrame,
                            images: viewModel.previewImages
                        )
                        .frame(width: frame.width * stripHeight, height: stripHeight)
                        // 暗いキャンバス地に対してスライド外周を薄く縁取り（黒背景でも境界が分かる）
                        .overlay(Rectangle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                        .position(
                            x: (frame.x + frame.width / 2) * stripHeight,
                            y: stripHeight / 2
                        )
                    }
                }
                // ページ境界の目印（書き出しには含まれない）
                ForEach(Array(project.orderedPages.dropFirst()), id: \.id) { page in
                    if let originX = SpreadGeometry.pageOriginX(project: project, pageIndex: page.index) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 1, height: stripHeight)
                            .position(x: CGFloat(originX) * stripHeight, y: stripHeight / 2)
                            .allowsHitTesting(false)
                    }
                }
                emptySlotOverlay(stripHeight: stripHeight)
                stripSelectionOverlay(stripHeight: stripHeight, viewportHeight: geo.size.height)
                textSelectionOverlay(stripHeight: stripHeight, viewportHeight: geo.size.height)
            }
            .frame(width: stripWidth, height: stripHeight, alignment: .topLeading)
            .offset(panOffset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            // ページ内（白）とページ外を明確に区別するため、キャンバス地を暗くする
            .background(PLColor.graphite)
            .clipped()
            .contentShape(Rectangle())
            .gesture(stripDoubleTap(geo: geo).exclusively(before: stripSingleTap(geo: geo)))
            .simultaneousGesture(stripDrag(geo: geo))
            .simultaneousGesture(stripMagnify(geo: geo))
            // 初期表示とレイアウト確定（ナビバー・セーフエリア反映でgeoが変わる）に追随して
            // 中央フィット。ユーザーが手でパン/ズームした後は勝手に動かさない
            .onChange(of: geo.size, initial: true) { _, _ in
                guard !didUserAdjustViewport else { return }
                resetView(geo: geo)
            }
            // ページ追加/削除・切替後は現在ページを中央にフィットし直す
            .onChange(of: viewModel.pageCount) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) { resetView(geo: geo) }
            }
            .onChange(of: viewModel.currentPageIndex) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) { resetView(geo: geo) }
            }
            .overlay(cropOverlay(geo: geo, stripHeight: stripHeight))
        }
    }

    /// 選択中の配置の枠・ハンドル・スナップガイド（スプレッド座標）。クロップ中は `cropOverlay` が見た目を担うので出さない
    @ViewBuilder
    private func stripSelectionOverlay(stripHeight: CGFloat, viewportHeight: CGFloat) -> some View {
        if let contentStrip = selectedContentRectInStrip(stripHeight: stripHeight),
           let selectedID = viewModel.selectedPlacementID,
           let placement = viewModel.project.placements.first(where: { $0.id == selectedID }),
           viewModel.cropModePlacementID != selectedID {
            let rect = PageGeometry.imageRect(destRect: placement.destRect, in: contentStrip)
            if placement.isLocked {
                lockedSelectionChrome(rect: rect)
            } else {
                selectionChrome(rect: rect, contentRect: contentStrip, placementID: selectedID)
                ForEach(Array(viewModel.activeGuides.enumerated()), id: \.offset) { _, guide in
                    guideLine(guide, contentRect: contentStrip)
                }
            }
            selectionHoverMenu(
                rect: rect, placementID: selectedID,
                isLocked: placement.isLocked,
                stripHeight: stripHeight, viewportHeight: viewportHeight
            )
        }
    }

    /// 選択中のテキストの枠＋削除ボタン（スプレッド座標）。ドラッグでの移動はキャンバスのドラッグが直接受ける
    @ViewBuilder
    private func textSelectionOverlay(stripHeight: CGFloat, viewportHeight: CGFloat) -> some View {
        if let selectedID = viewModel.selectedTextItemID,
           let item = viewModel.project.textItems.first(where: { $0.id == selectedID }),
           let rect = textRect(for: item, pageIndex: item.pageIndex, stripHeight: stripHeight) {
            let layoutRect = LayoutRect(
                x: Double(rect.minX), y: Double(rect.minY),
                width: Double(rect.width), height: Double(rect.height)
            )
            Rectangle()
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
                .accessibilityIdentifier("pageEditor.textSelectionOverlay")
            textHoverMenu(rect: layoutRect, stripHeight: stripHeight, viewportHeight: viewportHeight)
        }
    }

    /// 選択中テキストの直上に出す削除ボタン（内容編集・サイズ/色UIは対象外＝次のIssue）
    private func textHoverMenu(rect: LayoutRect, stripHeight: CGFloat, viewportHeight: CGFloat) -> some View {
        HStack(spacing: 2) {
            hoverMenuButton(
                systemImage: "trash", tint: .red,
                identifier: "pageEditor.hover.deleteText"
            ) {
                Task { await viewModel.deleteSelectedText() }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .position(hoverMenuPosition(
            rect: rect, isLocked: false,
            stripHeight: stripHeight, viewportHeight: viewportHeight))
    }

    /// 選択写真の直上に出す小型のフローティングメニュー（ロック/複製/削除）。
    /// フッターの写真メニューと同じ操作への近接ショートカット（フッター側も残す）。
    /// 削除はフッター同様ロック中はdisabled
    private func selectionHoverMenu(
        rect: LayoutRect, placementID: UUID, isLocked: Bool,
        stripHeight: CGFloat, viewportHeight: CGFloat
    ) -> some View {
        HStack(spacing: 2) {
            hoverMenuButton(
                systemImage: isLocked ? "lock.fill" : "lock.open",
                identifier: "pageEditor.hover.lock"
            ) {
                Task { await viewModel.toggleLock(placementID: placementID) }
            }
            hoverMenuButton(
                systemImage: "plus.square.on.square",
                identifier: "pageEditor.hover.duplicate"
            ) {
                Task { await viewModel.duplicatePlacement(placementID: placementID) }
            }
            hoverMenuButton(
                systemImage: "trash", tint: .red,
                identifier: "pageEditor.hover.delete"
            ) {
                Task { await viewModel.deleteSelectedPhoto() }
            }
            .disabled(isLocked)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .position(hoverMenuPosition(
            rect: rect, isLocked: isLocked,
            stripHeight: stripHeight, viewportHeight: viewportHeight))
    }

    private func hoverMenuButton(
        systemImage: String, tint: Color = .primary,
        identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// ホバーメニューの表示位置: 選択クローム（枠線・ハンドル）の最上端から一定の間隔を空けた真上。
    /// 「最上端」は非ロック時は角ハンドルのはみ出し（枠線から約8pt）を含む — 常に枠線基準にすると
    /// ハンドルの無いロック時だけ間隔が広く見えて、キャプチャごとに位置関係が違って見えるため。
    /// はみ出し判定は**ページではなくビューポート（描画領域）基準**: ページ上端の近くでも
    /// 画面に暗いキャンバス地が見えていればそこへ置き、ビューポート上端からはみ出すときだけ
    /// 写真の下側へフリップする（それも無理なら枠内上部・ビューポート内に重ねる）。
    /// 水平方向はストリップ端で見切れないようクランプする
    private func hoverMenuPosition(
        rect: LayoutRect, isLocked: Bool, stripHeight: CGFloat, viewportHeight: CGFloat
    ) -> CGPoint {
        let stripWidth = SpreadGeometry.totalWidth(project: viewModel.project) * Double(stripHeight)
        let halfWidth: Double = 70
        let x = min(max(rect.midX, halfWidth), max(stripWidth - halfWidth, halfWidth))

        let menuHalfHeight: Double = 19 // アイコン34pt＋上下パディング2ptの半分
        let gap: Double = 5             // 選択クローム（枠線・ハンドル）との見た目の間隔
        let handleOverhang: Double = isLocked ? 0 : 8 // 角ハンドル（16pt円が枠線中心）のはみ出し
        // ストリップ座標→ビューポート座標は panOffset.height を足すだけ（ズームはstripHeightに織り込み済み）。
        // ビューポート上下端から8ptの余白を、ストリップ座標での可動範囲に変換しておく
        let minCenterY = 8.0 + menuHalfHeight - Double(panOffset.height)
        let maxCenterY = Double(viewportHeight) - 8 - menuHalfHeight - Double(panOffset.height)

        let aboveCenterY = rect.minY - handleOverhang - gap - menuHalfHeight
        let y: Double
        if aboveCenterY >= minCenterY {
            y = aboveCenterY
        } else {
            let belowCenterY = rect.maxY + handleOverhang + gap + menuHalfHeight
            y = belowCenterY <= maxCenterY
                ? belowCenterY
                : max(rect.minY + gap + menuHalfHeight, minCenterY)
        }
        return CGPoint(x: x, y: y)
    }

    /// ロック中の写真の選択表現: 選択枠のみ表示し、移動・拡縮ハンドルは出さない。
    /// 施錠アイコンをオーバーレイして操作不可であることを視覚的に示す
    private func lockedSelectionChrome(rect: LayoutRect) -> some View {
        ZStack {
            Rectangle()
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
            Image(systemName: "lock.fill")
                .font(.system(size: min(rect.width, rect.height) * 0.16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
        .accessibilityIdentifier("pageEditor.lockedSelectionOverlay")
    }

    /// クロップモード中のオーバーレイ: 元画像全体をレイアウト画面に重ねて表示し、
    /// クロップ枠の外側を暗いスクリムで覆う（内側は現状通り鮮明）。
    /// パン/ピンチのジェスチャは下のキャンバスがそのまま受けるので、このレイヤー自体はヒットテストを持たない。
    @ViewBuilder
    private func cropOverlay(geo: GeometryProxy, stripHeight: CGFloat) -> some View {
        if let cropID = viewModel.cropModePlacementID,
           let placement = viewModel.project.placements.first(where: { $0.id == cropID }),
           let contentStrip = contentRectInStrip(pageIndex: placement.pageIndex, stripHeight: stripHeight) {
            let window = PageGeometry.imageRect(destRect: placement.destRect, in: contentStrip)
            let dest = CGRect(
                x: window.x + panOffset.width,
                y: window.y + panOffset.height,
                width: window.width,
                height: window.height
            )
            // フル画像がdestRectへ写る拡大率（CanvasRenderViewのdrawImage写像と同じ式）
            let source = placement.cropRect
            let fullWidth = dest.width / source.width
            let fullHeight = dest.height / source.height
            let fullRect = CGRect(
                x: dest.minX - source.x * fullWidth,
                y: dest.minY - source.y * fullHeight,
                width: fullWidth,
                height: fullHeight
            )
            // 回転の軸（枠=destRectの中心）を、フル画像フレーム内の相対位置（0..1）へ変換する。
            // rotationEffectのanchorはposition()適用前のローカルフレーム基準の割合であるため、
            // これによりCanvasRenderView/CoreGraphicsExportRendererと同じ回転軸で見た目が一致する
            let rotationAnchor = UnitPoint(
                x: (dest.midX - fullRect.minX) / fullRect.width,
                y: (dest.midY - fullRect.minY) / fullRect.height
            )
            ZStack(alignment: .topLeading) {
                if let uiImage = viewModel.previewImages[cropID] {
                    Image(uiImage: uiImage)
                        .resizable()
                        .frame(width: fullRect.width, height: fullRect.height)
                        .rotationEffect(.degrees(placement.cropRotation), anchor: rotationAnchor)
                        .position(x: fullRect.midX, y: fullRect.midY)
                }
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geo.size))
                    path.addRect(dest)
                }
                .fill(Color.black.opacity(0.65), style: FillStyle(eoFill: true))
                cropFrameChrome(rect: dest)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityIdentifier("pageEditor.cropOverlay")
        }
    }

    /// クロップ枠の角・辺ハンドル（見た目のみ・既存selectionChromeの意匠を流用）。
    /// パン/ズームは写真自体のドラッグ/ピンチで行うため、ここにはジェスチャを付けない
    @ViewBuilder
    private func cropFrameChrome(rect: CGRect) -> some View {
        Rectangle()
            .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)

        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        ForEach(Array(corners.enumerated()), id: \.offset) { _, point in
            ZStack {
                Circle().fill(Color.white)
                Circle().stroke(Color.orange, lineWidth: 2)
            }
            .frame(width: 16, height: 16)
            .position(point)
        }

        let edges: [(point: CGPoint, vertical: Bool)] = [
            (CGPoint(x: rect.midX, y: rect.minY), false), (CGPoint(x: rect.midX, y: rect.maxY), false),
            (CGPoint(x: rect.minX, y: rect.midY), true), (CGPoint(x: rect.maxX, y: rect.midY), true)
        ]
        ForEach(Array(edges.enumerated()), id: \.offset) { _, edge in
            ZStack {
                Capsule().fill(Color.white)
                Capsule().stroke(Color.orange, lineWidth: 2)
            }
            .frame(width: edge.vertical ? 8 : 20, height: edge.vertical ? 20 : 8)
            .position(edge.point)
        }
    }

    /// 空スロット（写真未充填）の目印＋当てはめ導線。タップは通し、visualだけ描く。
    @ViewBuilder
    private func emptySlotOverlay(stripHeight: CGFloat) -> some View {
        ForEach(viewModel.project.orderedPages, id: \.id) { page in
            if let slots = page.slots,
               let content = contentRectInStrip(pageIndex: page.index, stripHeight: stripHeight) {
                ForEach(viewModel.project.emptySlotIndices(onPage: page.index), id: \.self) { i in
                    let slot = slots[i].rect
                    let w = slot.width * content.width
                    let h = slot.height * content.height
                    ZStack {
                        // スロット範囲がはっきり分かるよう、しっかりグレーで塗りつぶす＋アクセント破線
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(white: 0.72))
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.accentColor.opacity(0.9),
                                          style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                        Image(systemName: "plus")
                            .font(.system(size: min(w, h) * 0.28))
                            .foregroundStyle(Color.white)
                    }
                    .frame(width: w, height: h)
                    .position(
                        x: content.x + (slot.x + slot.width / 2) * content.width,
                        y: content.y + (slot.y + slot.height / 2) * content.height
                    )
                    .allowsHitTesting(false)
                }
            }
        }
    }

    /// 指定ページの配置領域（スプレッド空間のpt矩形）
    private func contentRectInStrip(pageIndex: Int, stripHeight: CGFloat) -> LayoutRect? {
        guard let page = viewModel.project.page(at: pageIndex),
              let originX = SpreadGeometry.pageOriginX(project: viewModel.project, pageIndex: pageIndex)
        else { return nil }
        let pageSize = LayoutSize(width: page.aspect.ratio * stripHeight, height: stripHeight)
        let content = PageGeometry.contentRect(page: page, pageSize: pageSize)
        return LayoutRect(
            x: content.x + originX * stripHeight,
            y: content.y,
            width: content.width,
            height: content.height
        )
    }

    /// 選択中の配置が属するページの配置領域（スプレッド空間のpt矩形）
    private func selectedContentRectInStrip(stripHeight: CGFloat) -> LayoutRect? {
        guard let selectedID = viewModel.selectedPlacementID,
              let placement = viewModel.project.placements.first(where: { $0.id == selectedID })
        else { return nil }
        return contentRectInStrip(pageIndex: placement.pageIndex, stripHeight: stripHeight)
    }

    /// ページのピクセル基準（出力解像度の短辺に相当）。フォントサイズ比率のpx化に使う
    /// （RenderPlanBuilderの`pagePixelSize.referenceDimension`と同じ式）
    private func pageReferenceDimension(pageIndex: Int, stripHeight: CGFloat) -> Double? {
        guard let page = viewModel.project.page(at: pageIndex) else { return nil }
        let pageSize = LayoutSize(width: page.aspect.ratio * stripHeight, height: stripHeight)
        return pageSize.referenceDimension
    }

    /// テキスト項目の描画矩形（スプレッド空間のpt）。選択枠・ヒットテストに使う。
    /// CanvasRenderView/CoreGraphicsExportRendererと同じ左上原点・システムフォントサイズで
    /// NSString計測するため、見た目の大きさとズレない
    private func textRect(for textItem: TextItemEntity, pageIndex: Int, stripHeight: CGFloat) -> CGRect? {
        guard let content = contentRectInStrip(pageIndex: pageIndex, stripHeight: stripHeight),
              let ref = pageReferenceDimension(pageIndex: pageIndex, stripHeight: stripHeight)
        else { return nil }
        let fontSizePx = CGFloat(textItem.fontSizeRatio * ref)
        let origin = CGPoint(
            x: CGFloat(content.x + textItem.x * content.width),
            y: CGFloat(content.y + textItem.y * content.height)
        )
        let size = (textItem.content as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSizePx)])
        return CGRect(origin: origin, size: size)
    }

    /// 指定ページ内で、指定点（スプレッド空間、pan未反映）に当たる最前面のテキストを返す
    private func textHit(atStripPoint point: CGPoint, pageIndex: Int, stripHeight: CGFloat) -> TextItemEntity? {
        viewModel.project.textItems(onPage: pageIndex).reversed().first { item in
            guard let rect = textRect(for: item, pageIndex: pageIndex, stripHeight: stripHeight) else { return false }
            return rect.insetBy(dx: -8, dy: -8).contains(point)
        }
    }

    /// 画面点 →（ページindex, ヒットしたテキスト）。パン/ズームを反映したビューポート座標を受け取る
    private func textHit(at point: CGPoint, geo: GeometryProxy) -> (pageIndex: Int, item: TextItemEntity)? {
        let stripHeight = geo.size.height * viewZoom
        let sp = CGPoint(x: point.x - panOffset.width, y: point.y - panOffset.height)
        guard sp.y >= 0, sp.y <= stripHeight else { return nil }
        let spreadX = Double(sp.x / stripHeight)
        guard let pageIndex = SpreadGeometry.pageIndex(atSpreadX: spreadX, project: viewModel.project),
              let hit = textHit(atStripPoint: sp, pageIndex: pageIndex, stripHeight: stripHeight)
        else { return nil }
        return (pageIndex, hit)
    }

    // MARK: - キャンバス座標変換

    /// 画面点 →（ページindex, 配置領域の正規化座標）
    private func locate(_ point: CGPoint, geo: GeometryProxy) -> (pageIndex: Int, nx: Double, ny: Double)? {
        let stripHeight = geo.size.height * viewZoom
        let sp = CGPoint(x: point.x - panOffset.width, y: point.y - panOffset.height)
        guard sp.y >= 0, sp.y <= stripHeight else { return nil }
        let spreadX = Double(sp.x / stripHeight)
        guard let pageIndex = SpreadGeometry.pageIndex(atSpreadX: spreadX, project: viewModel.project),
              let page = viewModel.project.page(at: pageIndex),
              let originX = SpreadGeometry.pageOriginX(project: viewModel.project, pageIndex: pageIndex)
        else { return nil }
        let pagePt = CGPoint(x: sp.x - CGFloat(originX) * stripHeight, y: sp.y)
        let pageSize = LayoutSize(width: page.aspect.ratio * stripHeight, height: stripHeight)
        let content = PageGeometry.contentRect(page: page, pageSize: pageSize)
        guard content.width > 0, content.height > 0 else { return nil }
        return (
            pageIndex,
            (Double(pagePt.x) - content.x) / content.width,
            (Double(pagePt.y) - content.y) / content.height
        )
    }

    /// 現在ページが全体見えて左右の隣がのぞくズーム倍率。
    /// ページ高さ≒ビューポート高の88%、ページ幅≒ビューポート幅の78%（左右に隣がのぞく）に収める。
    private func fitZoom(geo: GeometryProxy) -> CGFloat {
        let layoutHeight = editorLayoutHeight(geo: geo)
        guard let page = viewModel.page, geo.size.height > 0, layoutHeight > 0 else { return 1 }
        let aspect = CGFloat(max(page.aspect.ratio, 0.01))
        let byHeight = layoutHeight * 0.88
        let byWidth = geo.size.width * 0.78 / aspect
        let stripHeight = min(byHeight, byWidth)
        return max(0.15, stripHeight / geo.size.height)
    }

    /// 現在ページを水平方向の中央へ置くパン量（垂直は中央固定）
    private func centeredPan(geo: GeometryProxy, zoom: CGFloat) -> CGSize {
        let stripHeight = geo.size.height * zoom
        guard let frame = SpreadGeometry.pageFrame(
            project: viewModel.project, pageIndex: viewModel.currentPageIndex
        ) else { return .zero }
        let centerX = CGFloat(frame.x + frame.width / 2) * stripHeight
        return CGSize(width: geo.size.width / 2 - centerX, height: 0)
    }

    /// 現在ページを中央にフィット（ズーム＋パンを既定へ）
    private func resetView(geo: GeometryProxy) {
        let zoom = fitZoom(geo: geo)
        viewZoom = zoom
        panOffset = clampedPan(desired: centeredPan(geo: geo, zoom: zoom), geo: geo, zoom: zoom)
    }

    /// クロップ中はフッター（スライド/写真メニュー）の代わりに回転ドラッグバーだけを出すため、
    /// その高さぶんだけキャンバスへ回す
    private func editorLayoutHeight(geo: GeometryProxy) -> CGFloat {
        let reserved = viewModel.cropModePlacementID == nil ? controlsOverlayBaseHeight : cropRotationBarHeight
        return max(geo.size.height - reserved, 1)
    }

    /// パンの可動域: キャンバスがビューポートより小さい軸は中央固定、大きい軸は端まで
    private func clampedPan(desired: CGSize, geo: GeometryProxy, zoom: CGFloat? = nil) -> CGSize {
        let z = zoom ?? viewZoom
        let stripHeight = geo.size.height * z
        let stripWidth = CGFloat(SpreadGeometry.totalWidth(project: viewModel.project)) * stripHeight
        let layoutHeight = editorLayoutHeight(geo: geo)
        var x = desired.width
        var y = desired.height
        if stripWidth <= geo.size.width {
            x = (geo.size.width - stripWidth) / 2
        } else {
            x = min(max(x, geo.size.width - stripWidth), 0)
        }
        if stripHeight <= layoutHeight {
            y = (layoutHeight - stripHeight) / 2
        } else {
            y = min(max(y, layoutHeight - stripHeight), 0)
        }
        return CGSize(width: x, height: y)
    }

    // MARK: - キャンバスのジェスチャ

    private func stripSingleTap(geo: GeometryProxy) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            // クロップ中はテキストのタップを無視し、クロップ対象の写真かどうかだけで判定する
            if viewModel.cropModePlacementID != nil {
                let loc = locate(value.location, geo: geo)
                let hit = loc.flatMap { viewModel.placement(atNormalizedX: $0.nx, y: $0.ny, onPage: $0.pageIndex) }
                if hit?.id != viewModel.cropModePlacementID {
                    viewModel.exitCropMode()
                }
                return
            }
            // テキストは最前面に描かれるため、写真より先にヒット判定する
            if let textHit = textHit(at: value.location, geo: geo) {
                viewModel.focusPage(textHit.pageIndex)
                viewModel.selectText(textHit.item.id)
                return
            }
            guard let loc = locate(value.location, geo: geo) else {
                // スライドの外（暗い地）をタップ → 何も選択なし（カルーセル視点）
                viewModel.deselectAll()
                return
            }
            viewModel.focusPage(loc.pageIndex)
            if let hit = viewModel.placement(atNormalizedX: loc.nx, y: loc.ny, onPage: loc.pageIndex) {
                viewModel.select(hit.id)
            } else if let slot = viewModel.emptySlot(atNormalizedX: loc.nx, y: loc.ny, onPage: loc.pageIndex) {
                // 空スロットのタップ → そのスロットへ当てはめる写真を選ぶ
                pendingSlotFill = (loc.pageIndex, slot)
                slotPickerPresented = true
            } else {
                // スライドの地をタップ → 写真の選択を外す（スライド編集コンテキスト）
                viewModel.deselectAll()
            }
        }
    }

    private func stripDoubleTap(geo: GeometryProxy) -> some Gesture {
        SpatialTapGesture(count: 2).onEnded { value in
            guard let loc = locate(value.location, geo: geo),
                  let hit = viewModel.placement(atNormalizedX: loc.nx, y: loc.ny, onPage: loc.pageIndex)
            else { return }
            viewModel.focusPage(loc.pageIndex)
            viewModel.toggleCropMode(hit.id)
        }
    }

    /// 写真の上から開始=写真の移動（クロップ中はクロップパン）、それ以外=ビューポートのパン
    private func stripDrag(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragMode == nil {
                    dragMode = beginStripDrag(at: value.startLocation, geo: geo)
                }
                switch dragMode {
                case .photo(let id, let isCrop, let denom):
                    if isCrop {
                        viewModel.updateCropPan(
                            placementID: id,
                            translationX: value.translation.width / denom.width,
                            translationY: value.translation.height / denom.height
                        )
                    } else {
                        viewModel.updateMove(
                            placementID: id,
                            translationX: value.translation.width / denom.width,
                            translationY: value.translation.height / denom.height
                        )
                    }
                case .text(let id, let denom):
                    viewModel.updateTextMove(
                        textItemID: id,
                        translationX: value.translation.width / denom.width,
                        translationY: value.translation.height / denom.height
                    )
                case .pan(let base):
                    didUserAdjustViewport = true
                    panOffset = clampedPan(
                        desired: CGSize(
                            width: base.width + value.translation.width,
                            height: base.height + value.translation.height
                        ),
                        geo: geo
                    )
                case .suppressed, nil:
                    break
                }
            }
            .onEnded { _ in
                if case .photo = dragMode {
                    Task { await viewModel.endGesture() }
                }
                if case .text = dragMode {
                    Task { await viewModel.endGesture() }
                }
                if case .pan = dragMode {
                    focusCenterPage(geo: geo)
                }
                dragMode = nil
            }
    }

    private func beginStripDrag(at start: CGPoint, geo: GeometryProxy) -> SpreadDragMode {
        // 角ハンドル付近はハンドルのジェスチャに譲る
        if let corners = selectedCornersInViewport(geo: geo),
           corners.contains(where: { hypot($0.x - start.x, $0.y - start.y) < 24 }) {
            return .suppressed
        }
        // テキストは最前面に描かれるため、写真より先にヒット判定する（クロップ中は対象外）
        if viewModel.cropModePlacementID == nil, let textHit = textHit(at: start, geo: geo) {
            viewModel.focusPage(textHit.pageIndex)
            viewModel.selectText(textHit.item.id)
            guard let content = contentRectInStrip(
                pageIndex: textHit.pageIndex, stripHeight: geo.size.height * viewZoom
            ) else {
                return .pan(base: panOffset)
            }
            return .text(id: textHit.item.id, denom: CGSize(width: content.width, height: content.height))
        }
        guard let loc = locate(start, geo: geo),
              let hit = viewModel.placement(atNormalizedX: loc.nx, y: loc.ny, onPage: loc.pageIndex),
              let page = viewModel.project.page(at: loc.pageIndex)
        else {
            return .pan(base: panOffset)
        }
        viewModel.focusPage(loc.pageIndex)
        let stripHeight = geo.size.height * viewZoom
        let pageSize = LayoutSize(width: page.aspect.ratio * stripHeight, height: stripHeight)
        let content = PageGeometry.contentRect(page: page, pageSize: pageSize)
        let isCrop = viewModel.cropModePlacementID == hit.id
        if isCrop {
            let imageRect = PageGeometry.imageRect(destRect: hit.destRect, in: content)
            return .photo(id: hit.id, isCrop: true, denom: CGSize(width: imageRect.width, height: imageRect.height))
        }
        viewModel.select(hit.id)
        return .photo(id: hit.id, isCrop: false, denom: CGSize(width: content.width, height: content.height))
    }

    /// 選択中配置の角・辺ハンドルのビューポート座標（キャンバスドラッグとの競合判定用）
    private func selectedCornersInViewport(geo: GeometryProxy) -> [CGPoint]? {
        let stripHeight = geo.size.height * viewZoom
        guard viewModel.cropModePlacementID == nil,
              let contentStrip = selectedContentRectInStrip(stripHeight: stripHeight),
              let selectedID = viewModel.selectedPlacementID,
              let placement = viewModel.project.placements.first(where: { $0.id == selectedID })
        else { return nil }
        let rect = PageGeometry.imageRect(destRect: placement.destRect, in: contentStrip)
        let points = Self.cornerOrder.map { cornerPoint($0, of: rect) }
            + Self.edgeOrder.map { edgePoint($0, of: rect) }
        return points.map { CGPoint(x: $0.x + panOffset.width, y: $0.y + panOffset.height) }
    }

    /// ピンチ: 写真選択中=写真の拡縮（クロップ中=クロップズーム）/ 非選択=ビューポートズーム
    private func stripMagnify(geo: GeometryProxy) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if let targetID = viewModel.cropModePlacementID ?? viewModel.selectedPlacementID {
                    if viewModel.cropModePlacementID == targetID {
                        viewModel.updateCropZoom(placementID: targetID, factor: value.magnification)
                    } else {
                        viewModel.updateScale(placementID: targetID, factor: value.magnification)
                    }
                } else {
                    if pinchBase == nil {
                        pinchBase = (zoom: viewZoom, pan: panOffset)
                    }
                    didUserAdjustViewport = true
                    guard let base = pinchBase else { return }
                    let newZoom = min(max(base.zoom * value.magnification, 0.25), 4)
                    // ビューポート中央を不動点にする
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    let ratio = newZoom / base.zoom
                    let newPan = CGSize(
                        width: center.x - (center.x - base.pan.width) * ratio,
                        height: center.y - (center.y - base.pan.height) * ratio
                    )
                    viewZoom = newZoom
                    panOffset = clampedPan(desired: newPan, geo: geo, zoom: newZoom)
                }
            }
            .onEnded { _ in
                if pinchBase == nil {
                    Task { await viewModel.endGesture() }
                } else {
                    pinchBase = nil
                    // フィット倍率よりさらに十分引いたら俯瞰モードへ。ズームはフィットへ戻す
                    if viewZoom <= fitZoom(geo: geo) * 0.6, viewModel.pageCount > 1 {
                        resetView(geo: geo)
                        viewModel.enterOverview()
                    } else {
                        focusCenterPage(geo: geo)
                    }
                }
            }
    }

    /// ビューポート中央にあるページを「現在ページ」にする
    private func focusCenterPage(geo: GeometryProxy) {
        let stripHeight = geo.size.height * viewZoom
        guard stripHeight > 0 else { return }
        let spreadX = Double((geo.size.width / 2 - panOffset.width) / stripHeight)
        if let index = SpreadGeometry.pageIndex(atSpreadX: spreadX, project: viewModel.project) {
            viewModel.focusPage(index)
        }
    }

    // MARK: - 選択枠・ハンドル・ガイド（共通部品）

    /// 角の位置（ハンドル描画・アンカー計算共用）
    private func cornerPoint(_ corner: PlacementGesture.Corner, of rect: LayoutRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private static let cornerOrder: [PlacementGesture.Corner] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    private static let edgeOrder: [PlacementGesture.Edge] = [.top, .bottom, .leading, .trailing]

    private func edgePoint(_ edge: PlacementGesture.Edge, of rect: LayoutRect) -> CGPoint {
        switch edge {
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .leading: return CGPoint(x: rect.minX, y: rect.midY)
        case .trailing: return CGPoint(x: rect.maxX, y: rect.midY)
        }
    }

    /// 選択枠＋四隅ハンドル（対角固定・アスペクト固定拡縮）＋辺ハンドル（枠アスペクト変更）
    @ViewBuilder
    private func selectionChrome(rect: LayoutRect, contentRect: LayoutRect, placementID: UUID) -> some View {
        Rectangle()
            .stroke(Color.accentColor, lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
        // 角: 対角アンカーのアスペクト固定拡縮
        ForEach(Array(Self.cornerOrder.enumerated()), id: \.offset) { _, corner in
            ZStack {
                Circle().fill(Color.white)
                Circle().stroke(Color.accentColor, lineWidth: 2)
            }
            .frame(width: 16, height: 16)
            .contentShape(Circle().scale(2)) // 指で掴みやすいよう当たり判定を広げる
            .position(cornerPoint(corner, of: rect))
            .gesture(cornerHandleGesture(
                placementID: placementID,
                handle: cornerPoint(corner, of: rect),
                anchor: cornerPoint(corner.opposite, of: rect)
            ))
        }
        // 辺: 枠アスペクト変更（画像は歪まずクロップ窓が変わる）
        ForEach(Array(Self.edgeOrder.enumerated()), id: \.offset) { _, edge in
            let vertical = (edge == .leading || edge == .trailing)
            ZStack {
                Capsule().fill(Color.white)
                Capsule().stroke(Color.accentColor, lineWidth: 2)
            }
            .frame(width: vertical ? 8 : 20, height: vertical ? 20 : 8)
            .contentShape(Rectangle().scale(2.5))
            .position(edgePoint(edge, of: rect))
            .gesture(edgeHandleGesture(placementID: placementID, edge: edge, contentRect: contentRect))
        }
    }

    /// 角ハンドルのドラッグ: 対角（anchor）からの距離比＝拡縮率（アスペクト固定・対角固定）。
    /// 拡縮でハンドル位置自体が動くため、基準点はドラッグ開始時の値に固定する
    private func cornerHandleGesture(placementID: UUID, handle: CGPoint, anchor: CGPoint) -> some Gesture {
        let anchorCorner = anchorCorner(handle: handle, anchor: anchor)
        return DragGesture(minimumDistance: 1)
            .onChanged { value in
                if handleDragBase == nil {
                    handleDragBase = (corner: handle, center: anchor)
                }
                guard let base = handleDragBase else { return }
                let baseDistance = hypot(base.corner.x - base.center.x, base.corner.y - base.center.y)
                guard baseDistance > 1 else { return }
                let current = CGPoint(
                    x: base.corner.x + value.translation.width,
                    y: base.corner.y + value.translation.height
                )
                let distance = hypot(current.x - base.center.x, current.y - base.center.y)
                viewModel.updateScaleAnchored(
                    placementID: placementID,
                    factor: distance / baseDistance,
                    anchor: anchorCorner
                )
            }
            .onEnded { _ in
                handleDragBase = nil
                Task { await viewModel.endGesture() }
            }
    }

    /// ハンドルとアンカーの位置関係からアンカー側の角を判定する
    private func anchorCorner(handle: CGPoint, anchor: CGPoint) -> PlacementGesture.Corner {
        if anchor.x <= handle.x {
            return anchor.y <= handle.y ? .topLeft : .bottomLeft
        } else {
            return anchor.y <= handle.y ? .topRight : .bottomRight
        }
    }

    /// 辺ハンドルのドラッグ: 枠のアスペクトを変える（反対辺固定・画像は歪まない）
    private func edgeHandleGesture(placementID: UUID, edge: PlacementGesture.Edge, contentRect: LayoutRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let delta: Double
                switch edge {
                case .leading, .trailing:
                    delta = value.translation.width / contentRect.width
                case .top, .bottom:
                    delta = value.translation.height / contentRect.height
                }
                viewModel.updateStretchEdge(placementID: placementID, edge: edge, delta: delta)
            }
            .onEnded { _ in
                Task { await viewModel.endGesture() }
            }
    }

    private func guideLine(_ guide: SnapEngine.Guide, contentRect: LayoutRect) -> some View {
        Path { path in
            switch guide.axis {
            case .vertical:
                let x = contentRect.x + guide.position * contentRect.width
                path.move(to: CGPoint(x: x, y: contentRect.minY))
                path.addLine(to: CGPoint(x: x, y: contentRect.maxY))
            case .horizontal:
                let y = contentRect.y + guide.position * contentRect.height
                path.move(to: CGPoint(x: contentRect.minX, y: y))
                path.addLine(to: CGPoint(x: contentRect.maxX, y: y))
            }
        }
        .stroke(Color.pink, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        .allowsHitTesting(false)
    }

    // MARK: - コントロール（コンテキスト依存メニュー）

    /// 選択状態で出すメニューを切り替える（写真選択=写真メニュー / それ以外=スライド編集メニュー）。
    /// クロップ中はこのフッターの代わりに `cropRotationBar` を出す（`cropOverlay` が枠・スクリムの
    /// 見た目を担い、枠外タップで完了する）
    @ViewBuilder
    private var controls: some View {
        Group {
            if viewModel.selectedPlacementID != nil {
                photoControls
            } else if viewModel.selectedTextItemID != nil {
                textControls
            } else {
                slideControls
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
        )
        // フィルムのパーフォレーション（ミシン目）を模した、上端に沿う控えめなドット列。
        // シグネチャーモチーフの初回導入箇所。アイコンより手前に出さずヒットテストも奪わない
        .overlay(alignment: .top) {
            HStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 4, height: 4)
                    if index < 5 { Spacer(minLength: 0) }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 7)
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// クロップ中の回転バー: 画面下の水平ドラッグでクロップ窓内の写真を回転する（枠自体は回転しない）。
    /// Out of scope: これ以外の回転手段（キャンバス上の直接ジェスチャなど）は設けない
    @ViewBuilder
    private var cropRotationBar: some View {
        if let cropID = viewModel.cropModePlacementID,
           let placement = viewModel.project.placements.first(where: { $0.id == cropID }) {
            HStack(spacing: 10) {
                VStack(spacing: 6) {
                    Text("\(Int(placement.cropRotation.rounded()))°")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                    GeometryReader { barGeo in
                        ZStack {
                            Capsule()
                                .fill(Color.white.opacity(0.18))
                                .frame(height: 6)
                            Rectangle()
                                .fill(Color.orange)
                                .frame(width: 2, height: 20)
                        }
                        .frame(width: barGeo.size.width, height: barGeo.size.height)
                        .contentShape(Rectangle())
                        .gesture(cropRotationDragGesture(placementID: cropID, barWidth: barGeo.size.width))
                    }
                    .frame(height: 32)
                }
                .frame(maxWidth: 240)
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityIdentifier("pageEditor.cropRotationBar")

                // クロップ終了の明示的な出口（枠外タップでも終了できるが、初見では気づけないため）。
                // レイヤー順シート等の「閉じる」と同じ文言に揃える
                Button {
                    viewModel.exitCropMode()
                } label: {
                    Text("閉じる")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pageEditor.cropClose")
            }
            .padding(.bottom, 24)
        }
    }

    /// 回転バーの水平ドラッグ: 累積translationXをPlacementGesture.cropRotationFromDragへ渡す
    private func cropRotationDragGesture(placementID: UUID, barWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                viewModel.updateCropRotation(
                    placementID: placementID,
                    translationX: Double(value.translation.width),
                    barWidth: Double(barWidth)
                )
            }
            .onEnded { _ in
                Task { await viewModel.endGesture() }
            }
    }

    // MARK: - 下部ツールバーの共通部品（アイコン＋ラベル縦積み・横スクロールで崩れ防止）

    /// ツールバー1項目の見た目（アイコンの上に小さなラベル）。等幅にして整列させる。
    private func toolItemLabel(
        _ title: String, systemImage: String, tint: Color = .accentColor, width: CGFloat = 62
    ) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .frame(height: 24)
            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .frame(width: width)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func toolButton(
        _ title: String, systemImage: String, role: ButtonRole? = nil,
        identifier: String, width: CGFloat = 62, action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            toolItemLabel(
                title, systemImage: systemImage,
                tint: role == .destructive ? .red : .accentColor, width: width
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// 項目が画面幅を超えても崩れないよう横スクロールに載せる共通コンテナ。
    /// 項目が5つ以上のときは約5.5個分の幅に項目を縮め、右端の見切れで「まだ先がある」ことを示す
    /// （全項目が収まって見えると6個目以降の存在に気づけないため。closureには項目幅を渡す）。
    private func toolbarStrip<Content: View>(
        itemCount: Int, @ViewBuilder _ content: @escaping (CGFloat) -> Content
    ) -> some View {
        GeometryReader { geo in
            // 可視幅 ≒ 先頭パディング12 + 項目幅×5.5 + 間隔6×5
            let visibleCount: CGFloat = 5.5
            let itemWidth: CGFloat = itemCount >= 5
                ? max(48, (geo.size.width - 12 - 6 * 5) / visibleCount)
                : 62
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    content(itemWidth)
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(height: 54)
    }

    /// 枠アスペクトのプリセット（写真は歪まずクロップ窓が変わる）
    private static let frameAspectChoices: [(label: String, pixelAspect: Double)] =
        AspectRatioOption.orderedAll
            .filter { $0 != .landscape191 }
            .map { ($0.label, $0.aspect.ratio) }

    private static let frameAspectTolerance: Double = 1e-6

    /// 枠比率シートのスウォッチが現在値かどうか（`pixelAspect == nil` は「元画像」＝どのプリセットとも
    /// 一致しない場合を表す）。写真のネイティブ比がたまたまプリセットと一致する場合はプリセット側を優先する
    private func isCurrentFrameAspect(_ pixelAspect: Double?) -> Bool {
        guard let current = viewModel.currentFramePixelAspect else { return false }
        if let pixelAspect {
            return abs(pixelAspect - current) < Self.frameAspectTolerance
        }
        return !Self.frameAspectChoices.contains { abs($0.pixelAspect - current) < Self.frameAspectTolerance }
    }

    /// 写真選択中のメニュー（枠比率 / クロップ / 差し替え / 枠 / ロック切替 / 複製 / 削除）。
    /// 前面/背面はページ選択の「レイヤー」に集約、差し替えは廃止。移動/拡縮はドラッグ。
    /// ロック中はクロップ・削除がdisabled（Coreの`removePlacement`/ジェスチャガードと二重に防御）。
    private var photoControls: some View {
        toolbarStrip(itemCount: 7) { itemWidth in
            Button {
                activeSheet = .frameAspect
            } label: {
                toolItemLabel("枠比率", systemImage: "aspectratio", width: itemWidth)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pageEditor.frameAspectMenu")

            toolButton("クロップ", systemImage: "crop",
                       identifier: "pageEditor.cropButton", width: itemWidth) {
                if let id = viewModel.selectedPlacementID {
                    viewModel.toggleCropMode(id)
                }
            }
            .disabled(viewModel.isSelectedPhotoLocked)

            toolButton("差し替え", systemImage: "arrow.triangle.2.circlepath",
                       identifier: "pageEditor.replaceButton", width: itemWidth) {
                replacePickerPresented = true
            }
            .disabled(viewModel.isSelectedPhotoLocked)

            toolButton("枠", systemImage: "photo.artframe",
                       identifier: "pageEditor.frameButton", width: itemWidth) {
                activeSheet = .frame
            }

            toolButton(
                viewModel.isSelectedPhotoLocked ? "ロック解除" : "ロック",
                systemImage: viewModel.isSelectedPhotoLocked ? "lock.fill" : "lock.open",
                identifier: "pageEditor.lockButton",
                width: itemWidth
            ) {
                if let id = viewModel.selectedPlacementID {
                    Task { await viewModel.toggleLock(placementID: id) }
                }
            }

            toolButton("複製", systemImage: "plus.square.on.square",
                       identifier: "pageEditor.duplicateButton", width: itemWidth) {
                if let id = viewModel.selectedPlacementID {
                    Task { await viewModel.duplicatePlacement(placementID: id) }
                }
            }

            toolButton("削除", systemImage: "trash", role: .destructive,
                       identifier: "pageEditor.deletePhoto", width: itemWidth) {
                Task { await viewModel.deleteSelectedPhoto() }
            }
            .disabled(viewModel.isSelectedPhotoLocked)
        }
    }

    /// テキスト選択中のメニュー（削除のみ。移動はドラッグ、内容編集・サイズ/色UIは対象外＝次のIssue）
    private var textControls: some View {
        toolbarStrip(itemCount: 1) { itemWidth in
            toolButton("削除", systemImage: "trash", role: .destructive,
                       identifier: "pageEditor.deleteText", width: itemWidth) {
                Task { await viewModel.deleteSelectedText() }
            }
        }
    }

    /// 写真1枚の枠（縁）プリセット（写真選択コンテキスト）。タップすると太さ・角丸・縁色の
    /// 微調整（`frameSheetBorderWidthRatio`等）の起点として使われる
    private static let photoFrameChoices: [(label: String, frame: PhotoFrameStyle?)] = [
        ("なし", nil),
        ("白フチ", PhotoFrameStyle(borderColor: .white, borderWidthRatio: 0.012, cornerRadiusRatio: 0)),
        ("黒フチ", PhotoFrameStyle(borderColor: .black, borderWidthRatio: 0.006, cornerRadiusRatio: 0)),
        ("黒太フチ", PhotoFrameStyle(borderColor: .black, borderWidthRatio: 0.02, cornerRadiusRatio: 0)),
        ("角丸", PhotoFrameStyle(borderColor: .clear, borderWidthRatio: 0, cornerRadiusRatio: 0.05))
    ]

    /// 縁色の3択（白/黒/クリーム）。太さ0の間も選択状態を保持し、太さを上げた時点で反映される
    private static let frameColorChoices: [(identifier: String, label: String, color: LayoutColor)] = [
        ("white", "白", .white),
        ("black", "黒", .black),
        ("cream", "クリーム", .cream)
    ]

    private static let maxFrameBorderWidthRatio: Double = 0.06
    private static let maxFrameCornerRadiusRatio: Double = 0.5

    /// スライド編集メニュー（=既定/何も選択なし）。
    /// 写真追加は中央のフローティング +、書き出しは右上ツールバーへ移動。
    private var slideControls: some View {
        ZStack {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 10) {
                    templateButton
                    toolButton("レイヤー", systemImage: "square.stack.3d.up", identifier: "pageEditor.layerButton") {
                        activeSheet = .layers
                    }
                    toolButton("テキスト", systemImage: "textformat", identifier: "pageEditor.addText") {
                        Task { await viewModel.addText() }
                    }
                }
                Spacer(minLength: 0)
                toolButton("スライド", systemImage: "rectangle.stack", identifier: "pageEditor.overview") {
                    viewModel.enterOverview()
                }
            }
            addPhotoButton
        }
    }

    /// 写真追加（中央のフローティング +）
    private var addPhotoButton: some View {
        Button {
            photoPickerPresented = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(PLColor.accentText)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                )
                .shadow(color: Color.accentColor.opacity(0.28), radius: 12, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pageEditor.addPhoto")
    }

    /// 右上ツールバーの書き出し。押すとプレビュー画面へ。
    @ViewBuilder
    private var exportToolbarButton: some View {
        if viewModel.isExporting {
            ProgressView()
                .accessibilityIdentifier("pageEditor.export")
        } else {
            Button {
                previewPresented = true
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .foregroundStyle(viewModel.hasPhoto ? Color.accentColor : PLColor.textSecondary)
            .disabled(!viewModel.hasPhoto)
            .accessibilityIdentifier("pageEditor.export")
        }
    }

    /// 選択中の写真の枠（縁）をプリセット＋微調整（太さ・角丸スライダー、縁色）で選ぶシート（写真選択）
    private var framePickerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                        ForEach(Self.photoFrameChoices, id: \.label) { choice in
                            Button {
                                applyFramePreset(choice.frame)
                            } label: {
                                VStack(spacing: 6) {
                                    FrameSwatch(frame: choice.frame)
                                        .selectionHighlight(
                                            viewModel.currentFrameOverride == choice.frame,
                                            in: RoundedRectangle(cornerRadius: 6)
                                        )
                                    Text(choice.label).font(.caption2).foregroundStyle(.secondary)
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    frameAdjustmentControls
                }
                .padding(20)
            }
            .background(PLColor.surface)
            .navigationTitle("枠").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 和文タイトルへの刻印体（PLFont）試験導入。S01のワードマークで見た目を確認済みだが、
                // トラッキング付きの和文は未検証のため、まずこの1画面だけで試す
                ToolbarItem(placement: .principal) {
                    Text("枠").plStamp(size: 17)
                }
                ToolbarItem(placement: .confirmationAction) { Button("閉じる") { activeSheet = nil } }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            let base = viewModel.currentFrameOverride ?? .none
            frameSheetBorderWidthRatio = base.borderWidthRatio
            frameSheetCornerRadiusRatio = base.cornerRadiusRatio
            frameSheetColor = base.borderColor.alpha > 0 ? base.borderColor : .white
        }
    }

    /// 枠シートの微調整UI: 太さ・角丸スライダーと縁色（白/黒/クリーム）選択。プレビューはドラフト値へ即追従する
    private var frameAdjustmentControls: some View {
        VStack(alignment: .leading, spacing: 20) {
            FrameSwatch(frame: frameSheetDraft)
                .frame(width: 100, height: 100)
                .accessibilityIdentifier("pageEditor.frameSheetPreview")

            VStack(alignment: .leading, spacing: 8) {
                Text("太さ").font(.caption).foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { frameSheetBorderWidthRatio },
                        set: { newValue in
                            frameSheetBorderWidthRatio = newValue
                            viewModel.updateSelectedPhotoFrameLive(frameSheetDraft)
                        }
                    ),
                    in: 0...Self.maxFrameBorderWidthRatio
                ) { editing in
                    if !editing { Task { await viewModel.endFrameSheetGesture() } }
                }
                .accessibilityIdentifier("pageEditor.frameBorderWidthSlider")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("角丸").font(.caption).foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { frameSheetCornerRadiusRatio },
                        set: { newValue in
                            frameSheetCornerRadiusRatio = newValue
                            viewModel.updateSelectedPhotoFrameLive(frameSheetDraft)
                        }
                    ),
                    in: 0...Self.maxFrameCornerRadiusRatio
                ) { editing in
                    if !editing { Task { await viewModel.endFrameSheetGesture() } }
                }
                .accessibilityIdentifier("pageEditor.frameCornerRadiusSlider")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("縁色").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    ForEach(Self.frameColorChoices, id: \.identifier) { choice in
                        Button {
                            selectFrameColor(choice.color)
                        } label: {
                            Circle()
                                .fill(choice.color.swiftUIColor)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(PLColor.hairline, lineWidth: 1))
                                .selectionHighlight(frameSheetColor == choice.color, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pageEditor.frameColor.\(choice.identifier)")
                        .accessibilityLabel(choice.label)
                    }
                }
            }
        }
    }

    /// 枠シートの微調整ドラフト値から組み立てた現在の枠。太さ0・角丸0でも明示的な上書きとして扱う
    private var frameSheetDraft: PhotoFrameStyle {
        PhotoFrameStyle(
            borderColor: frameSheetColor,
            borderWidthRatio: frameSheetBorderWidthRatio,
            cornerRadiusRatio: frameSheetCornerRadiusRatio
        )
    }

    /// プリセットタップ: 太さ・角丸・縁色をそのプリセットの値へ初期化し、選択中写真へ確定反映する
    private func applyFramePreset(_ frame: PhotoFrameStyle?) {
        let base = frame ?? .none
        frameSheetBorderWidthRatio = base.borderWidthRatio
        frameSheetCornerRadiusRatio = base.cornerRadiusRatio
        frameSheetColor = base.borderColor.alpha > 0 ? base.borderColor : .white
        Task { await viewModel.setSelectedPhotoFrame(frame) }
    }

    /// 縁色タップ: 太さが0の間も選択状態を保持しつつ、選択中写真の枠へ即確定反映する
    private func selectFrameColor(_ color: LayoutColor) {
        frameSheetColor = color
        viewModel.updateSelectedPhotoFrameLive(frameSheetDraft)
        Task { await viewModel.endFrameSheetGesture() }
    }

    /// レイヤー順（重なり）の並べ替えシート: 現在スライドの写真を前面順で並べ、ドラッグまたは上下ボタンで入替。
    private var layerSheet: some View {
        let frontFirst = viewModel.currentPagePlacementsFrontFirst
        return NavigationStack {
            List {
                ForEach(Array(frontFirst.enumerated()), id: \.element.id) { index, placement in
                    HStack(spacing: 12) {
                        if let img = viewModel.previewImages[placement.id] {
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(PLColor.surfaceSecondary).frame(width: 64, height: 64)
                        }
                        Spacer()
                        Button { Task { await viewModel.toggleLock(placementID: placement.id) } } label: {
                            Image(systemName: placement.isLocked ? "lock.fill" : "lock.open")
                        }
                        .buttonStyle(.borderless)
                        .tint(placement.isLocked ? .accentColor : .secondary)
                        Button { Task { await viewModel.duplicatePlacement(placementID: placement.id) } } label: {
                            Image(systemName: "plus.square.on.square")
                        }
                        .buttonStyle(.borderless)
                        Button { Task { await viewModel.bringForward(placementID: placement.id) } } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        Button { Task { await viewModel.sendBackward(placementID: placement.id) } } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == frontFirst.count - 1)
                    }
                }
                .onMove { offsets, destination in
                    Task { await viewModel.movePlacements(fromOffsets: offsets, toOffset: destination) }
                }
            }
            .overlay {
                if frontFirst.isEmpty {
                    Text("このスライドに写真はありません").foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PLColor.surface)
            .navigationTitle("レイヤー順")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("レイヤー順").plStamp(size: 17)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { activeSheet = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// テンプレート（型枠）ボタン: タップで型枠の形をビジュアル一覧したシートを開く。
    private var templateButton: some View {
        Button {
            activeSheet = .template
        } label: {
            toolItemLabel("テンプレート", systemImage: "rectangle.split.2x2")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pageEditor.templateMenu")
    }

    /// 型枠の形をマス目でビジュアライズしたピッカー（5列グリッド）。
    /// 選ぶと現在スライドに型枠を敷き、空スロットに写真を当てはめる（スロット先行）。
    private var templatePickerSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 16) {
                    ForEach(viewModel.availableTemplates) { template in
                        Button {
                            activeSheet = nil
                            Task { await viewModel.applyTemplate(template) }
                        } label: {
                            VStack(spacing: 6) {
                                TemplateThumbnail(template: template)
                                    .selectionHighlight(
                                        template.id == viewModel.currentTemplateID,
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                                Text(template.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(template.name)
                    }
                }
                .padding(16)
            }
            .background(PLColor.surface)
            .navigationTitle("スライド \(viewModel.currentPageIndex + 1) のレイアウト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // 長め＋動的な文字列（ページ番号を含む）のためplStampのminimumScaleFactorで
                    // 幅が足りない場合に自動縮小させる
                    Text("スライド \(viewModel.currentPageIndex + 1) のレイアウト").plStamp(size: 17)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { activeSheet = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var frameAspectPickerSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3),
                    spacing: 16
                ) {
                    // 写真単体のクロップ窓の比率選択。比率は枠の中央に収める（S01/S03と同じ見せ方。
                    // SNS用途キャプションは新規作成・カルーセル比率の文脈でのみ意味があるためここでは出さない）
                    Button {
                        activeSheet = nil
                        Task { await viewModel.applyPhotoNativeAspect() }
                    } label: {
                        AspectRatioSwatch(aspect: nil, centerLabel: "元画像")
                            .selectionHighlight(
                                isCurrentFrameAspect(nil),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("元画像の比率（全体を表示）")

                    ForEach(Self.frameAspectChoices, id: \.label) { choice in
                        Button {
                            activeSheet = nil
                            Task { await viewModel.applyFrameAspect(pixelAspect: choice.pixelAspect) }
                        } label: {
                            AspectRatioSwatch(aspect: choice.pixelAspect, centerLabel: choice.label)
                                .selectionHighlight(
                                    isCurrentFrameAspect(choice.pixelAspect),
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(choice.label)
                    }
                }
                .padding(20)
            }
            .background(PLColor.surface)
            .navigationTitle("枠比率")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("枠比率").plStamp(size: 17)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { activeSheet = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// 型枠のスロット配置をマス目で表す小さなプレビュー（正方形）。
private struct TemplateThumbnail: View {
    let template: LayoutTemplate

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                ForEach(Array(template.slots.enumerated()), id: \.offset) { _, spec in
                    let slot = spec.rect
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color.accentColor, lineWidth: 1)
                        )
                        .frame(width: CGFloat(slot.width) * g.size.width,
                               height: CGFloat(slot.height) * g.size.height)
                        .offset(x: CGFloat(slot.x) * g.size.width,
                                y: CGFloat(slot.y) * g.size.height)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(PLColor.surfaceSecondary)
        )
    }
}

/// 写真の枠（縁）プリセットの見た目プレビュー（正方形）。写真領域に枠線・角丸を適用。
private struct FrameSwatch: View {
    let frame: PhotoFrameStyle?

    var body: some View {
        let f = frame ?? .none
        let radius = CGFloat(f.cornerRadiusRatio) * 60
        let lineWidth: CGFloat = f.borderWidthRatio > 0 ? max(2, CGFloat(f.borderWidthRatio) * 120) : 0
        return ZStack {
            Rectangle().fill(Color(.systemGray4)) // 地（白フチがシート背景に同化しない濃さ）
            RoundedRectangle(cornerRadius: radius)
                .fill(Color.gray.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(f.borderColor.swiftUIColor, lineWidth: lineWidth)
                )
                .padding(8)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.systemGray4), lineWidth: 0.5))
    }
}

extension LayoutColor {
    fileprivate var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
