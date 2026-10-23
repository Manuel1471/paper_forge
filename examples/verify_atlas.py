"""Independent readback checks. Run after the Elixir generator; requires pypdf."""
import json
import re
import sys
from pathlib import Path
import pypdf

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "output/pdf/atlas-2026"
expected = json.loads((root / "verification.json").read_text())
reader = pypdf.PdfReader(root / "atlas-2026-report.pdf", strict=True)
texts = [page.extract_text() for page in reader.pages]
all_text = "\n".join(texts)
route_ids = re.findall(r"^AT-\d{3}\b", all_text, re.MULTILINE)
outline_titles = [item.title for item in reader.outline]
checks = {
    "outline_titles_match_source": outline_titles == expected["chapter_titles"],
    "page_count": len(reader.pages) == expected["pages"],
    "all_route_ids_once_in_order": route_ids == [f"AT-{i:03}" for i in range(1, 121)],
    "spanish_accents_preserved": all(word in all_text for word in ["más", "LOGÍSTICA", "Información", "Mérida", "Querétaro", "Metodología"]),
    "no_utf8_mojibake": not any(word in all_text for word in ["Ã¡", "Ã³", "Ã©", "Ã±", "�"]),
    "dataset_attachment_matches": json.loads(reader.attachments["atlas-routes.json"][0]) == json.loads((root / "routes.json").read_text()),
    "chapter_destinations_match_layout": all(reader.get_destination_page_number(reader.named_destinations[name]) + 1 == page for name, page in expected["chapter_destinations"].items()),
    "page_footers_match_physical_pages": all(re.search(rf"\b0?{n} / {len(texts)}\b", text) for n, text in enumerate(texts, 1) if n > 1),
    "table_headers_repeat": all("Corredor Origen / destino Viajes Puntualidad Distancia" in texts[n-1] for n in expected["route_table_pages"]),
}
extract = pypdf.PdfReader(root / "atlas-2026-extract.pdf", strict=True)
checks.update({
    "extract_has_four_pages": len(extract.pages) == 4,
    "rotation_preserved": extract.pages[3].rotation == 90,
    "watermark_present_on_each_extracted_page": all("DEMO / REVIEW COPY" in p.extract_text() for p in extract.pages),
    "updated_metadata": extract.metadata.title == "Atlas 2026 - reviewed extract",
})
result = {"reader": f"pypdf {pypdf.__version__}", "checks": checks}
(root / "independent-verification.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
failed = [name for name, passed in checks.items() if not passed]
if failed:
    raise SystemExit("FAILED: " + ", ".join(failed))
print(f"Independent readback: {len(checks)} checks passed across {len(texts)} pages.")
