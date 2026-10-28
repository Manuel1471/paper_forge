"""Independent checks after `mix run examples/lumen_visual_2026.exs` (pypdf)."""
import sys
from pathlib import Path
from pypdf import PdfReader

path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / 'output/pdf/lumen-visual-2026.pdf'
pdf = PdfReader(path, strict=True)
fields = pdf.get_fields()
expected = {'revisor_ñ': 'Lucía Peña', 'área': 'Operación y diseño',
            'presupuesto_€': '€ 125,000', 'país': 'MX',
            'estado': '/aprobado', 'confirmación': '/Yes'}
assert len(pdf.pages) == 8
assert len(fields) == 7
assert pdf.metadata.title == 'Lumen · Diseño, información y revisión'
for name, value in expected.items():
    assert fields[name]['/V'] == value, (name, fields[name])
widgets = [ref.get_object() for ref in pdf.pages[6]['/Annots']
           if ref.get_object()['/Subtype'] == '/Widget']
assert len(widgets) == 8
for widget in widgets:
    owner = widget.get('/Parent', widget)
    if hasattr(owner, 'get_object'):
        owner = owner.get_object()
    assert owner['/T'] in fields
    assert owner.get('/V') == fields[owner['/T']].get('/V')
    appearance = widget['/AP']['/N']
    if '/AS' in widget:
        appearance = appearance[widget['/AS']]
    assert appearance.get_data()
    x1, y1, x2, y2 = widget['/Rect']
    assert 52 <= x1 < x2 <= 543 and 62 <= y1 < y2 <= 788
    assert y2 - y1 <= 28, "Compact/comfortable widgets must not become oversized"
for n, page in enumerate(pdf.pages, 1):
    assert f'{n} / 8' in page.extract_text()
    assert '�' not in page.extract_text()
assert any('Método visible' in item.title for item in pdf.outline if not isinstance(item, list))
assert 'página 5' in pdf.pages[4].extract_text()
assert fields['firma']['/FT'] == '/Sig' and '/V' not in fields['firma']
print('Lumen: 8 pages, 7 fields, 8 widget appearances and Unicode/navigation verified.')
