#!/usr/bin/env python3
"""操作シナリオの描画命令JSON（Swiftが出力）をPNG＋HTMLギャラリーに起こす。

RenderPlanBuilder の [DrawCommand] はプレビューも書き出しも同一なので、ここで描くのは
「編集画面のキャンバス」であり「書き出し結果」でもある。写真はファイル名から決めたグラデーション
＋位置マーカーで代替し、配置・テンプレ・枠・クロップ・背景・スライドまたぎ等を確認する。

usage: python3 tools/render_gallery.py <commands.json> <out_dir>
"""
import sys, json, math, hashlib, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont


def photo_colors(name: str):
    h = int(hashlib.md5(name.encode()).hexdigest(), 16)
    hue = (h % 360) / 360.0
    import colorsys
    a = colorsys.hsv_to_rgb((hue) % 1.0, 0.55, 0.95)
    b = colorsys.hsv_to_rgb((hue + 0.18) % 1.0, 0.65, 0.80)
    return np.array([c * 255 for c in a]), np.array([c * 255 for c in b])


def clip_box(x, y, w, h, W, H):
    x0 = max(0, int(math.floor(x))); x1 = min(W, int(math.ceil(x + w)))
    y0 = max(0, int(math.floor(y))); y1 = min(H, int(math.ceil(y + h)))
    return x0, y0, x1, y1


def draw_fill(img, cmd, W, H):
    x, y, w, h = cmd['rect']
    x0, y0, x1, y1 = clip_box(x, y, w, h, W, H)
    if x1 <= x0 or y1 <= y0:
        return
    col = np.array(cmd['color'][:3]) * 255
    img[y0:y1, x0:x1] = col.astype(np.uint8)


def draw_image(img, cmd, W, H):
    dx, dy, dw, dh = cmd['rect']
    sx, sy, sw, sh = cmd['sourceRect']
    if dw <= 0 or dh <= 0 or sw <= 0 or sh <= 0:
        return
    cA, cB = photo_colors(cmd['photo'])
    fullW = dw / sw
    fullH = dh / sh
    gx0 = dx - sx * fullW
    gy0 = dy - sy * fullH
    x0, y0, x1, y1 = clip_box(dx, dy, dw, dh, W, H)
    if x1 <= x0 or y1 <= y0:
        return
    xs = np.arange(x0, x1)
    ys = np.arange(y0, y1)
    U = ((xs - gx0) / fullW)[None, :]           # 元画像0..1 x
    V = ((ys - gy0) / fullH)[:, None]           # 元画像0..1 y
    tt = np.clip((U + V) / 2.0, 0, 1)
    col = (1 - tt)[..., None] * cA + tt[..., None] * cB
    # 元画像内の位置マーカー（白い円）でクロップ位置を分かりやすく
    du = U - 0.70; dv = V - 0.34
    mask = (du * du + dv * dv) < (0.16 ** 2)
    mask = np.broadcast_to(mask, tt.shape)
    marker = np.array([245, 240, 236])
    col[mask] = col[mask] * 0.30 + marker * 0.70
    img[y0:y1, x0:x1] = np.clip(col, 0, 255).astype(np.uint8)


def draw_border(img, cmd, W, H):
    x, y, w, h = cmd['rect']
    lw = max(1, int(round(cmd.get('lineWidth', 1) or 1)))
    col = np.array(cmd['color'][:3]) * 255
    for (bx, by, bw, bh) in [(x, y, w, lw), (x, y + h - lw, w, lw),
                             (x, y, lw, h), (x + w - lw, y, lw, h)]:
        x0, y0, x1, y1 = clip_box(bx, by, bw, bh, W, H)
        if x1 > x0 and y1 > y0:
            img[y0:y1, x0:x1] = col.astype(np.uint8)


def draw_slot(img, cmd, W, H):
    x, y, w, h = cmd['rect']
    x0, y0, x1, y1 = clip_box(x, y, w, h, W, H)
    if x1 <= x0 or y1 <= y0:
        return
    img[y0:y1, x0:x1] = np.array([184, 184, 188], dtype=np.uint8)  # スロット範囲=グレー塗り
    draw_border(img, {'rect': [x, y, w, h], 'lineWidth': 2, 'color': [0.42, 0.55, 0.95, 1]}, W, H)


def render_page(page):
    W = max(1, int(round(page['width'])))
    H = max(1, int(round(page['height'])))
    img = np.full((H, W, 3), 40, dtype=np.uint8)  # キャンバス外=暗色（編集画面と同じ）
    for cmd in page['commands']:
        t = cmd['type']
        if t == 'fill':
            draw_fill(img, cmd, W, H)
        elif t == 'image':
            draw_image(img, cmd, W, H)
        elif t == 'border':
            draw_border(img, cmd, W, H)
        elif t == 'slot':
            draw_slot(img, cmd, W, H)
    return Image.fromarray(img, 'RGB')


def render_scenario_strip(scn, pad=10, gap=8):
    pages = [render_page(p) for p in scn['pages']]
    H = max(p.height for p in pages)
    W = sum(p.width for p in pages) + gap * (len(pages) - 1)
    strip = Image.new('RGB', (W + 2 * pad, H + 2 * pad), (28, 28, 30))
    x = pad
    for p in pages:
        strip.paste(p, (x, pad + (H - p.height) // 2))
        x += p.width + gap
    return strip


def main():
    src, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    scenarios = json.load(open(src))

    def load_font(size, bold):
        for path in ["/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
                     if bold else "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
                     "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
                     if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]:
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
        return ImageFont.load_default()
    font = load_font(20, True)
    small = load_font(14, False)

    strips = []
    for i, scn in enumerate(scenarios):
        strip = render_scenario_strip(scn)
        strips.append((scn, strip))
        strip.save(os.path.join(out_dir, f"{i:02d}.png"))

    # 1枚に縦積み（AIも1枚で全体を確認できるように）
    label_h = 46
    W = max(s.width for _, s in strips) + 24
    total_h = sum(s.height + label_h for _, s in strips) + 12
    board = Image.new('RGB', (W, total_h), (18, 18, 20))
    d = ImageDraw.Draw(board)
    y = 6
    for idx, (scn, strip) in enumerate(strips):
        d.text((12, y + 4), f"{idx:02d}  {scn['name']}", font=font, fill=(255, 255, 255))
        d.text((12, y + 26), scn['note'], font=small, fill=(170, 170, 175))
        board.paste(strip, (12, y + label_h))
        y += strip.height + label_h
    board.save(os.path.join(out_dir, "gallery.png"))

    # HTML（人間が見る用）
    rows = "".join(
        f'<figure><figcaption><b>{i:02d} {scn["name"]}</b><br><span>{scn["note"]}</span></figcaption>'
        f'<img src="{i:02d}.png"></figure>'
        for i, (scn, _) in enumerate(strips))
    html = f"""<!doctype html><meta charset=utf-8><title>操作ギャラリー</title>
<style>body{{background:#111;color:#eee;font-family:sans-serif;margin:16px}}
figure{{margin:0 0 22px;border-bottom:1px solid #333;padding-bottom:14px}}
figcaption span{{color:#aaa;font-size:13px}} img{{max-width:100%;margin-top:8px}}</style>
<h1>操作ギャラリー（画面＝書き出し結果）</h1>{rows}"""
    open(os.path.join(out_dir, "index.html"), "w").write(html)
    print(f"wrote {len(strips)} scenarios -> {out_dir}/gallery.png , index.html")


if __name__ == "__main__":
    main()
