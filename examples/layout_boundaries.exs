alias PaperForge.{Flow, Page, Color}

{document, report} =
  PaperForge.layout(
    PaperForge.new(compress: false),
    fn flow ->
      flow
      |> Flow.heading("Automatic placement with wrapped headings", size: 24)
      |> Flow.paragraph("Large text\nSecond line",
        size: 22,
        padding: 8,
        fill_color: Color.gray(0.92)
      )
      |> Flow.columns(2, ["Left column\nSecond line", "Right column\nSecond line"],
        size: 14,
        width: :content
      )
      |> Flow.keep_together(fn group ->
        group
        |> Flow.paragraph("Table and its title", size: 16)
        |> Flow.table(["Item", "Result"], [["Margins", "Checked"], ["Pagination", "Checked"]])
      end)
      |> Flow.rich_text([{"Large inline text", [size: 24]}, {"\nFollowing line", [size: 12]}])
    end,
    page_options: [size: {340, 360}, margins: [top: 30, bottom: 30, left: 24, right: 36]],
    header: fn page, context ->
      Page.rectangle(page,
        x: context.content_left,
        y: context.content_top,
        width: context.content_width,
        height: context.content_bottom - context.content_top,
        stroke_color: Color.rgb(1, 0, 0),
        line_width: 0.5
      )
    end,
    footer: "Page {page} of {total}"
  )

File.mkdir_p!("output/pdf")
File.write!("output/pdf/layout-boundaries.pdf", PaperForge.to_binary(document))
IO.inspect(report.pages, label: "QA pages")
