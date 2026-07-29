defmodule PaperForge.ProductionHardeningTest do
  use ExUnit.Case, async: true

  test "xref offset and EOF marker are internally conformant" do
    pdf =
      PaperForge.new(compress: false)
      |> PaperForge.add_page(fn page ->
        PaperForge.Page.text(page, "Conformance", x: 40, y: 40)
      end)
      |> PaperForge.to_binary()

    [_, offset] = Regex.run(~r/startxref\n(\d+)\n%%EOF\n\z/, pdf)
    offset = String.to_integer(offset)

    assert binary_part(pdf, offset, 4) == "xref"
    assert String.starts_with?(pdf, "%PDF-1.7\n")
    assert String.ends_with?(pdf, "%%EOF\n")
  end

  test "corrupted image inputs fail predictably without exits or throws" do
    :rand.seed(:exsss, {101, 202, 303})

    Enum.each(1..200, fn size ->
      binary = :rand.bytes(rem(size, 96) + 1)

      result =
        try do
          PaperForge.new()
          |> PaperForge.add_page(fn page ->
            PaperForge.Page.image(page, binary, x: 10, y: 10, width: 20, height: 20)
          end)

          :accepted
        rescue
          error in ArgumentError -> {:error, error.message}
        end

      assert match?({:error, _}, result)
    end)
  end

  test "pdfinfo accepts a generated compatibility fixture when available" do
    case System.find_executable("pdfinfo") do
      nil ->
        :ok

      executable ->
        path = Path.join(System.tmp_dir!(), "paper_forge_compatibility.pdf")

        PaperForge.new()
        |> PaperForge.add_page(fn page ->
          page
          |> PaperForge.Page.text("Compatibility", x: 50, y: 50)
          |> PaperForge.Page.circle(x: 100, y: 120, radius: 20, fill: true)
        end)
        |> PaperForge.write!(path)

        {output, status} = System.cmd(executable, [path], stderr_to_stdout: true)
        assert status == 0, output
        assert output =~ "Pages:"
    end
  end

  test "qpdf accepts a generated compatibility fixture when available" do
    with_external_pdf("qpdf", ["--check"], fn output ->
      assert output =~ "checking" or output =~ "No syntax or stream encoding errors"
    end)
  end

  test "VeraPDF checks a generated fixture when available" do
    with_external_pdf("verapdf", ["--format", "text"], fn output ->
      assert output =~ "PASS" or output =~ "FAILED"
    end)
  end

  defp with_external_pdf(executable_name, arguments, assertion) do
    case System.find_executable(executable_name) do
      nil ->
        :ok

      executable ->
        path =
          Path.join(
            System.tmp_dir!(),
            "paper_forge_#{executable_name}_#{System.unique_integer([:positive])}.pdf"
          )

        PaperForge.new()
        |> PaperForge.add_page(fn page ->
          page
          |> PaperForge.Page.text("External conformance", x: 50, y: 50)
          |> PaperForge.Page.rectangle(x: 50, y: 80, width: 100, height: 40, fill: true)
        end)
        |> PaperForge.write!(path)

        {output, status} =
          System.cmd(executable, arguments ++ [path], stderr_to_stdout: true)

        assert status == 0, output
        assertion.(output)
    end
  end
end
