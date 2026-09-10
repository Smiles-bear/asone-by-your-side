"""Run dependency-free structural checks for the static website."""

from __future__ import annotations

from html.parser import HTMLParser
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit


WEBSITE_ROOT = Path(__file__).resolve().parents[1]


class SiteParser(HTMLParser):
    def __init__(self, page: Path) -> None:
        super().__init__()
        self.page = page
        self.references: list[str] = []
        self.ids: set[str] = set()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if values.get("id"):
            self.ids.add(values["id"] or "")
        for name in ("href", "src"):
            if values.get(name):
                self.references.append(values[name] or "")


def main() -> None:
    errors: list[str] = []
    pages = list(WEBSITE_ROOT.rglob("*.html"))
    parsed: dict[Path, SiteParser] = {}

    for page in pages:
        parser = SiteParser(page)
        parser.feed(page.read_text(encoding="utf-8"))
        parsed[page.resolve()] = parser

    for page, parser in parsed.items():
        for reference in parser.references:
            parts = urlsplit(reference)
            if parts.scheme or parts.netloc or reference.startswith("mailto:"):
                continue

            target = (page.parent / parts.path).resolve() if parts.path else page
            if parts.path and not target.exists():
                errors.append(
                    f"{page.relative_to(WEBSITE_ROOT)} references missing {reference}"
                )
                continue

            if parts.fragment and target.suffix.lower() == ".html":
                target_parser = parsed.get(target)
                if target_parser and parts.fragment not in target_parser.ids:
                    errors.append(
                        f"{page.relative_to(WEBSITE_ROOT)} references missing anchor {reference}"
                    )

    css = (WEBSITE_ROOT / "assets" / "site.css").read_text(encoding="utf-8")
    if css.count("{") != css.count("}"):
        errors.append("CSS brace count does not match")

    js = (WEBSITE_ROOT / "assets" / "site.js").read_text(encoding="utf-8")
    if "scrollIntoView" in js:
        errors.append("site.js contains forbidden scrollIntoView")

    if re.search(r"<img(?![^>]*\balt=)", (WEBSITE_ROOT / "index.html").read_text(encoding="utf-8")):
        errors.append("Homepage contains an image without alt text")

    if errors:
        print("static checks: FAIL")
        print("\n".join(errors))
        sys.exit(1)

    print(f"static checks: PASS ({len(pages)} HTML pages)")


if __name__ == "__main__":
    main()
