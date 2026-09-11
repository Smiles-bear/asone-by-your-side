"""Normalize role-card backdrop pixels to the shared Claude warm background."""

from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ROLE_DIR = ROOT / "assets" / "generated" / "roles"
TARGET = (253, 243, 238)
ROLE_FILES = {
    "GPT": "GPT.png",
    "Claude": "Claude.png",
    "DeepSeek-clean": "DeepSeek-clean.png",
    "Gemini-clean": "Gemini-clean.png",
    "kimi": "kimi.png",
    "doubao": "doubao.png",
}


def is_backdrop(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, alpha = pixel
    if alpha == 0 or max(red, green, blue) < 210:
        return False
    if max(pixel[:3]) - min(pixel[:3]) > 38:
        return False
    return max(abs(red - TARGET[0]), abs(green - TARGET[1]), abs(blue - TARGET[2])) <= 34


def normalize(source: Path, destination: Path) -> None:
    image = Image.open(source).convert("RGBA")
    pixels = image.load()
    queue: deque[tuple[int, int]] = deque()
    visited: set[tuple[int, int]] = set()

    for x in range(image.width):
        queue.extend(((x, 0), (x, image.height - 1)))
    for y in range(1, image.height - 1):
        queue.extend(((0, y), (image.width - 1, y)))

    while queue:
        x, y = queue.popleft()
        if (x, y) in visited or not (0 <= x < image.width and 0 <= y < image.height):
            continue
        visited.add((x, y))
        if not is_backdrop(pixels[x, y]):
            continue
        _, _, _, alpha = pixels[x, y]
        pixels[x, y] = (*TARGET, alpha)
        queue.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))

    image.save(destination, "PNG")


if __name__ == "__main__":
    temp_dir = ROLE_DIR / ".normalized"
    temp_dir.mkdir(exist_ok=True)
    for output_name, input_name in ROLE_FILES.items():
        normalize(ROLE_DIR / input_name, temp_dir / f"{output_name}.png")
    print(f"normalized {len(ROLE_FILES)} role backdrops to #FDF3EE")
