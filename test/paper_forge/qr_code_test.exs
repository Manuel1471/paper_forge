defmodule PaperForge.QRCodeTest do
  use ExUnit.Case, async: true
  alias PaperForge.{Flow, Page}

  test "batched paths preserve every QR module in both coordinate systems" do
    data = "b874a89e-8397-4fb1-9411-000000000001"

    for origin <- [:top_left, :bottom_left], level <- [:l, :m, :q, :h] do
      matrix = Qiroex.to_matrix!(data, level: level, quiet_zone: 4)
      count = length(matrix)

      page =
        Page.new(origin: origin)
        |> Page.qr_code(data, size: count * 2, x: 10, y: 20, level: level)

      assert length(page.operations) == 2
      {:path, segments, _} = Enum.find(page.operations, &match?({:path, _, _}, &1))

      for {row, row_index} <- Enum.with_index(matrix), {bit, col} <- Enum.with_index(row) do
        x = 10 + col * 2 + 1
        y = 20 + if(origin == :top_left, do: row_index, else: count - row_index - 1) * 2 + 1

        dark =
          Enum.any?(segments, fn {:rectangle, left, bottom, width, height} ->
            x >= left and x < left + width and y >= bottom and y < bottom + height
          end)

        assert dark == (bit == 1)
      end
    end
  end

  test "size controls flow height and QR alignment" do
    {doc, report} =
      PaperForge.new()
      |> PaperForge.layout(
        fn flow ->
          flow
          |> Flow.qr_code("invitation", size: 64, align: :right, space_after: 0)
          |> Flow.paragraph("After QR")
        end,
        page_options: [size: {300, 400}, margins: 30]
      )

    qr = Enum.find(report.placements, &(&1.type == :qr_code))
    paragraph = Enum.find(report.placements, &(&1.type == :paragraph))
    assert qr.height == 64
    assert paragraph.y >= qr.y + 64
    assert byte_size(PaperForge.to_binary(doc)) > 0
  end

  test "oversized QR fails before drawing beyond the flow margins" do
    assert_raise ArgumentError, ~r/available page width/, fn ->
      PaperForge.new()
      |> PaperForge.layout(fn flow -> Flow.qr_code(flow, "data", size: 250) end,
        page_options: [size: {300, 400}, margins: 30]
      )
    end
  end

  test "invalid payloads and dimensions fail explicitly" do
    for options <- [[size: 0], [size: -2], [quiet_zone: 0], [level: :invalid]] do
      assert_raise ArgumentError, fn -> Page.qr_code(Page.new(), "data", options) end
    end

    assert_raise ArgumentError, fn -> Page.qr_code(Page.new(), "") end
  end

  test "invitation template accepts runtime payload and numeric size" do
    {:ok, source} = PaperForge.Declarative.load("examples/qr_invitation.paperforge")

    {:ok, doc, report} =
      PaperForge.Declarative.render(source, %{
        qr_code: "https://example.com/invite/123",
        qr_size: 72
      })

    qr = Enum.find(report.placements, &(&1.type == :qr_code))
    assert qr.block.content == "https://example.com/invite/123"
    assert qr.image_height == 72
    assert qr.block.options[:level] == :h
    assert byte_size(PaperForge.to_binary(doc)) > 0
  end
end
