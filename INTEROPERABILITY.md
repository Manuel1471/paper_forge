# PDF Interoperability And Transformation

PaperForge 1.5.0 adds an existing-document workflow alongside PDF authoring:

```text
Existing PDF → object graph → analysis or transformation → PDF
```

The runtime is pure Elixir/OTP. The parser uses cross-reference entries and
stream lengths, rather than scanning binary stream contents for object markers.
It is a strict reader for the supported structures, not a general PDF repair tool.

## Open And Inspect

```elixir
{:ok, pdf} = PaperForge.open("contract.pdf")
# For supported encrypted input:
# {:ok, pdf} = PaperForge.open("contract.pdf", password: "reader")

PaperForge.page_count(pdf)
PaperForge.metadata(pdf)
PaperForge.forms(pdf)
PaperForge.annotations(pdf)
PaperForge.attachments(pdf)
PaperForge.outlines(pdf)
PaperForge.signatures(pdf)
{:ok, analysis} = PaperForge.analyze(pdf)
```

`open/2` reads a path and returns `{:ok, %PaperForge.Document{}}` or
`{:error, reason}`. `open!/2` raises `ArgumentError` on failure. To read bytes,
use `PaperForge.Interoperability.parse_pdf/2` with the same parser options.

The graph stores the active object generation selected by the newest xref entry.
A newer free entry masks the previous object. `/Prev` chains supply older entries
and missing trailer keys; `/XRefStm` supplies hybrid entries. Historical object
bodies are not exposed as editable snapshots. `PDF.Graph.resolve/2` checks both
object number and generation and returns an error for stale or missing references.

Inspection functions return values directly and raise `ArgumentError` for invalid
feature structures. `analyze/1` returns a result tuple and records malformed page
or feature trees in `issues` where possible:

| Function | Result |
| --- | --- |
| `page_count/1` | Number of leaf pages, traversing nested page trees |
| `metadata/1` | Info dictionary, with PDF string keys and original PDF values |
| `forms/1` | AcroForm fields, qualified names and inherited field properties |
| `annotations/1` | Annotation dictionaries and one-based page numbers |
| `attachments/1` | EmbeddedFiles name-tree entries and file specifications |
| `outlines/1` | Outline hierarchy with titles, dictionaries and children |
| `signatures/1` | Signature dictionaries with `verification: :not_performed` |

This is a structural inventory: it does not execute actions or JavaScript,
render XFA, extract attachment files onto disk, or verify digital signatures.
Names and ordinary PDF dictionaries retain string keys, avoiding input atoms.
Metadata strings may be binaries or `{:hex_string, bytes}`; metadata inspection
currently returns Info, not a merged interpretation of Info and XMP.

## Analysis

The report includes PDF version, file size, xref offsets and section history,
page and active-object counts, compressed-object count, incremental revisions,
fonts, images, exact duplicate resources, broken references, orphaned objects,
forms, annotations, attachments, outlines, signatures, encryption revision,
permissions, tagged-PDF markers and normalization opportunities.

`cross_reference_type` is `:table`, `:stream`, `:hybrid`, `:mixed`, or `:generated`.
`:mixed` means a revision chain uses both tables and streams; `:hybrid` means an
xref table actually references a supplementary `/XRefStm`. The two initial xref
sections of a linearized file are not counted as an incremental edit.

Source structure describes the opened file; it is not recomputed after in-memory
edits. Reopen the written output to analyze its new file structure. The `revisions`
list records xref sections, newest first, including their trailers. Duplicate
resource detection compares exact object values, not rendered visual equivalence.
Orphaned objects can include structural streams and linearization hints that are
not reachable from the catalog or Info dictionary. Tagged-PDF information is not
PDF/UA conformance certification. Permission flags are reported, not enforced as
an application authorization policy.

## Command-Line Inspector

```sh
mix paper_forge.inspect document.pdf
mix paper_forge.inspect document.pdf --json
mix paper_forge.inspect document.pdf --password-env PDF_PASSWORD
```

The last command reads the password from an existing environment variable. It
does not print the password. JSON represents references as object ID/generation
pairs and non-UTF-8 values as Base64. The inspector does not modify its input.

## Transform Existing Pages

```elixir
"input.pdf"
|> PaperForge.open!()
|> PaperForge.delete_pages(10..15)
|> PaperForge.rotate_pages([2, 3], 90)
|> PaperForge.add_watermark("CONFIDENTIAL", opacity: 0.2, size: 36)
|> PaperForge.update_metadata(title: "Reviewed report")
|> PaperForge.write!("output.pdf")
```

All page numbers are one-based. Invalid selections and rotations raise.
`rotate_pages/3` adds a multiple of 90 degrees to the inherited rotation.
`update_metadata/2` changes only supplied Info fields; unrelated entries survive.
It does not synchronize XMP. Watermarks use Helvetica-Bold with Latin-1 text,
preserve inherited/indirect resources, choose unused resource names, and isolate
the previous content's graphics state. They do not implement automatic text fitting
or international font shaping.

```elixir
{:ok, extracted} = PaperForge.extract_pages(pdf, [3, 1])
{:ok, merged} = PaperForge.merge([extracted, another_document])
reordered = PaperForge.reorder_pages(pdf, [3, 1, 2])
normalized = PaperForge.normalize(reordered)
```

`reorder_pages/2` requires a permutation of all pages. Extraction and merging use
page-level import into a new document; they do not merge document-level outline,
AcroForm, attachment, tagging, or signature catalogs. Open encrypted inputs first
and pass the resulting documents to these functions.

`normalize/1` materializes inherited page attributes, flattens the page tree, and
removes objects unreachable from Root and Info. It does not repair invalid PDF
operators, rebuild tags, reconcile destinations or form relationships after page
deletion, or canonicalize visually equivalent resources. Page deletion is not
redaction: other references may retain content from removed pages.

Writing produces a complete new PDF with classic xref subsections. Incremental
append-only writing is future work. Rewriting does not preserve the validity of
existing digital signatures or linearization. A successfully decrypted document
writes unencrypted unless new `security:` options are supplied to the writer.

## Compatibility And Limits

| Feature | 1.5.0 support |
| --- | --- |
| Headers | PDF 1.0–1.7 and 2.0 syntax; no blanket conformance claim for every version feature |
| Cross references | Tables, streams, hybrid references, sparse IDs and incremental `/Prev` chains |
| Objects | Direct and compressed objects; generation-aware references; direct/indirect stream lengths |
| Pages | Nested page trees and inherited Resources, MediaBox, CropBox and Rotate |
| Structural filters | FlateDecode, ASCIIHexDecode, ASCII85Decode, RunLengthDecode; filter arrays; PNG predictors 10–15 |
| Other streams | Encoded bytes preserved; unsupported image codecs/filters are not rasterized or decoded |
| Encryption | Standard AES-256 revisions 5 and 6, user and owner passwords, permission-block verification |
| Unsupported encryption | RC4, AES-128, public-key/custom handlers, alternate crypt-filter layouts |
| Password preparation | Supplied UTF-8 bytes, truncated to 127 bytes; no SASLprep normalization |
| Malformed input | Explicit errors; no xref reconstruction or recovery scan |

Unsupported filters in structural xref/object streams prevent opening the file.
Unknown filters in ordinary content or image streams are preserved. LZW and TIFF
predictor decoding are not implemented in this release. A graph can open with
broken nonessential references so `analyze/1` can report them; the writer validates
references before serialization and import rejects reachable broken references.

Defaults can be tightened per import:

```elixir
PaperForge.open("input.pdf",
  max_file_size: 100_000_000,
  max_objects: 500_000,
  max_depth: 100,
  max_stream_size: 50_000_000,
  max_total_decoded_bytes: 200_000_000,
  timeout: 15_000
)
```

The stream limit applies to encoded data and to supported decoded stream data.
The total decoded limit also bounds cached object streams and cumulative decoded
stream sizes. Unknown codecs remain bounded by their encoded size, not hypothetical
pixel memory. `:max_recursion_depth` aliases `:max_depth`, and
`:max_uncompressed_stream_bytes` aliases `:max_stream_size`. A parser timeout
covers parsing, not the preceding filesystem read. No password or derived key is
retained in the document. Choose limits and timeout for the application's workload.

## Verification

The regular suite covers syntax, xref revisions, hybrid and object streams,
inherited resources, stale generations, cyclic references, decompression limits,
passwords, inspection, transformation and round trips. The fuzz profile mutates
classic and independently generated compressed/incremental PDFs at arbitrary byte
positions. Existing authoring, security, layout and writer tests remain in place.

`test/fixtures/interoperability/generate.py` creates owned fixtures using pikepdf
9.11.0/libqpdf and pypdf 6.21.2. Those packages are optional QA tools, not runtime
or test-suite dependencies. Fixtures cover classic, compressed, linearized,
incremental, AES-256 and explicitly unsupported AES-128 documents. Real-world
producer diversity still exceeds this corpus; reproducible compatibility reports
with shareable PDFs are welcome.

Implementation references: [qpdf object and cross-reference streams](https://qpdf.readthedocs.io/en/stable/object-streams.html)
and [PDF Association syntax/encryption errata](https://pdf-issues.pdfa.org/32000-2-2020/clause07.html).
