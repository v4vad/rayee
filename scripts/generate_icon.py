#!/usr/bin/env python3
"""Generate Rayee app icon with gradient and waveform design."""

import math
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Pillow not installed. Installing...")
    import subprocess
    subprocess.check_call(["pip", "install", "Pillow"])
    from PIL import Image, ImageDraw


def create_gradient(size: int) -> Image.Image:
    """Create a purple-to-blue diagonal gradient."""
    img = Image.new("RGBA", (size, size))

    # Gradient colors (purple to teal/cyan)
    start_color = (138, 43, 226)   # Purple/violet
    end_color = (0, 191, 255)      # Deep sky blue

    for y in range(size):
        for x in range(size):
            # Diagonal gradient based on position
            ratio = (x + y) / (2 * size)
            r = int(start_color[0] + (end_color[0] - start_color[0]) * ratio)
            g = int(start_color[1] + (end_color[1] - start_color[1]) * ratio)
            b = int(start_color[2] + (end_color[2] - start_color[2]) * ratio)
            img.putpixel((x, y), (r, g, b, 255))

    return img


def draw_rounded_rect(draw: ImageDraw.Draw, bounds: tuple, radius: int, fill: tuple):
    """Draw a rounded rectangle."""
    x1, y1, x2, y2 = bounds

    # Draw the main rectangles
    draw.rectangle([x1 + radius, y1, x2 - radius, y2], fill=fill)
    draw.rectangle([x1, y1 + radius, x2, y2 - radius], fill=fill)

    # Draw the four corners as circles
    draw.ellipse([x1, y1, x1 + 2*radius, y1 + 2*radius], fill=fill)
    draw.ellipse([x2 - 2*radius, y1, x2, y1 + 2*radius], fill=fill)
    draw.ellipse([x1, y2 - 2*radius, x1 + 2*radius, y2], fill=fill)
    draw.ellipse([x2 - 2*radius, y2 - 2*radius, x2, y2], fill=fill)


def draw_waveform(draw: ImageDraw.Draw, size: int):
    """Draw a stylized audio waveform in the center."""
    center_y = size // 2
    center_x = size // 2

    # Waveform bar settings
    num_bars = 5
    bar_width = size // 16
    bar_gap = size // 12
    max_height = size * 0.5

    # Heights for each bar (creates a classic waveform shape)
    heights = [0.4, 0.7, 1.0, 0.7, 0.4]

    total_width = num_bars * bar_width + (num_bars - 1) * bar_gap
    start_x = center_x - total_width // 2

    for i, height_ratio in enumerate(heights):
        bar_height = int(max_height * height_ratio)
        x = start_x + i * (bar_width + bar_gap)
        y1 = center_y - bar_height // 2
        y2 = center_y + bar_height // 2

        # Draw rounded bar
        radius = bar_width // 2
        draw_rounded_rect(
            draw,
            (x, y1, x + bar_width, y2),
            radius,
            (255, 255, 255, 230)  # White with slight transparency
        )


def create_icon(size: int) -> Image.Image:
    """Create the complete app icon at the given size."""
    # Create gradient background
    img = create_gradient(size)

    # Apply rounded corners (macOS style)
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    corner_radius = size // 5  # macOS uses ~22% corner radius
    draw_rounded_rect(mask_draw, (0, 0, size, size), corner_radius, 255)

    # Apply the mask
    output = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    output.paste(img, mask=mask)

    # Draw waveform
    draw = ImageDraw.Draw(output)
    draw_waveform(draw, size)

    return output


def main():
    # Output directory
    output_dir = Path(__file__).parent.parent / "swift/Rayee/Rayee/Assets.xcassets/AppIcon.appiconset"
    output_dir.mkdir(parents=True, exist_ok=True)

    # Generate icons at all required sizes
    sizes = [16, 32, 64, 128, 256, 512, 1024]

    for size in sizes:
        print(f"Generating {size}x{size} icon...")
        icon = create_icon(size)
        icon.save(output_dir / f"icon_{size}.png", "PNG")

    print(f"\nIcons saved to: {output_dir}")
    print("Done! Rebuild the Xcode project to see the new icon.")


if __name__ == "__main__":
    main()
