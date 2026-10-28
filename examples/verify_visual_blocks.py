"""Independent structure checks. Usage: python examples/verify_visual_blocks.py."""
from pathlib import Path
from pypdf import PdfReader
from pypdf.generic import ContentStream

root = Path(__file__).resolve().parents[1]
reader = PdfReader(root / "output/pdf/visual-blocks.pdf", strict=True)
assert len(reader.pages) == 4
links = []
clips = 0
for page in reader.pages:
    depth = 0
    for operands, operator in ContentStream(page.get_contents(), reader).operations:
        if operator == b"q":
            depth += 1
        elif operator == b"Q":
            depth -= 1
            assert depth >= 0, "Graphics state underflow"
        elif operator in (b"W", b"W*"):
            clips += 1
    assert depth == 0, "Unbalanced graphics state"
    for reference in page.get("/Annots", []):
        annot = reference.get_object()
        if annot.get("/Subtype") == "/Link":
            x1, y1, x2, y2 = map(float, annot["/Rect"])
            assert 0 <= x1 < x2 <= float(page.mediabox.width)
            assert 0 <= y1 < y2 <= float(page.mediabox.height)
            links.append(str(annot["/A"]["/URI"]))
assert len(links) == 2
assert clips >= 3
text = "\n".join(page.extract_text() for page in reader.pages)
for expected in ["Diseña", "Conexión", "Recorte circular", "Lectura rápida"]:
    assert expected in text, expected
print(f"Verified {len(reader.pages)} pages, {len(links)} links and {clips} clips")
