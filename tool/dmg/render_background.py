"""重新生成仓库中的 Finder 安装背景，需要 Pillow 和 CJK 字体。

用法：python tool/dmg/render_background.py --font C:/Windows/Fonts/msyh.ttc
CI 使用已提交的 PNG，无需另外安装 Pillow 或字体。
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def render(font_path):
    scale = 3
    image = Image.new("RGB", (720 * scale, 460 * scale), "#fbf7f5")
    draw = ImageDraw.Draw(image)

    def text(x, y, value, size, color="#281e22", anchor="la"):
        draw.text((x * scale, y * scale), value,
                  font=ImageFont.truetype(font_path, size * scale), fill=color, anchor=anchor)

    def line(points, color="#ded2d3", width=1):
        draw.line([(x * scale, y * scale) for x, y in points], fill=color, width=width * scale)

    text(48, 32, "THMR", 32, "#970f26")
    text(672, 47, "东方音乐电台", 16, anchor="ra")
    text(48, 90, "将 THMR 拖入右侧 Applications 文件夹", 18)
    line([(48, 132), (672, 132)])
    # Finder 在 (180, 220) 和 (540, 220) 绘制可拖动的图标。
    line([(306, 220), (414, 220)], "#a91f38", 2)
    line([(401, 208), (414, 220), (401, 232)], "#a91f38", 2)
    text(360, 244, "拖拽安装", 12, "#785d65", "ma")
    line([(48, 330), (672, 330)])
    text(48, 352, "安装完成后，从 Applications 打开 THMR", 16)
    text(48, 384, "Drag THMR into Applications, then open it from there.", 13, "#785d65")
    text(48, 426, "TOUHOU MUSIC RADIO", 10, "#785d65")
    text(672, 426, "macOS · Intel / Apple Silicon", 10, "#785d65", "ra")
    image.resize((720, 460), Image.Resampling.LANCZOS).save(
        Path(__file__).with_name("background.png"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font", required=True)
    render(parser.parse_args().font)
