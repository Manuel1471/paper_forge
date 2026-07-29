alias PaperForge.Flow

rows =
  for index <- 1..5_000 do
    ["ROW-#{index}", "Region #{rem(index, 8) + 1}", index * 17, "#{rem(index * 7, 100)}%"]
  end

before_memory = :erlang.memory(:total)

{time_us, {document, report}} =
  :timer.tc(fn ->
    PaperForge.new(compress: true)
    |> PaperForge.layout(fn flow ->
      Flow.table(
        flow,
        ["Identifier", "Region", "Revenue", "Growth"],
        rows,
        repeat_header: true,
        row_split: :split,
        column_widths: [110, 110, 100, 80]
      )
    end)
  end)

{serialization_us, pdf} = :timer.tc(fn -> PaperForge.to_binary(document) end)
after_memory = :erlang.memory(:total)

IO.inspect(%{
  rows: length(rows),
  pages: report.pages,
  layout_ms: time_us / 1_000,
  serialization_ms: serialization_us / 1_000,
  pdf_bytes: byte_size(pdf),
  memory_delta_bytes: after_memory - before_memory
})
