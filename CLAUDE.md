# PhotoLayout 開発規約

X/Instagram向け投稿準備iOSアプリ。責務は**トリミング・枠付け・配置・高解像度書き出し**のみ（レタッチはスコープ外）。

## 環境の大前提（Macなし開発）

- 開発機はWSL2 (Ubuntu 24.04)。**XcodeもiOSシミュレータもローカルに存在しない**
- Apple framework（SwiftUI/SwiftData/PhotosUI/CoreGraphics）に依存するコードのコンパイル確認はGitHub Actions（macos-26）でしかできない。1往復≒10分 — **App層の変更はpush前に型・APIの自己レビューを必ず行う**
- `Packages/PhotoLayoutCore` はApple framework非依存。**ローカルの `swift test` で検証できる唯一の場所**。ロジックは必ずここに置く
- 実機確認は無料Apple ID＋Sideloadly手動サイドロード。CIはunsigned .ipaをartifact化するだけ（CIで署名しない）

## ツールチェーン（バージョンを揃えること）

| 場所 | バージョン |
|---|---|
| CI Xcode | 26.6 固定（`DEVELOPER_DIR`、macos-26イメージ） |
| CI / ローカル Swift | 6.3（swiftly管理。`~/.local/share/swiftly/bin` をPATHへ） |
| swift-tools-version | 6.3（Core＝Swift 6言語モード） |
| App層の言語モード | Swift 5（`SWIFT_VERSION: "5.0"`。strict concurrencyのCI往復を避けるため当面維持） |
| 最低iOS | 17.0 |

## コマンド

```bash
# ドメインロジックのテスト（開発の基本ループ。数秒で終わる）
swift test --package-path Packages/PhotoLayoutCore

# Xcodeプロジェクト生成（CIが実行。ローカルでは不可・不要）
xcodegen generate
```

## 設計ドキュメント（着手前に読む）

設計の全体像・ドメインモデル・座標系・編集モデルは `docs/` にまとめてある。**コードを触る前に必ず目を通すこと。**

- [docs/design.md](docs/design.md) — 統一「汎用プロジェクト」モデル、アーキテクチャ、エンティティ、座標系、Coreサービス早見表、書き出し3系統、編集モデル、永続化
- [docs/decisions.md](docs/decisions.md) — 主要な設計判断の理由と**廃止した設計（復活させないこと）**
- [docs/screens.md](docs/screens.md) — 全画面の**画面ID・機能ID**、状態と操作の網羅カタログ。スクショ命名規約（`画面ID-機能ID｜説明`）とフィルタ用 index.html の対応

## アーキテクチャ（要点。詳細は docs/design.md）

依存は一方向のみ: `Presentation → UseCases → Domain ← Infrastructure`（InfrastructureはDomainのPortを実装）。ロジックは Apple framework 非依存の `Packages/PhotoLayoutCore` に置き、Linux の `swift test` で検証する。具象の結線は `App/Presentation/Composition/AppComposition.swift` のみ。

### 破ってはいけないルール

1. Domain/UseCasesにApple framework（Foundation以外）をimportしない
2. 書き出しに `ImageRenderer(content:).scale` を使わない — 書き出しCGContextは目標ピクセルサイズ・`scale=1`で構築する
3. クロップは元画像に対する正規化(0..1) `LayoutRect` が正。scale+offsetを永続化しない
4. 枠・余白・角丸は出力解像度に対する**比率**で保持し、px化は `RenderPlanBuilder` と `PageGeometry`（描画とジェスチャで座標変換を共有）内のみ
5. プレビューと書き出しは共通の `RenderPlanBuilder` が生成する `[DrawCommand]` を解釈する。描画ロジックを2箇所に書かない
6. 並び順はSwiftDataの配列順序に依存せず明示的な `index`（ページ）/`sortIndex`（配置）フィールドで管理

> これらの根拠と、モデル全体（自由変形の不変条件・座標系・Coreサービス）は [docs/design.md](docs/design.md) 参照。**過去に廃止した設計を復活させないこと**（[docs/decisions.md](docs/decisions.md)）。

## 開発ワークフロー（2026-07-08 改定: trunkベース）

- **動く段階まで仕上げて main へ直接コミット**する（Issue/PR単位の開発は廃止。大きな設計変更の相談はIssueを使ってもよい）
- push前の必須条件: ① Core `swift test` グリーン ② App層差分の型・API自己レビュー（CI往復10分を無駄にしない）
- push後はCI（core-tests / ios-ci）を監視し、赤くなったら**即fix-forward**（revertより前進修正を優先）
- mainへのpushで自動デプロイ:
  - **Appetize**（`appetize.yml`）: ブラウザ上のシミュレータで動作確認（要 `APPETIZE_API_TOKEN` Secret）
  - **unsigned .ipa**（ios-ci artifact）: Sideloadlyで実機確認
- CIのXCUITestスクリーンショット（artifact）も画面確認の手段。画面を追加・変更したらスクショテストも更新する
