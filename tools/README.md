# tools/ — 実機なしで確認する道具

## 操作ギャラリー（画面＝書き出し結果）

各操作シナリオの描画結果を、**CI・実機なし・数秒**でPNG/HTMLに起こす。人間もAIも見て改善点を掴み、短いサイクルで回すためのもの。

```bash
tools/gallery.sh            # -> gallery/gallery.png（全シナリオ1枚）, gallery/index.html, 00.png..
open gallery/index.html     # 人間はブラウザで
```

- `RenderPlanBuilder` の `[DrawCommand]` はプレビューも書き出しも同一。ここで描くのは
  **編集画面のキャンバスであり、書き出し結果でもある**。
- 写真はファイル名から決めたグラデーション＋位置マーカーで代替（配置・テンプレ・枠・
  クロップ・背景・スライドまたぎ等のレイアウト結果を確認する用途）。
- シナリオの追加は `Packages/PhotoLayoutCore/Tests/PhotoLayoutCoreTests/GallerySnapshot.swift`
  の `GalleryScenarios.all()` に1つ足すだけ（Coreミューテーションで状態を作る）。

仕組み: `GALLERY_OUT=... swift test --filter generateGallery`（Swift/Linux）が描画命令をJSON化
→ `tools/render_gallery.py`（Python/PIL）がPNG＋HTML化。

> 編集画面のUIそのもの（選択ハンドル・下部メニュー等）は含まれない。それらはCIのXCUITest
> スクリーンショットで確認する。
