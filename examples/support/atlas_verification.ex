defmodule PaperForge.Examples.AtlasVerification do
  @moduledoc false
  alias PaperForge.{Page, PDF.Graph}
  alias PaperForge.Examples.AtlasReport

  def verify!(document, layout) do
    {:ok, analysis} = PaperForge.analyze(document)
    routes = AtlasReport.routes()
    tables = Enum.filter(layout.placements, &String.starts_with?(&1.id, "route-table-part-"))

    ids =
      for table <- tables,
          row <- table.rows,
          text = row.cells |> hd() |> Map.fetch!(:lines) |> Enum.join(" "),
          String.starts_with?(text, "AT-"),
          do: text

    checks = %{
      "page_count_matches_layout" => PaperForge.page_count(document) == layout.pages,
      "large_document" => layout.pages >= 20,
      "no_broken_references" => analysis.broken_references == [],
      "no_inspection_errors" => analysis.issues == [],
      "all_120_routes_once_in_order" => ids == Enum.map(routes, & &1.id),
      "table_spans_multiple_pages" => length(tables) >= 6,
      "headers_repeated_on_every_table_page" =>
        Enum.all?(tables, fn table ->
          hd(hd(table.rows).cells).lines == ["Corredor"]
        end),
      "automatic_blocks_within_margins" =>
        Enum.all?(layout.placements, &within_bounds?(&1, layout)),
      "page_numbers_are_contiguous" =>
        Enum.uniq(Enum.map(layout.placements, & &1.page_number)) == Enum.to_list(1..layout.pages),
      "embedded_route_dataset" =>
        Enum.any?(PaperForge.attachments(document), &(&1.name == "atlas-routes.json")),
      "chapter_bookmarks" => length(PaperForge.outlines(document)) >= 13,
      "internal_links" => length(PaperForge.annotations(document)) >= 13,
      "monthly_and_quarterly_totals_agree" =>
        Enum.sum(Enum.map(AtlasReport.months(), &elem(&1, 1))) == 225 + 256 + 283 + 326,
      "complete_register_has_end_marker" =>
        Enum.any?(layout.placements, &(&1.id == "register-end"))
    }

    assert_checks!(checks)

    %{
      "checks" => checks,
      "pages" => layout.pages,
      "objects" => analysis.object_count,
      "route_rows" => length(ids),
      "route_table_pages" => Enum.map(tables, & &1.page_number),
      "scheduled_trips" => Enum.sum(Enum.map(routes, & &1.trips)),
      "annual_revenue_mxn_millions" => 1090,
      "placements" => length(layout.placements),
      "chapter_titles" =>
        for(p <- layout.placements, p.type == :heading,
          Keyword.get(p.block.options, :bookmark, true), do: p.block.content),
      "chapter_destinations" =>
        for(
          p <- layout.placements,
          p.type == :heading,
          destination = Keyword.get(p.block.options, :destination),
          is_binary(destination),
          into: %{},
          do: {destination, p.page_number}
        ),
      "fonts" => length(analysis.fonts),
      "cross_reference_type" => analysis.cross_reference_type,
      "scope" =>
        "Fictional dataset. Structural and layout checks; not PDF/A, PDF/UA, signature or financial certification."
    }
  end

  def transformed_extract!(document, output) do
    {:ok, excerpt} = PaperForge.extract_pages(document, [1, 3, 4, 5])

    excerpt =
      excerpt
      |> PaperForge.rotate_pages([4], 90)
      |> PaperForge.add_watermark("DEMO / REVIEW COPY", size: 24)
      |> PaperForge.update_metadata(title: "Atlas 2026 - reviewed extract")

    PaperForge.write!(excerpt, output)
    reopened = PaperForge.open!(output)
    {:ok, pages} = Graph.pages(reopened)
    {:ok, analysis} = PaperForge.analyze(reopened)

    checks = %{
      "extract_reopens_with_four_pages" => PaperForge.page_count(reopened) == 4,
      "selected_page_rotated" => List.last(pages).dictionary["Rotate"] == 90,
      "metadata_updated" =>
        PaperForge.metadata(reopened)["Title"] == "Atlas 2026 - reviewed extract",
      "transformed_graph_has_no_broken_references" => analysis.broken_references == []
    }

    assert_checks!(checks)
    checks
  end

  defp within_bounds?(%{id: "cover"}, _), do: true

  defp within_bounds?(placement, report) do
    page = Enum.at(report.rendered_pages, placement.page_number - 1)

    height =
      if placement.type == :table,
        do: Enum.sum(Enum.map(placement.rows, & &1.height)),
        else: placement.height

    epsilon = 0.01

    placement.x >= Page.content_left(page) - epsilon and
      placement.x + placement.width <= page.width - page.margins.right + epsilon and
      placement.y >= Page.content_top(page) - epsilon and
      placement.y + height <= Page.content_bottom(page) + epsilon
  end

  defp assert_checks!(checks) do
    failed = for {name, false} <- checks, do: name
    if failed != [], do: raise("Atlas verification failed: #{Enum.join(failed, ", ")}")
  end
end
