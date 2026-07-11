# 設計ドキュメント

PhotoLayout の設計・実装を引き継ぐための中核ドキュメント。運用ルール（Macなし開発・ツールチェーン・ワークフロー）は [../CLAUDE.md](../CLAUDE.md)、設計判断の経緯と「復活させない設計」は [decisions.md](decisions.md) を参照。

## 統一「汎用プロジェクト」モデル（最重要の考え方）

**枠付けとレイアウトは別機能ではなく、同じ汎用プロジェクトの2つの使い方**。プロジェクト＝キャンバス（用紙アスペクト）＋画像＋書き出し。SNS別の「モード」は持たない（アスペクト比やテンプレートの選択肢をSNS名でラベルするのはOK）。

- **枠付けプロジェクト**: 1枚＋余白を 8:9 / 16:9 / 1:1 等のキャンバスに置き、枠付き画像として書き出す
- **レイアウトプロジェクト**: 1:1 等のキャンバス＋テンプレートに、（枠付けプロジェクトで作った）画像を流し込んで1枚に合成
- 一方の書き出し画像がもう一方の入力になる（カメラロール経由）。**同じエディタ・同じ描画/書き出し機構**で両方を扱う

## アーキテクチャ（Layered / Clean）

依存は一方向のみ: `Presentation → UseCases → Domain ← Infrastructure`（Infrastructure は Domain の Port を実装）。

- **Domain**（`Packages/PhotoLayoutCore/Sources/PhotoLayoutCore/Domain/`）: Entities / ValueObjects / PlatformSpec / Services / Ports。**Foundation 以外を import しない**
- **UseCases**（同パッケージ）: Domain の Port protocol だけに依存。フェイク Port 注入で `swift test`
- **Infrastructure**（`App/Infrastructure/`）: Port の実装。SwiftData / PhotosUI / ImageIO / CoreGraphics を知るのはここだけ
- **Presentation**（`App/Presentation/`）: View + `@Observable` ViewModel。UseCase のみに依存
- 具象の結線は `App/Presentation/Composition/AppComposition.swift` のみ

`Packages/PhotoLayoutCore` は Apple framework 非依存なので、ロジックはすべてここに置き Linux の `swift test` で検証できる（Macなし開発の生命線）。

## エンティティ（`Domain/Entities/`）

```
ProjectEntity              # 下書き1件。pages と placements を持つ（placementはページの子ではなくProject直下）
├── platformPreset?        # .x / .instagram。現在は「不活性メタデータ」。挙動は分岐させない
├── pages: [PageEntity]    # index順。各ページ = 1書き出し単位。aspect + background(色・余白)
│                          # ※背景色はプロジェクト共通として全ページ一括で設定する（俯瞰/新規作成）
├── placements: [PlacementEntity]
│   ├── sortIndex          # 重なり順（昇順で奥→手前）
│   ├── pageIndex          # 所属ページ
│   ├── photo: PhotoRef    # ローカルコピーのファイル名 + 元ピクセルサイズ
│   ├── cropRect           # 元画像に対する正規化(0..1)。画像のどこを見せるか
│   ├── destRect           # 所属ページの配置領域に対する正規化。写真の表示矩形（枠が付く対象）
│   └── frameOverride?     # 写真ごとの枠（色・太さ・角丸）
└── defaultPhotoFrame
```

### 自由変形モデル（fill/fit の永続モードは廃止）

写真は Canva / SCRL 型の自由変形オブジェクト。

- **不変条件**: `destRect` のピクセルアスペクト == `cropRect` のピクセルアスペクト。配置ヘルパ（`ProjectEntity+Mutations`）が維持し、`RenderPlanBuilder` が `CropMath.subCrop` で防御的に正規化する → **画像は絶対に歪まない**
- **枠のアスペクトは変えられるが画像は歪まない**: 枠を変えると「枠の中で見せる範囲（cropRect）」が変わるだけ（`resizeFrame` / `setFramePixelAspect`）
- `destRect` はページ配置領域からはみ出してよい。`RenderPlanBuilder` が可視部分だけ描く（はみ出し＝クロップ調整）

## 座標系（混同しないこと）

- **cropRect**: 元画像の正規化(0..1)
- **destRect**: 所属ページの「配置領域（余白を除いた領域）」の正規化(0..1)
- **スプレッド空間**（`SpreadGeometry`）: 全ページを高さ1.0で隙間なく横連結した座標。シームレスキャンバスとページまたぎ配置の基盤
- **px**: 実出力ピクセル。比率→px の変換は `RenderPlanBuilder` と `PageGeometry` だけで行う

## プレビューと書き出しの一致（最重要の構造保証）

`RenderPlanBuilder.build(page:placements:defaultFrame:pagePixelSize:) -> [DrawCommand]` が「どの矩形に何を描くか」を一度だけ決める純粋関数。SwiftUI `Canvas`（プレビュー）も CoreGraphics（書き出し）も**同じコマンド列を解釈するだけ**なので、構造的に乖離しえない。

- 枠・余白・角丸は出力解像度に対する**比率**で保持し、px化は `RenderPlanBuilder` / `PageGeometry` 内のみ
- 書き出しは目標ピクセルサイズ・`scale=1` の CGContext で構築する。`ImageRenderer(content:).scale` は**使用禁止**（低解像度出力の原因）

## Core サービス早見表（`Domain/Services/`）

| 型 | 役割 |
|---|---|
| `RenderPlanBuilder` | ページ→`[DrawCommand]`。プレビューも書き出しも唯一これを解釈 |
| `DrawCommand` | fillRect / drawImage(sourceRect,destRect) / strokeBorder。px単位の描画命令 |
| `PageGeometry` | contentRect（余白差引）と destRect→px矩形。描画とジェスチャで共有 |
| `SpreadGeometry` | ページ隙間なし連結座標。原点/矩形/ページ⇄スプレッド変換・スプレッドX→ページindex |
| `PlacementGesture` | ジェスチャ→ジオメトリ純粋計算。move / scale / scaleAnchored(対角固定) / stretchEdge(枠比率) / panCrop / zoomCrop |
| `SnapEngine` | 移動中の辺・中心スナップ＋ガイド線 |
| `CropMath.subCrop` | クロップを目標pxアスペクトへ中央絞り込み（不変条件の要） |
| `ExportSizeCalculator` | 出力pxサイズ決定（元解像度ベース・長辺4096クランプ・偶数丸め） |
| `EditHistory` | ProjectEntity スナップショットの undo/redo スタック |
| `LayoutTemplate` / `LayoutTemplateTable` | スロット矩形テンプレ（単写真 / 2〜4分割 / Xタイムライン）。`ProjectEntity.applyTemplate` で写真をスロットへ |
| `XTimelineComposite` | Xタイムライン表示のスロット配置（テンプレの一種として利用） |
| `PlatformSpecTable` | X枚数別アスペクト・Instagramアスペクトの定数テーブル（仕様変更はここだけ更新） |

## 書き出しの3系統（`ExportPageUseCase`）

- `execute(pageIndex:)` — 1ページを1枚で書き出す（基本）
- `executeAll()` — 全ページを投稿順に（複数ページ / カルーセル）
- `executeSlots(pageIndex:)` — 1ページ内の各スロットを個別のトリミング済み画像で（汎用。X複数投稿など。スロット間ガター・ページ余白なしの縁いっぱい、写真ごとの枠線は保持）

## 編集モデル（`App/Presentation/Screens/PageEditor/`）

全画面の状態・操作の網羅カタログ（画面ID/機能ID）は [screens.md](screens.md)。

- **シームレスキャンバス**: 全ページを隙間ゼロで横連結表示。横パンで移動、写真非選択時のピンチでビューポート全体をズーム（`SpreadGeometry` 基準）。十分引くと俯瞰へ遷移
- **フッターは2状態**（「写真を選んでいるか否か」だけで切替。"ページ選択"という状態は持たない＝写真が乗ったページを選べず操作が不明瞭になるため）:
  - **スライド編集メニュー**（非選択・既定）: テンプレート / ⊕写真追加 / ↓ダウンロード（中央・主役）/ レイヤー順 / スライド俯瞰
  - **写真メニュー**（写真選択中）: 枠比率 / クロップ / 枠（縁）プリセット / 削除
  - **クロップ中**: 「クロップ完了」のみ
- **写真の初期配置は自然配置**: 追加した写真は元アスペクトのままページ中央付近に置く（fill/fit で強制しない）。複数枚は少しずつずらす（カスケード）
- **テンプレート（スロット先行）**: スライドに型枠（スロット矩形）を敷き、空スロットをタップして写真を充填。プロジェクト配置モデルなので写真は隣スライドへ跨げる（`SpreadGeometry.visiblePlacements`）
- **クロップモード**: ダブルタップで枠固定→中身をパン/ズーム、枠の外タップで完了
- **ハンドル**: 角＝対角固定のアスペクト固定拡縮、辺＝枠アスペクト変更（画像は歪まない）
- **ダウンロード＝プレビュー経由**: ↓ で書き出しプレビュー画面（`PreviewView`）へ遷移し、仕上がりを確認してからカメラロール保存（全ページ一括 / 各写真を個別に。1スライドに2枚以上で後者も提示）
- **スライド俯瞰**（`PageOverviewView`）: 横並び一覧で 挿入 / 複製 / 並べ替え（ドラッグ・長押しメニュー）/ 削除。**カルーセル全体の比率**と**プロジェクト共通の背景色**もここで設定。左上キャンセル / 右上確定
- **背景色はプロジェクト全体に適用**（俯瞰・新規作成で設定し、レイアウト画面にはメニューを置かない）。写真ごとの「枠（縁）」＝写真選択時、「背景色」＝プロジェクト単位、と責務を分ける
- ジェスチャの純粋計算は Core、View は画面pt↔正規化の変換と State 管理だけ

## 永続化（SwiftData）

Domain の純粋 struct（`ProjectEntity` 他）と Infrastructure の `@Model`（`ProjectModel`/`PageModel`/`PlacementModel`）を分離し、`SwiftDataProjectRepository` が双方向マッピングを担う。UseCases/Presentation は常に Entity だけを見る。

- スタイル等の複合値は JSON Data で格納（SwiftData の Codable 実装差異に依存しない）
- save は upsert（既存id は子ごと削除して再挿入）。未insert モデルへのリレーション代入クラッシュを避けるため、親を insert してから子配列を代入する
- 並び順は `index`（ページ）/`sortIndex`（配置）フィールドで明示管理（SwiftData の配列順序に依存しない）
- モデルに列を足すときは既定値付きプロパティで軽量マイグレーション（例: `pageIndex`）
