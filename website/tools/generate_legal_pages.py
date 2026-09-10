"""Generate static legal HTML pages from the approved DOCX source files."""

from __future__ import annotations

from html import escape
from pathlib import Path
import re
from zipfile import ZipFile
import xml.etree.ElementTree as ET


PROJECT_ROOT = Path(__file__).resolve().parents[2]
WEBSITE_ROOT = PROJECT_ROOT / "website"
SOURCE_ROOT = PROJECT_ROOT / "隐私政策用户协议"
OUTPUT_ROOT = WEBSITE_ROOT / "legal"
WORD_NAMESPACE = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"

PAGES = {
    "privacy": "Azruiyoi_隐私政策_V1.0_20260819.docx",
    "terms": "Azruiyoi_用户协议_V1.0_20260819.docx",
    "minors": "Azruiyoi_未成年人个人信息保护规则_V1.0_20260819.docx",
}

SECTION_PATTERN = re.compile(r"^[一二三四五六七八九十百]+、")


def paragraphs_from_docx(path: Path) -> list[str]:
    with ZipFile(path) as archive:
        root = ET.fromstring(archive.read("word/document.xml"))

    paragraphs: list[str] = []
    for paragraph in root.iter(WORD_NAMESPACE + "p"):
        text = "".join(
            node.text or "" for node in paragraph.iter(WORD_NAMESPACE + "t")
        ).strip()
        if text:
            paragraphs.append(text)
    return paragraphs


def extract_metadata(paragraphs: list[str]) -> tuple[list[tuple[str, str]], list[str]]:
    labels = {"运营者", "联系邮箱", "生效日期"}
    metadata: list[tuple[str, str]] = []
    content: list[str] = []
    index = 1

    if index < len(paragraphs) and paragraphs[index].startswith(("版本", "适用于")):
        version = paragraphs[index]
        if "·" in version:
            audience, version_number = [item.strip() for item in version.split("·", 1)]
            metadata.append(("适用范围", audience))
            metadata.append(("版本", version_number.removeprefix("版本 ")))
        else:
            metadata.append(("版本", version.split("：", 1)[-1]))
        index += 1

    while index < len(paragraphs):
        label = paragraphs[index]
        if label not in labels or index + 1 >= len(paragraphs):
            break
        metadata.append((label, paragraphs[index + 1]))
        index += 2

    content.extend(paragraphs[index:])
    return metadata, content


def metadata_html(items: list[tuple[str, str]]) -> str:
    rows = []
    for label, value in items:
        rendered_value = escape(value)
        if label == "联系邮箱":
            rendered_value = f'<a href="mailto:{rendered_value}">{rendered_value}</a>'
        rows.append(f"<div><dt>{escape(label)}</dt><dd>{rendered_value}</dd></div>")
    return "<dl class=\"legal-meta\">" + "".join(rows) + "</dl>"


def body_html(paragraphs: list[str]) -> str:
    rendered: list[str] = []
    for index, text in enumerate(paragraphs):
        safe_text = escape(text)
        if SECTION_PATTERN.match(text):
            rendered.append(f"<h2>{safe_text}</h2>")
        elif index == 0:
            rendered.append(f'<p class="legal-intro">{safe_text}</p>')
        else:
            rendered.append(f"<p>{safe_text}</p>")
    return "\n".join(rendered)


def page_html(title: str, metadata: list[tuple[str, str]], body: list[str]) -> str:
    clean_title = title.strip("《》")
    return f"""<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="theme-color" content="#FAF8F4">
    <meta name="description" content="{escape(clean_title)}">
    <title>{escape(clean_title)}｜Azruiyoi</title>
    <link rel="icon" href="../assets/azruiyoi-brand/app-icon.png">
    <link rel="stylesheet" href="../assets/site.css">
    <script src="../assets/site.js" defer></script>
  </head>
  <body class="legal-page">
    <a class="skip-link" href="#main">跳到主要内容</a>
    <header class="site-header" data-header>
      <div class="nav-shell">
        <a class="brand" href="../index.html" aria-label="返回 Azruiyoi 首页">
          <img src="../assets/azruiyoi-brand/logo.svg" alt="Azruiyoi">
        </a>
      </div>
    </header>
    <main class="legal-main" id="main">
      <article class="legal-article">
        <a class="legal-back" href="../index.html#privacy">← 返回官网</a>
        <h1>{escape(clean_title)}</h1>
        {metadata_html(metadata)}
        {body_html(body)}
      </article>
    </main>
    <footer class="site-footer">
      <div class="footer-shell">
        <div class="footer-brand">
          <img src="../assets/azruiyoi-brand/logo.svg" alt="Azruiyoi">
          <p>京山市如一软件科技有限公司</p>
        </div>
        <nav class="footer-links" aria-label="法律与联系">
          <a href="privacy.html">隐私政策</a>
          <a href="terms.html">用户协议</a>
          <a href="minors.html">未成年人保护规则</a>
          <a href="mailto:851591039@qq.com">联系我们</a>
        </nav>
        <p class="copyright">© <span data-year>2026</span> Azruiyoi</p>
      </div>
    </footer>
  </body>
</html>
"""


def main() -> None:
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    for slug, filename in PAGES.items():
        paragraphs = paragraphs_from_docx(SOURCE_ROOT / filename)
        title = paragraphs[0]
        metadata, body = extract_metadata(paragraphs)
        (OUTPUT_ROOT / f"{slug}.html").write_text(
            page_html(title, metadata, body), encoding="utf-8", newline="\n"
        )


if __name__ == "__main__":
    main()
