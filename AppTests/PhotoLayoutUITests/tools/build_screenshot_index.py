#!/usr/bin/env python3
"""fastlane snapshot の出力からフィルタ可能なスクショ一覧 index.html を生成する。

fastlane 標準の screenshots.html は言語・端末でしか分類できない。本スクリプトは
ファイル名に埋めた「画面ID(-機能ID)｜説明」を解析し、ASCIIのみの安全な
`<device-slug>/<lang>/<screen-id[-feature-id]-action>.png` ミラーを生成したうえで、
言語・端末・画面IDで絞り込めるビューア（単一の自己完結HTML）を出力する。
撮影自体は fastlane snapshot に任せ、これは出力の見せ方だけを担う薄い後処理。

命名規約（AppTests/PhotoLayoutUITests/ScreenshotSmokeTests.swift）:
    <画面ID>[-<機能ID>]｜<状態/操作の説明>
    例: S01-F02｜プロジェクトなし（空状態）
ファイル名は fastlane の規約で `<端末>-<スナップ名>.png`。ディレクトリ名が言語。
画面ID・機能IDの一覧は docs/screens.md と対応する。

使い方（リポジトリ直下から）:
    python3 AppTests/PhotoLayoutUITests/tools/build_screenshot_index.py \
        AppTests/PhotoLayoutUITests/fastlane/screenshots
      引数省略時の既定は CWD 基準の fastlane/screenshots
出力:
    <screenshots_dir>/index.html
    <screenshots_dir>/<device-slug>/<lang>/<safe-name>.png
"""
from __future__ import annotations

import json
import re
import shutil
import sys
import unicodedata
from html import escape
from pathlib import Path

# 画面IDの日本語名（docs/screens.md と揃える）
SCREEN_LABELS = {
    "S01": "プロジェクト一覧",
    "S02": "スライド編集",
    "S03": "スライド俯瞰",
    "S04": "書き出しプレビュー",
}

LANG_DIR_RE = re.compile(r"^[a-z]{2}(-[A-Za-z]{2,4})?$")  # ja-JP, en-US など
SCREEN_RE = re.compile(r"^(S\d+)")
FEATURE_RE = re.compile(r"(F\d+)")
SAFE_TOKEN_RE = re.compile(r"[^A-Za-z0-9]+")

# raw snapshot name -> safe ASCII file stem used by index.html
SAFE_NAME_MAP = {
    "S01-F01｜一覧（複数プロジェクト・サムネイル＋ページ数バッジ）": "S01-F01-project-list-populated",
    "S01-F02｜プロジェクトなし（空状態）": "S01-F02-project-list-empty-state",
    "S01-F03｜用紙サイズ選択メニュー": "S01-F03-project-list-paper-size-menu",
    "S01-F04｜新規作成 正方形 1：1（空キャンバス）": "S01-F04-create-square-canvas",
    "S01-F05｜新規作成 縦 4：5（空キャンバス）": "S01-F05-create-portrait-4-5-canvas",
    "S01-F06｜新規作成 縦 3：4（空キャンバス）": "S01-F06-create-portrait-3-4-canvas",
    "S01-F07｜新規作成 横 16：9（空キャンバス）": "S01-F07-create-landscape-16-9-canvas",
    "S01-F08｜新規作成 横長 1.91：1（空キャンバス）": "S01-F08-create-landscape-1-91-1-canvas",
    "S01-F10｜セルの⋯メニュー（削除）": "S01-F10-project-cell-delete-menu",
    "S02｜新規スライド（空・スライド編集メニュー）": "S02-empty-slide-editor",
    "S02｜写真1枚（自然配置・元アスペクトのまま中央）": "S02-single-photo-natural-placement",
    "S02｜コラージュ（田の字4枚の合成）": "S02-collage-four-grid",
    "S02｜枠付き（黒背景＋白フチ＋マット）": "S02-framed-black-background",
    "S02｜パノラマ（1枚が3スライドに跨る）": "S02-panorama-three-slides",
    "S02｜X組写真（タイムライン合成・左大＋右2）": "S02-x-timeline-composite",
    "S02-F09｜写真を選択（写真メニュー＋四隅ハンドル）": "S02-F09-photo-selected-menu",
    "S02-F09｜枠比率メニュー（元画像・1：1・4：5・3：4・16：9）": "S02-F09-frame-aspect-menu",
    "S02-F10｜クロップ調整モード": "S02-F10-crop-mode",
    "S02-F14｜テンプレート選択シート（型枠ビジュアル一覧）": "S02-F14-template-sheet",
    "S02-F14｜田の字を適用（空スロット4つ・グレー範囲）": "S02-F14-four-grid-empty-slots",
    "S02-F15｜レイヤー順シート（重なり順）": "S02-F15-layer-order-sheet",
    "S02-F16｜枠プリセット一覧シート": "S02-F16-frame-preset-sheet",
    "S03｜スライド一覧（俯瞰）": "S03-slide-overview",
    "S03｜スライド一覧（3スライド）": "S03-slide-overview-three-pages",
    "S03-F03｜スライドを追加（2スライドに増える）": "S03-F03-append-slide",
    "S03-F04〜F09｜カード長押しメニュー（追加・複製・移動・削除）": "S03-F04-F09-card-context-menu",
    "S03-F11｜比率メニュー（カルーセル全体の比率）": "S03-F11-carousel-ratio-menu",
    "S03-F12｜背景メニュー（プロジェクト共通の背景色）": "S03-F12-project-background-menu",
    "S04｜書き出しプレビュー画面": "S04-export-preview",
    "S04-F03｜書き出しプレビュー（各写真を個別に保存ボタン）": "S04-F03-export-preview-save-each-photo",
}


def slugify_ascii(text: str) -> str:
    normalized = unicodedata.normalize("NFKD", text)
    ascii_text = normalized.encode("ascii", "ignore").decode("ascii")
    slug = SAFE_TOKEN_RE.sub("-", ascii_text).strip("-").lower()
    return slug or "unknown"


def safe_head_token(head: str) -> str:
    return SAFE_TOKEN_RE.sub("-", head.replace("〜", "-")).strip("-") or "SCREEN"


def build_safe_stem(head: str, desc: str, snap_name: str) -> str:
    if mapped := SAFE_NAME_MAP.get(snap_name):
        return mapped
    return f"{safe_head_token(head)}-{slugify_ascii(desc)}"


def parse_entry(lang: str, device: str, snap_name: str, rel_path: str) -> dict:
    """スナップ名 `S01-F02｜説明` を画面ID・機能ID・説明に分解する。"""
    # 全角/半角の縦棒どちらでも区切れるようにする
    sep = "｜" if "｜" in snap_name else ("|" if "|" in snap_name else None)
    head, desc = (snap_name.split(sep, 1) if sep else (snap_name, ""))
    head = head.strip()
    desc = desc.strip() or snap_name
    m_screen = SCREEN_RE.match(head.strip())
    screen = m_screen.group(1) if m_screen else "その他"
    m_feat = FEATURE_RE.search(head)
    feature = m_feat.group(1) if m_feat else ""
    device_slug = slugify_ascii(device)
    lang_slug = slugify_ascii(lang)
    safe_stem = build_safe_stem(head, desc, snap_name)
    return {
        "lang": lang,
        "langSlug": lang_slug,
        "device": device,
        "deviceSlug": device_slug,
        "screen": screen,
        "screenLabel": SCREEN_LABELS.get(screen, screen),
        "feature": feature,
        "desc": desc,
        "name": snap_name,
        "sourcePath": rel_path,
        "safeStem": safe_stem,
        "path": f"{device_slug}/{lang_slug}/{safe_stem}.png",
    }


def collect(root: Path) -> list[dict]:
    entries: list[dict] = []
    for lang_dir in sorted(p for p in root.iterdir() if p.is_dir()):
        if not LANG_DIR_RE.match(lang_dir.name):
            continue
        lang = lang_dir.name
        for png in sorted(lang_dir.glob("*.png")):
            stem = png.stem  # `<端末>-<スナップ名>`
            # fastlane は端末名を先頭に付ける（例: "iPhone 16-..."）。最初の "-" で分割。
            device, _, snap_name = stem.partition("-")
            if not snap_name:  # 区切りが無いものは端末不明扱い
                device, snap_name = "", stem
            rel = f"{lang}/{png.name}"
            entries.append(parse_entry(lang, device.strip(), snap_name, rel))
    # 画面ID → 機能ID → 言語 → 端末 の順で安定ソート
    entries.sort(key=lambda e: (e["screen"], e["feature"], e["desc"], e["lang"], e["device"]))
    return entries


def mirror_safe_files(root: Path, entries: list[dict]) -> None:
    for device_slug in sorted({entry["deviceSlug"] for entry in entries}):
        generated_dir = root / device_slug
        if generated_dir.is_dir():
            shutil.rmtree(generated_dir)

    for entry in entries:
        source = root / entry["sourcePath"]
        target = root / entry["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)


HTML_TEMPLATE = """<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PhotoLayout スクリーンショット一覧</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body { margin: 0; font-family: -apple-system, "Hiragino Sans", "Noto Sans JP", sans-serif;
         background: Canvas; color: CanvasText; }
  header { position: sticky; top: 0; z-index: 10; padding: 12px 16px;
           background: color-mix(in srgb, Canvas 88%, CanvasText 4%);
           backdrop-filter: blur(8px); border-bottom: 1px solid color-mix(in srgb, CanvasText 15%, transparent); }
  h1 { font-size: 16px; margin: 0 0 8px; }
  .controls { display: flex; flex-wrap: wrap; gap: 8px 12px; align-items: center; }
  .controls label { font-size: 12px; opacity: 0.75; display: flex; gap: 4px; align-items: center; }
  select, input[type=search] { font: inherit; font-size: 13px; padding: 4px 8px;
           border-radius: 8px; border: 1px solid color-mix(in srgb, CanvasText 25%, transparent);
           background: Canvas; color: CanvasText; }
  input[type=search] { min-width: 180px; }
  .count { font-size: 12px; opacity: 0.6; margin-left: auto; }
  main { padding: 16px; }
  .screen-group { margin-bottom: 28px; }
  .screen-title { font-size: 14px; font-weight: 700; margin: 0 0 10px;
                  padding-bottom: 6px; border-bottom: 2px solid color-mix(in srgb, CanvasText 20%, transparent); }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 16px; }
  .card { border: 1px solid color-mix(in srgb, CanvasText 15%, transparent); border-radius: 12px;
          overflow: hidden; background: color-mix(in srgb, Canvas 92%, CanvasText 3%); }
  .card a { display: block; }
  .card img { width: 100%; display: block; background: #8883; aspect-ratio: 9/19.5; object-fit: contain; }
  .meta { padding: 8px 10px; }
  .tags { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 4px; }
  .tag { font-size: 10px; font-weight: 700; padding: 1px 6px; border-radius: 6px;
         background: color-mix(in srgb, CanvasText 12%, transparent); }
  .tag.screen { background: #3b82f633; color: #2563eb; }
  .tag.feature { background: #10b98133; color: #059669; }
  .desc { font-size: 12px; line-height: 1.4; }
  .sub { font-size: 10px; opacity: 0.55; margin-top: 3px; }
  .empty { opacity: 0.6; padding: 40px; text-align: center; }
</style>
</head>
<body>
<header>
  <h1>PhotoLayout スクリーンショット一覧</h1>
  <div class="controls">
    <label>言語 <select id="f-lang"></select></label>
    <label>画面 <select id="f-screen"></select></label>
    <label>端末 <select id="f-device"></select></label>
    <input id="f-text" type="search" placeholder="説明・機能IDで検索">
    <span class="count" id="count"></span>
  </div>
</header>
<main id="main"></main>
<script>
const DATA = __DATA__;
const SCREEN_LABELS = __LABELS__;

const $ = (id) => document.getElementById(id);
function uniq(vals) { return [...new Set(vals)].filter(Boolean); }

function fillSelect(el, values, allLabel, labeler) {
  el.innerHTML = '';
  const opt = document.createElement('option');
  opt.value = ''; opt.textContent = allLabel; el.appendChild(opt);
  for (const v of values) {
    const o = document.createElement('option');
    o.value = v; o.textContent = labeler ? labeler(v) : v; el.appendChild(o);
  }
}

fillSelect($('f-lang'), uniq(DATA.map(d => d.lang)).sort(), 'すべて');
fillSelect($('f-screen'), uniq(DATA.map(d => d.screen)).sort(), 'すべて',
           v => (SCREEN_LABELS[v] ? v + ' ' + SCREEN_LABELS[v] : v));
fillSelect($('f-device'), uniq(DATA.map(d => d.device)).sort(), 'すべて');

function render() {
  const lang = $('f-lang').value, screen = $('f-screen').value, device = $('f-device').value;
  const q = $('f-text').value.trim().toLowerCase();
  const rows = DATA.filter(d =>
    (!lang || d.lang === lang) &&
    (!screen || d.screen === screen) &&
    (!device || d.device === device) &&
    (!q || (d.desc + ' ' + d.feature + ' ' + d.name).toLowerCase().includes(q)));

  const main = $('main');
  main.innerHTML = '';
  $('count').textContent = rows.length + ' / ' + DATA.length + ' 枚';
  if (rows.length === 0) { main.innerHTML = '<p class="empty">該当なし</p>'; return; }

  const groups = {};
  for (const r of rows) (groups[r.screen] ||= []).push(r);
  for (const sid of Object.keys(groups).sort()) {
    const g = document.createElement('section');
    g.className = 'screen-group';
    const label = SCREEN_LABELS[sid] ? sid + ' ' + SCREEN_LABELS[sid] : sid;
    g.innerHTML = '<h2 class="screen-title">' + label + ' <span style="opacity:.5;font-weight:400">('
                  + groups[sid].length + ')</span></h2>';
    const grid = document.createElement('div');
    grid.className = 'grid';
    for (const r of groups[sid]) {
      const card = document.createElement('div');
      card.className = 'card';
      const tags = '<span class="tag screen">' + r.screen + '</span>'
                 + (r.feature ? '<span class="tag feature">' + r.feature + '</span>' : '');
      card.innerHTML =
        '<a href="' + r.path + '" target="_blank" rel="noopener"><img loading="lazy" src="' + r.path + '"></a>'
        + '<div class="meta"><div class="tags">' + tags + '</div>'
        + '<div class="desc">' + r.desc + '</div>'
        + '<div class="sub">' + r.lang + ' · ' + (r.device || '端末不明') + '</div></div>';
      grid.appendChild(card);
    }
    g.appendChild(grid);
    main.appendChild(g);
  }
}

for (const id of ['f-lang', 'f-screen', 'f-device']) $(id).addEventListener('change', render);
$('f-text').addEventListener('input', render);
render();
</script>
</body>
</html>
"""


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "fastlane/screenshots")
    if not root.is_dir():
        print(f"screenshots dir not found: {root}", file=sys.stderr)
        return 0  # CIを止めない
    entries = collect(root)
    mirror_safe_files(root, entries)
    # 説明文はHTMLに直接埋めるためエスケープ
    for e in entries:
        e["desc"] = escape(e["desc"])
        e["name"] = escape(e["name"])
    html = (HTML_TEMPLATE
            .replace("__DATA__", json.dumps(entries, ensure_ascii=False))
            .replace("__LABELS__", json.dumps(SCREEN_LABELS, ensure_ascii=False)))
    out = root / "index.html"
    # NFC 正規化して書き出す（macOSのNFDファイル名との突合を避ける）
    out.write_text(unicodedata.normalize("NFC", html), encoding="utf-8")
    print(f"wrote {out} ({len(entries)} screenshots)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
