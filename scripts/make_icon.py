#!/usr/bin/env python3
"""生成 MacTemp 的 App 图标（1024@2x 主图 -> iconset）。

用法：make_icon.py <输出目录.iconset>
依赖：系统 Python3 自带的 Pillow。
视觉：深色圆角方块 + 青蓝/橙色渐变液柱温度计 + 玻璃高光，符合 macOS 图标规范。
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

SIZE = 2048          # 超采样母版
MARGIN = 108         # 内容留边（1024 画布约 54pt）
RADIUS = 430


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def rounded_mask(size, box, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def multi_gradient(size, stops, y_start, y_end):
    """stops: [(position 0..1, color), ...]，生成竖直多段渐变。"""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    span = max(1, y_end - y_start)
    stops = sorted(stops, key=lambda item: item[0])
    for y in range(y_start, y_end):
        t = (y - y_start) / span
        left = stops[0]
        right = stops[-1]
        for i in range(len(stops) - 1):
            if stops[i][0] <= t <= stops[i + 1][0]:
                left, right = stops[i], stops[i + 1]
                break
        local = 0.0 if right[0] == left[0] else (t - left[0]) / (right[0] - left[0])
        d.line([(0, y), (size, y)], fill=lerp(left[1], right[1], local))
    return img


def vertical_gradient(size, top_color, bottom_color, y_start, y_end):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    span = max(1, y_end - y_start)
    for y in range(y_start, y_end):
        t = (y - y_start) / span
        d.line([(0, y), (size, y)], fill=lerp(top_color, bottom_color, t))
    return img


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.iconset"
    os.makedirs(out_dir, exist_ok=True)

    box = (MARGIN, MARGIN, SIZE - MARGIN, SIZE - MARGIN)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # ---- 背景：深色渐变 + 两处柔光 ----
    bg = vertical_gradient(SIZE, (30, 40, 61, 255), (7, 10, 17, 255), 0, SIZE)
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([-520, -760, 1280, 980], fill=(54, 209, 220, 110))
    gd.ellipse([980, 1120, 2500, 2560], fill=(91, 134, 229, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(230))
    bg.alpha_composite(glow)

    edge = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(box, radius=RADIUS, outline=(150, 235, 255, 95), width=5)
    bg.alpha_composite(edge)
    canvas.paste(bg, (0, 0), rounded_mask(SIZE, box, RADIUS))

    # ---- 温度计几何 ----
    cx = SIZE // 2
    stem_w = 232
    stem_top = 430
    stem_bottom = 1250
    bulb_r = 292
    bulb_cy = 1470
    inner_w = 108
    level_y = stem_top + int((bulb_cy - bulb_r - stem_top) * 0.38)

    # ---- 玻璃外壳（亮色，带竖向渐变）----
    glass_mask = Image.new("L", (SIZE, SIZE), 0)
    gm = ImageDraw.Draw(glass_mask)
    gm.rounded_rectangle(
        [cx - stem_w // 2, stem_top, cx + stem_w // 2, stem_bottom],
        radius=stem_w // 2, fill=255,
    )
    gm.ellipse([cx - bulb_r, bulb_cy - bulb_r, cx + bulb_r, bulb_cy + bulb_r], fill=255)
    glass = vertical_gradient(SIZE, (242, 253, 255, 255), (116, 211, 255, 255), stem_top, bulb_cy + bulb_r)
    glass.putalpha(glass_mask)

    # ---- 内腔（深色玻璃）----
    cavity_mask = Image.new("L", (SIZE, SIZE), 0)
    cm = ImageDraw.Draw(cavity_mask)
    cm.rounded_rectangle(
        [cx - inner_w // 2, stem_top + 66, cx + inner_w // 2, stem_bottom + 40],
        radius=inner_w // 2, fill=255,
    )
    cm.ellipse(
        [cx - bulb_r + 66, bulb_cy - bulb_r + 66, cx + bulb_r - 66, bulb_cy + bulb_r - 66],
        fill=255,
    )
    cavity = vertical_gradient(SIZE, (13, 18, 27, 255), (7, 10, 16, 255), stem_top, bulb_cy + bulb_r)
    cavity.putalpha(cavity_mask)

    # ---- 液柱：青蓝 -> 橙红 渐变，填充内腔下部 ----
    liquid_mask = Image.new("L", (SIZE, SIZE), 0)
    lm = ImageDraw.Draw(liquid_mask)
    lm.rounded_rectangle(
        [cx - inner_w // 2, level_y, cx + inner_w // 2, stem_bottom + 40],
        radius=inner_w // 2, fill=255,
    )
    lm.ellipse(
        [cx - bulb_r + 66, bulb_cy - bulb_r + 66, cx + bulb_r - 66, bulb_cy + bulb_r - 66],
        fill=255,
    )
    liquid = multi_gradient(
        SIZE,
        [
            (0.00, (96, 238, 255, 255)),    # 液面：冰蓝
            (0.30, (86, 224, 196, 255)),    # 青绿
            (0.62, (255, 205, 92, 255)),    # 暖黄
            (1.00, (255, 104, 68, 255)),    # 球泡：橙红
        ],
        level_y, bulb_cy + bulb_r - 66,
    )
    liquid.putalpha(liquid_mask)

    # 液面高光
    surface = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(surface)
    sd.ellipse([cx - inner_w // 2, level_y - 8, cx + inner_w // 2, level_y + 26], fill=(215, 255, 255, 150))
    surface = surface.filter(ImageFilter.GaussianBlur(6))

    # 球泡高光
    specular = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sp = ImageDraw.Draw(specular)
    sp.ellipse([cx - 118, bulb_cy - 132, cx - 34, bulb_cy - 48], fill=(255, 235, 222, 105))
    specular = specular.filter(ImageFilter.GaussianBlur(18))

    # 玻璃竖向高光
    highlight = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    hd = ImageDraw.Draw(highlight)
    hd.rounded_rectangle(
        [cx - stem_w // 2 + 40, stem_top + 52, cx - stem_w // 2 + 88, stem_bottom - 210],
        radius=24, fill=(255, 255, 255, 120),
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(12))

    # ---- 合成 ----
    canvas.alpha_composite(glass)
    canvas.alpha_composite(cavity)
    canvas.alpha_composite(liquid)
    canvas.alpha_composite(surface)
    canvas.alpha_composite(specular)
    canvas.alpha_composite(highlight)

    # 刻度线
    ticks = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    td = ImageDraw.Draw(ticks)
    for i in range(6):
        y = stem_top + 168 + i * 145
        length = 76 if i % 2 == 0 else 50
        td.rounded_rectangle(
            [cx + stem_w // 2 + 66, y, cx + stem_w // 2 + 66 + length, y + 17],
            radius=8, fill=(190, 235, 255, 170),
        )
    canvas.alpha_composite(ticks)

    # ---- 导出 iconset ----
    names = {
        16: ["icon_16x16.png", "icon_16x16@2x.png"],
        32: ["icon_32x32.png", "icon_32x32@2x.png"],
        128: ["icon_128x128.png", "icon_128x128@2x.png"],
        256: ["icon_256x256.png", "icon_256x256@2x.png"],
        512: ["icon_512x512.png", "icon_512x512@2x.png"],
    }
    master = canvas.resize((1024, 1024), Image.LANCZOS)
    for base, filenames in names.items():
        for name in filenames:
            target = base * (2 if "@2x" in name else 1)
            master.resize((target, target), Image.LANCZOS).save(os.path.join(out_dir, name))
    master.save(os.path.join(out_dir, "icon_1024.png"))
    print(f"icon written: {out_dir} ({len(os.listdir(out_dir))} files)")


if __name__ == "__main__":
    main()
