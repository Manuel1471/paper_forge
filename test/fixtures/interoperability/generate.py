"""Regenerate owned interoperability fixtures; QA-only pikepdf and pypdf dependencies.
Generated with pikepdf 9.11.0 (libqpdf) and pypdf 6.21.2. No third-party documents.
"""
from pathlib import Path
import pikepdf
from pypdf import PdfWriter

root = Path(__file__).parent
pdf = pikepdf.Pdf.new()
font = pdf.make_indirect(pikepdf.Dictionary(Type=pikepdf.Name.Font, Subtype=pikepdf.Name.Type1, BaseFont=pikepdf.Name.Helvetica))
for number in range(1, 3):
    page = pdf.add_blank_page(page_size=(300, 400))
    page.Resources = pikepdf.Dictionary(Font=pikepdf.Dictionary(F1=font))
    page.Contents = pdf.make_stream(f"BT /F1 16 Tf 30 350 Td (Independent page {number}) Tj ET".encode())
pdf.docinfo.Title = "Independent fixture"
pdf.docinfo.Author = "PaperForge tests"
pdf.save(root / "classic.pdf", object_stream_mode=pikepdf.ObjectStreamMode.disable, deterministic_id=True)
pdf.save(root / "object-streams.pdf", object_stream_mode=pikepdf.ObjectStreamMode.generate, deterministic_id=True)
pdf.save(root / "linearized.pdf", linearize=True)
pdf.save(root / "aes256.pdf", object_stream_mode=pikepdf.ObjectStreamMode.generate, encryption=pikepdf.Encryption(owner="owner", user="reader", R=6))
pdf.save(root / "unsupported-aes128.pdf", encryption=pikepdf.Encryption(owner="owner", user="reader", R=4))
writer = PdfWriter(str(root / "classic.pdf"), incremental=True)
writer.add_metadata({"/Title": "Incrementally reviewed"})
writer.write(str(root / "incremental.pdf"))
