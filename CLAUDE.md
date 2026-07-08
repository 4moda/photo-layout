# PhotoLayout 開発規約

X/Instagram向け投稿準備iOSアプリ。責務は**トリミング・枠付け・配置・高解像度書き出し**のみ（レタッチはスコープ外）。

## 環境の大前提（Macなし開発）

- 開発機はWSL2 (Ubuntu 24.04)。**XcodeもiOSシミュレータもローカルに存在しない**
- Apple framework（SwiftUI/SwiftData/PhotosUI/CoreGraphics）に依存するコードのコンパイル確認はGitHub Actions（macos-15）でしかできない。1往復≒10分 — **App層の変更はpush前に型・APIの自己レビューを必ず行う**
- `Packages/PhotoLayoutCore` はApple framework非依存。**ローカルの `swift test` で検証できる唯一の場所**。ロジックは必ずここに置く
- 実機確認は無料Apple ID＋Sideloadly手動サイドロード。CIはunsigned .ipaをartifact化するだけ（CIで署名しない）

## ツールチェーン（バージョンを揃えること）

| 場所 | バージョン |
|---|---|
| CI Xcode | 16.4 固定（`DEVELOPER_DIR`、macos-15イメージ） |
| CI / ローカル Swift | 6.1（swiftly管理。`~/.local/share/swiftly/bin` をPATHへ） |
| swift-tools-version | 6.1（Core＝Swift 6言語モード） |
| App層の言語モード | Swift 5（`SWIFT_VERSION: "5.0"`。strict concurrencyのCI往復を避けるため当面維持） |
| 最低iOS | 17.0 |

## コマンド

```bash
# ドメインロジックのテスト（開発の基本ループ。数秒で終わる）
swift test --package-path Packages/PhotoLayoutCore

# Xcodeプロジェクト生成（CIが実行。ローカルでは不可・不要）
xcodegen generate
```

## アーキテクチャ（Layered / Clean）

依存は一方向のみ: `Presentation → UseCases → Domain ← Infrastructure`（InfrastructureはDomainのPortを実装）。

- **Domain**（`Packages/PhotoLayoutCore/Sources/PhotoLayoutCore/Domain/`）: Entities / ValueObjects / PlatformSpec / Services / Ports。**何もimportしない**（Foundationのみ可）
- **UseCases**（同パッケージ）: DomainのPort protocolだけに依存。テストはフェイクPort注入で`swift test`
- **Infrastructure**（`App/Infrastructure/`）: Portの実装。SwiftData/PhotosUI/ImageIO/CoreGraphicsを知るのはここだけ
- **Presentation**（`App/Presentation/`）: View + @Observable ViewModel。UseCaseのみに依存
- 具象の結線は `App/Presentation/Composition/AppComposition.swift` のみ

### 破ってはいけないルール

1. Domain/UseCasesにApple framework（Foundation以外）をimportしない
2. 書き出しに `ImageRenderer(content:).scale` を使わない — 書き出しCGContextは目標ピクセルサイズ・`scale=1`で構築する
3. クロップは元画像に対する正規化(0..1) `LayoutRect` が正。scale+offsetを永続化しない
4. 枠・余白・角丸は出力解像度に対する**比率**で保持し、px化は `RenderPlanBuilder` と `PageGeometry`（描画とジェスチャで座標変換を共有）内のみ
5. プレビューと書き出しは共通の `RenderPlanBuilder` が生成する `[DrawCommand]` を解釈する。描画ロジックを2箇所に書かない
6. 並び順はSwiftDataの配列順序に依存せず明示的な `index`（ページ）/`sortIndex`（配置）フィールドで管理

## ドメインモデルと設計の要点（引き継ぎ用）

### 統一「汎用プロジェクト」モデル（最重要の考え方）

**枠付けとレイアウトは別機能ではなく、同じ汎用プロジェクトの2つの使い方**。プロジェクト＝キャンバス（用紙アスペクト）＋画像＋書き出し。SNS別の「モード」は持たない（アスペクト比やテンプレートの選択肢をSNS名でラベルするのはOK）。

- **枠付けプロジェクト**: 1枚＋余白を 8:9 / 16:9 / 1:1 等のキャンバスに置き、枠付き画像として書き出す
- **レイアウトプロジェクト**: 1:1 等のキャンバス＋テンプレートに、（枠付けプロジェクトで作った）画像を流し込んで1枚に合成
- 一方の書き出し画像がもう一方の入力になる（カメラロール経由）。**同じエディタ・同じ描画/書き出し機構**で両方を扱う

### エンティティ（`Domain/Entities/`）

```
ProjectEntity              # 下書き1件。pages と placements を持つ（placementはページの子ではなくProject直下）
├── platformPreset?        # .x / .instagram。現在は「不活性メタデータ」。挙動は分岐させない
├── pages: [PageEntity]    # index順。各ページ = 1書き出し単位。aspect + background(色・余白)
├── placements: [PlacementEntity]
│   ├── sortIndex          # 重なり順（昇順で奥→手前）
│   ├── pageIndex          # 所属ページ
│   ├── photo: PhotoRef    # ローカルコピーのファイル名 + 元ピクセルサイズ
│   ├── cropRect           # 元画像に対する正規化(0..1)。画像のどこを見せるか
│   ├── destRect           # 所属ページの配置領域に対する正規化。写真の表示矩形（枠が付く対象）
│   └── frameOverride?     # 写真ごとの枠（色・太さ・角丸）
└── defaultPhotoFrame
```

**自由変形モデル（fill/fitの永続モードは廃止）**: 写真はCanva/SCRL型の自由変形オブジェクト。
- **不変条件**: `destRect`のピクセルアスペクト == `cropRect`のピクセルアスペクト。配置ヘルパ（`ProjectEntity+Mutations`）が維持し、`RenderPlanBuilder` が `CropMath.subCrop` で防御的に正規化 → 画像は絶対に歪まない
- **枠のアスペクトは変えられるが画像は歪まない**: 枠を変えると「枠の中で見せる範囲（cropRect）」が変わるだけ（`resizeFrame` / `setFramePixelAspect`）
- `destRect`はページ配置領域からはみ出してよい。`RenderPlanBuilder`が可視部分だけ描く（はみ出し＝クロップ調整）

### 座標系（混同しないこと）

- **cropRect**: 元画像の正規化(0..1)
- **destRect**: 所属ページの「配置領域（余白を除いた領域）」の正規化(0..1)
- **スプレッド空間**（`SpreadGeometry`）: 全ページを高さ1.0で隙間なく横連結した座標。シームレスキャンバスとページまたぎの基盤
- **px**: 実出力ピクセル。比率→pxの変換は `RenderPlanBuilder` と `PageGeometry` だけ

### Coreサービス早見表（`Domain/Services/`）

| 型 | 役割 |
|---|---|
| `RenderPlanBuilder` | ページ→`[DrawCommand]`。プレビューも書き出しも唯一これを解釈（乖離しえない） |
| `DrawCommand` | fillRect / drawImage(sourceRect,destRect) / strokeBorder。px単位の描画命令 |
| `PageGeometry` | contentRect（余白差引）と destRect→px矩形。描画とジェスチャで共有 |
| `SpreadGeometry` | ページ隙間なし連結座標。原点/矩形/ページ⇄スプレッド変換 |
| `PlacementGesture` | ジェスチャ→ジオメトリ純粋計算。move/scale/scaleAnchored(対角固定)/stretchEdge(枠比率)/panCrop/zoomCrop |
| `SnapEngine` | 移動中の辺・中心スナップ＋ガイド線 |
| `CropMath.subCrop` | クロップを目標pxアスペクトへ中央絞り込み（不変条件の要） |
| `ExportSizeCalculator` | 出力pxサイズ決定（元解像度ベース・長辺4096クランプ・偶数丸め） |
| `EditHistory` | ProjectEntityスナップショットのundo/redoスタック |
| `LayoutTemplate` / `LayoutTemplateTable` | スロット矩形テンプレ（単写真/2-4分割/Xタイムライン）。`applyTemplate`で写真をスロットへ |
| `XTimelineComposite` | Xタイムライン表示のスロット配置（テンプレの一種として利用） |

### UseCases（書き出しの3系統）

- `ExportPageUseCase.execute(pageIndex:)` — 1ページを1枚で（基本）
- `.executeAll()` — 全ページを投稿順に（複数ページ/カルーセル）
- `.executeSlots(pageIndex:)` — 1ページ内の各スロットを個別のトリミング済み画像で（汎用。X複数投稿など）

### 編集モデル（`App/Presentation/Screens/PageEditor/`）

- **シームレスキャンバス**: 全ページを隙間ゼロで横連結表示。横パンで移動、写真非選択時のピンチでビューポート全体をズーム（`SpreadGeometry`基準）
- **コンテキスト依存メニュー**: 写真選択中=写真メニュー（枠比率/全面/マット/クロップ/レイヤー順/削除）、非選択=ページメニュー（比率/テンプレート/全面/マット/枠プリセット/ページ俯瞰）
- **クロップモード**: ダブルタップで枠固定→中身をパン/ズーム、枠の外タップで完了
- **ハンドル**: 角＝対角固定のアスペクト固定拡縮、辺＝枠アスペクト変更（画像は歪まない）
- **ページ俯瞰モード**（`PageOverviewView`）: 挿入/削除/並べ替え。ピンチアウトでも遷移。左上キャンセル/右上確定
- **書き出しボタン**: 「ページを1枚で」/「各写真を個別に」の汎用選択（2枚以上で後者を提示）
- ジェスチャの純粋計算はCore、Viewは画面pt↔正規化の変換とState管理だけ

### 廃止した設計（復活させないこと）

- **SNS別モード**（X編集専用ビュー等）: 汎用プロジェクトに統一済み。`isXPost`分岐を増やさない
- **fill/fitの永続モード**（`ContentMode`）: 自由変形（cropRect+destRect）に置換済み
- **ページ送りUI（< 1/N >）**: シームレスキャンバスに置換済み
- `ImageRenderer(content:).scale`（低解像度化の原因）: 使わない（厳守ルール2）

## 実装計画

全体計画・フェーズ・残タスクは `/home/taiga/.claude/plans/ios-mvp-vast-sprout.md`（開発者ローカル）。リポジトリ内で完結させたい場合はIssue（GitHub）とこのCLAUDE.mdを正とする。

## 開発ワークフロー（2026-07-08 改定: trunkベース）

- **動く段階まで仕上げて main へ直接コミット**する（Issue/PR単位の開発は廃止。大きな設計変更の相談はIssueを使ってもよい）
- push前の必須条件: ① Core `swift test` グリーン ② App層差分の型・API自己レビュー（CI往復10分を無駄にしない）
- push後はCI（core-tests / ios-ci）を監視し、赤くなったら**即fix-forward**（revertより前進修正を優先）
- mainへのpushで自動デプロイ:
  - **Appetize**（`appetize.yml`）: ブラウザ上のシミュレータで動作確認（要 `APPETIZE_API_TOKEN` Secret）
  - **unsigned .ipa**（ios-ci artifact）: Sideloadlyで実機確認
- CIのXCUITestスクリーンショット（artifact）も画面確認の手段。画面を追加・変更したらスクショテストも更新する
