# PhotoLayout

X / Instagram への写真投稿を準備するための iOS アプリ（開発中）。

写真家のワークフロー「撮影 → レタッチ（Lightroom等） → 書き出し → SNS投稿」の最後の区間を高速化する。レタッチはしない。**トリミング・枠付け・配置**と、**プラットフォーム仕様に正確な高解像度書き出し**だけをやる。

## 機能

- **汎用「プロジェクト」モデル**: 枠付けもレイアウトも同じプロジェクト（キャンバス＋画像＋書き出し）。1枚＋余白で枠付き画像を作るのも、テンプレートに複数枚を並べて1枚に合成するのも同じ仕組み
- **テンプレート配置**: 1ページに複数枚を割り付けるテンプレート（2〜4分割、Xタイムライン等）。用紙アスペクトは 1:1 / 4:5 / 3:4 / 16:9 / 1.91:1 などから選択（SNS名はラベルのみ）
- **書き出し**: ページを1枚で、または各写真を個別のトリミング済み画像で（X複数投稿など）。元画像の実解像度ベース（長辺4096px）
- **シームレスキャンバス**: 全ページを隙間なく連結表示（Instagramカルーセルの繋がりを確認）。パン＋ピンチズーム
- **プレビュー＝書き出し一致**を構造的に保証するレンダリング設計
- Undo/Redo、ページ俯瞰での挿入・並べ替え、ランタイム通信ゼロ・すべてオンデバイス

## 設計ドキュメント

- [docs/design.md](docs/design.md) — アーキテクチャ、ドメインモデル、座標系、Coreサービス、編集モデル
- [docs/decisions.md](docs/decisions.md) — 設計判断の理由と、廃止した設計

## 開発

このリポジトリは Mac を持たない環境（WSL2 + GitHub Actions）で開発されている。Claude / AIエージェント向けの運用ルール（ツールチェーン・厳守ルール・ワークフロー）は [CLAUDE.md](CLAUDE.md) を参照。

| 検証 | 場所 |
|---|---|
| ドメインロジック（`Packages/PhotoLayoutCore`） | ローカル `swift test`（Linux可） |
| iOSビルド・テスト・スクリーンショット・.ipa | GitHub Actions（macos-15） |

## プロジェクト構成

**ロジックは SwiftPM パッケージへ、Apple framework 依存は薄い Xcode シェルへ**、という
ハイブリッド構成（意図的）。iOS の**アプリ本体**と **XCUITest** は SwiftPM プロダクトに
なれない（SwiftPM に iOS アプリ製品型が無い）ため、「全部を `Packages/` に統一」はしない。

```
Packages/
  PhotoLayoutCore/   SwiftPM パッケージ。Domain / UseCases など framework 非依存の
                     ロジック。Linux の `swift test` で検証できる唯一の層。
App/                 Xcode アプリターゲット。Presentation / Infrastructure。
                     SwiftUI・SwiftData・CoreGraphics 等に依存し CI でのみコンパイル。
AppTests/
  PhotoLayoutTests/       Xcode ユニットテスト（App の Infrastructure など）
  PhotoLayoutUITests/     Xcode UIテスト（XCUITest）＋スクショ運用ツール一式
    ScreenshotSmokeTests.swift  画面・状態・操作を巡回して撮影
    SnapshotHelper.swift        fastlane snapshot 公式ヘルパ
    fastlane/Snapfile           snapshot 設定（撮影対象のUITestと同じ場所に置く）
    tools/build_screenshot_index.py  安全なASCII名のミラー画像と filterable index.html を生成
project.yml          XcodeGen 定義（.xcodeproj は生成物・非コミット）
docs/                design.md / decisions.md / screens.md（画面カタログ）
```

- 依存方向は `Presentation → UseCases → Domain ← Infrastructure`（詳細は [docs/design.md](docs/design.md)）。
- 全画面の**画面ID・機能ID**と状態/操作の網羅、スクショ命名規約は [docs/screens.md](docs/screens.md)。
- スクショ運用ツール（fastlane/tools）は撮影対象の UITest ターゲット配下に同居させる。
  CI はそのディレクトリを CWD にして `fastlane snapshot` を実行する。
