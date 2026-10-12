"""Иконка приложения: графит, шашечки такси, знак тенге ₸.

Рисуется геометрией (без шрифтов и картинок), поэтому чёткая в любом размере.
Пересобрать:  dart run flutter_launcher_icons && uv run --with pillow python tool/make_icon.py
(сначала иконки платформ, потом значки вкладки сайта: их launcher_icons не трогает)
"""

from pathlib import Path

from PIL import Image, ImageDraw

GRAPHITE = (13, 14, 16, 255)  # Dash.dark.bg
AMBER = (255, 184, 28, 255)  # Dash.dark.accent
APP = Path(__file__).resolve().parent.parent
OUT = APP / "assets" / "icon"
WEB = APP / "web"
SIZE = 1024
SS = 4  # суперсэмплинг для гладких краёв


def draw_mark(d: ImageDraw.ImageDraw, cx: float, top: float, scale: float) -> None:
    """Шашечки (2 ряда) и под ними ₸. Координаты в «единицах» знака, ширина знака = 8 ед."""
    u = scale
    left = cx - 4 * u
    # Шашечки: 8 × 2 клетки.
    for row in range(2):
        for col in range(8):
            if (row + col) % 2 == 0:
                x0, y0 = left + col * u, top + row * u
                d.rectangle([x0, y0, x0 + u, y0 + u], fill=AMBER)
    # ₸: две горизонтальные перекладины и стойка.
    bar_w, bar_h, gap = 6.2 * u, 0.95 * u, 0.55 * u
    stem_w, stem_h = 1.25 * u, 4.2 * u
    y = top + 2 * u + 1.0 * u
    r = 0.18 * u
    d.rounded_rectangle([cx - bar_w / 2, y, cx + bar_w / 2, y + bar_h], r, fill=AMBER)
    y2 = y + bar_h + gap
    d.rounded_rectangle([cx - bar_w / 2, y2, cx + bar_w / 2, y2 + bar_h], r, fill=AMBER)
    d.rounded_rectangle(
        [cx - stem_w / 2, y2 + bar_h - r, cx + stem_w / 2, y2 + stem_h], r, fill=AMBER
    )


def render(scale_units: float, background: tuple[int, int, int, int]) -> Image.Image:
    big = SIZE * SS
    img = Image.new("RGBA", (big, big), background)
    d = ImageDraw.Draw(img)
    u = big * scale_units / 8  # ширина знака = scale_units от стороны
    total_h = 2 * u + 1.0 * u + 0.95 * u + 0.55 * u + 4.2 * u
    draw_mark(d, big / 2, (big - total_h) / 2, u)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def favicon_svg() -> str:
    """Значок вкладки в векторе: чёткий на любом экране (Chrome, Firefox, Edge).

    Для крошечного размера рисунок упрощён: одна полоса шашечек из 4 клеток
    и крупный ₸ на скруглённом графитовом квадрате.
    """
    a = "#FFB81C"
    cells = "".join(
        f'<rect x="{6 + i * 5}" y="5" width="5" height="5" fill="{a}"/>' for i in (0, 2)
    ) + "".join(f'<rect x="{6 + i * 5}" y="10" width="5" height="5" fill="{a}"/>' for i in (1, 3))
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">'
        '<rect width="32" height="32" rx="7" fill="#0D0E10"/>'
        f"{cells}"
        f'<rect x="7" y="17" width="18" height="2.6" rx=".6" fill="{a}"/>'
        f'<rect x="7" y="21" width="18" height="2.6" rx=".6" fill="{a}"/>'
        f'<rect x="14.2" y="22" width="3.6" height="7" rx=".6" fill="{a}"/>'
        "</svg>\n"
    )


def favicon_raster(size: int) -> Image.Image:
    """Растровый значок для .ico (Safari и старые браузеры запрашивают /favicon.ico)."""
    big = size * 8
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = big / 32  # те же координаты, что в SVG (сетка 32×32)
    d.rounded_rectangle([0, 0, big - 1, big - 1], 7 * k, fill=GRAPHITE)
    if size >= 32:  # на 16 px шашечки не читаются — только ₸, но крупнее
        for col, row in ((0, 0), (2, 0), (1, 1), (3, 1)):
            x, y = (6 + col * 5) * k, (5 + row * 5) * k
            d.rectangle([x, y, x + 5 * k, y + 5 * k], fill=AMBER)
        bars = [(7, 17, 18, 2.6), (7, 21, 18, 2.6), (14.2, 22, 3.6, 7)]
    else:
        bars = [(5, 5, 22, 4.5), (5, 13, 22, 4.5), (12.5, 14, 7, 14)]
    for x, y, w, h in bars:
        d.rounded_rectangle([x * k, y * k, (x + w) * k, (y + h) * k], 0.6 * k, fill=AMBER)
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    # Обычная иконка (iOS, веб, старый Android). Знак на 54% ширины: так он
    # целиком помещается и в круг «маскируемой» веб-иконки (безопасная зона — 80%).
    render(0.54, GRAPHITE).convert("RGB").save(OUT / "icon.png")
    # Адаптивная иконка Android: прозрачный передний план. flutter_launcher_icons
    # сам добавляет отступ 16%, поэтому здесь знак крупнее — в итоге он
    # укладывается в безопасный круг 66 dp из 108 dp.
    render(0.58, (0, 0, 0, 0)).save(OUT / "icon_foreground.png")
    # Значки вкладки сайта.
    (WEB / "favicon.svg").write_text(favicon_svg(), encoding="utf-8")
    ico = favicon_raster(48)
    ico.save(WEB / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)],
             append_images=[favicon_raster(16), favicon_raster(32)])
    favicon_raster(32).save(WEB / "favicon.png")
    print("готово:", *sorted(p.name for p in OUT.glob("*.png")), "+ web/favicon.{svg,ico,png}")


if __name__ == "__main__":
    main()
