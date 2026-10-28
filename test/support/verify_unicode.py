"""Independent QA: run after mix run test/support/unicode_review.exs (pypdf required)."""
import json
from pathlib import Path
from pypdf import PdfReader

root = Path(__file__).resolve().parents[2] / "output/pdf/unicode-review"
text = "Niñez — € “México” 日本語 🚚"
pdf = PdfReader(root / "interactive.pdf", strict=True)
fields = pdf.get_fields()
annotations = [ref.get_object() for ref in pdf.pages[0]["/Annots"]]
stamp = next(a for a in annotations if a["/Subtype"] == "/Stamp")
file_note = next(a for a in annotations if a["/Subtype"] == "/FileAttachment")
spec = file_note["/FS"]
flat = PdfReader(root / "flattened.pdf", strict=True)
flat_text = flat.pages[0].extract_text()
checks = {
    "metadata_title": pdf.metadata.title == text,
    "metadata_author": pdf.metadata.author == "Peña",
    "metadata_nbsp": pdf.metadata.subject == "a\u00a0b",
    "outline": pdf.outline[0].title == text,
    "attachment_name_and_data": pdf.attachments[text + ".txt"][0] == b"document payload",
    "file_annotation_unicode": spec["/UF"] == text + ".txt" and spec["/Desc"] == text,
    "file_annotation_payload": spec["/EF"]["/UF"].get_data() == b"annotation payload",
    "file_annotation_mime": spec["/EF"]["/UF"]["/Subtype"] == "/text/plain",
    "annotation_strings": all(stamp[k] == text for k in ["/T", "/Subj", "/Contents"]),
    "field_name_value_tooltip_default": fields[text]["/V"] == "Peña € “sí”" and fields[text]["/TU"] == text and fields[text]["/DV"] == "España",
    "unicode_field_value": fields["日本語"]["/V"] == "Ж Ω Ω",
    "choice_strings": fields["país"]["/Opt"] == [["MX", "México"], ["ES", "España"]] and fields["país"]["/V"] == "ES",
    "flatten_removed_form": not flat.get_fields(),
    "flatten_removed_all_widgets": all(ref.get_object()["/Subtype"] != "/Widget" for ref in flat.pages[0]["/Annots"]),
    "flatten_preserved_other_annotations": len(flat.pages[0]["/Annots"]) == 3,
    "flatten_updated_text": "Peña € “sí”" in flat_text and "OLD VALUE" not in flat_text,
    "flatten_unicode_appearance": "Ж Ω Ω" in flat_text,
    "flatten_choice_display_label": "España" in flat_text,
    "no_off_label_painted": "Off" not in flat_text,
}
(root / "verification.json").write_text(json.dumps(checks, indent=2) + "\n")
failed = [name for name, ok in checks.items() if not ok]
assert not failed, failed
print(f"{len(checks)} independent Unicode/form checks passed")
