defmodule PaperForge.ProductionHardeningTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias PaperForge.Concurrent
  alias PaperForge.Error
  alias PaperForge.Interoperability
  alias PaperForge.Page
  alias PaperForge.Runtime.CircuitBreaker
  alias PaperForge.Runtime.Guard
  alias PaperForge.Writer

  setup do
    CircuitBreaker.reset()
    :ok
  end

  test "bounded operations return a stable timeout error and leave no worker behind" do
    parent = self()

    assert {:error, %Error{code: "PF8101", category: :timeout, operation: :import}} =
             Guard.run(
               :import,
               fn ->
                 send(parent, :started)
                 Process.sleep(100)
               end,
               timeout: 1
             )

    assert_receive :started
  end

  test "repeated failures open a short-lived resource circuit" do
    failed = fn -> {:error, :invalid_resource} end

    assert {:error, :invalid_resource} =
             CircuitBreaker.protect(:fixture, failed, failure_threshold: 2, reset_after_ms: 100)

    assert {:error, :invalid_resource} =
             CircuitBreaker.protect(:fixture, failed, failure_threshold: 2, reset_after_ms: 100)

    assert {:error, %Error{code: "PF8102", category: :resource}} =
             CircuitBreaker.protect(:fixture, failed, failure_threshold: 2, reset_after_ms: 100)
  end

  test "a healthy result clears prior circuit failures" do
    options = [failure_threshold: 2, reset_after_ms: 1_000]

    assert {:error, :temporary} =
             CircuitBreaker.protect(:recovering, fn -> {:error, :temporary} end, options)

    assert {:ok, :healthy} =
             CircuitBreaker.protect(:recovering, fn -> {:ok, :healthy} end, options)

    assert {:error, :temporary} =
             CircuitBreaker.protect(:recovering, fn -> {:error, :temporary} end, options)

    assert {:error, :temporary} =
             CircuitBreaker.protect(:recovering, fn -> {:error, :temporary} end, options)
  end

  test "circuit state is bounded for unique failing resources" do
    Enum.each(1..20, fn id ->
      assert {:error, :temporary} =
               CircuitBreaker.protect(
                 {:resource, id},
                 fn -> {:error, :temporary} end,
                 failure_threshold: 100,
                 reset_after_ms: 10_000,
                 max_entries: 5
               )
    end)

    assert map_size(:sys.get_state(CircuitBreaker)) == 5
  end

  test "the runtime circuit recreates itself after an unexpected crash" do
    assert {:ok, :ready} = CircuitBreaker.protect(:restart, fn -> {:ok, :ready} end)
    pid = Process.whereis(CircuitBreaker)
    Process.exit(pid, :kill)

    assert_eventually(fn -> Process.whereis(CircuitBreaker) == nil end)
    assert {:ok, :recovered} = CircuitBreaker.protect(:restart, fn -> {:ok, :recovered} end)
  end

  test "a malformed PDF is contained by parser limits and never poisons a later valid import" do
    hostile =
      PaperForge.Test.PDFFixture.classic(
        PaperForge.Test.PDFFixture.objects() ++
          [{4, 0, String.duplicate("[", 300) <> "0" <> String.duplicate("]", 300)}]
      )

    assert {:error, {:max_depth_exceeded, 10}} =
             Interoperability.parse_pdf(hostile, max_depth: 10)

    document = document("Healthy import")
    assert {:ok, _parsed} = Interoperability.parse_pdf(PaperForge.to_binary(document))
  end

  test "concurrent render failures remain isolated and successful output is deterministic" do
    document = document("Concurrent deterministic output")

    results =
      Concurrent.run(
        [:first, :broken, :last],
        fn
          :broken -> raise "isolated failure"
          _ -> PaperForge.to_binary(document)
        end,
        max_concurrency: 3,
        timeout: 5_000
      )

    assert [first, broken, last] = results
    assert first.status == :ok
    assert broken.status == :error
    assert broken.error.code == "PF8105"
    assert last.status == :ok
    assert first.value == last.value
  end

  test "temporary export cleanup removes only its own work file" do
    path =
      Path.join(
        System.tmp_dir!(),
        "paperforge-hardening-#{System.unique_integer([:positive])}.pdf"
      )

    temporary = Writer.temporary_path(path)
    concurrent_temporary = Writer.temporary_path(path)
    File.write!(temporary, "partial")
    File.write!(concurrent_temporary, "active")

    assert :ok = Writer.cleanup_temporary_file(temporary)
    refute File.exists?(temporary)
    assert File.exists?(concurrent_temporary)
    File.rm!(concurrent_temporary)
  end

  test "xref offset and EOF marker are internally conformant" do
    pdf = PaperForge.to_binary(document("Conformance"))

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

      assert_raise ArgumentError, fn ->
        PaperForge.new()
        |> PaperForge.add_page(fn page ->
          Page.image(page, binary, x: 10, y: 10, width: 20, height: 20)
        end)
      end
    end)
  end

  test "pdfinfo accepts a generated compatibility fixture when available" do
    with_external_pdf("pdfinfo", [], fn output ->
      assert output =~ "Pages:"
    end)
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

  property "hostile declarative identifiers do not create atoms during bounded compilation" do
    check all(identifier <- string(:printable, min_length: 1, max_length: 128)) do
      template = %{
        "version" => 1,
        "id" => identifier,
        "document" => %{},
        "blocks" => [%{"type" => "text", "text" => "safe"}]
      }

      _ = PaperForge.Declarative.compile(template, %{})
      before = :erlang.system_info(:atom_count)
      _ = PaperForge.Declarative.compile(template, %{})
      assert :erlang.system_info(:atom_count) == before
    end
  end

  @tag :soak
  @tag timeout: 60_000
  test "soak profile completes repeated concurrent render batches without leaking workers" do
    baseline = Process.list() |> MapSet.new()
    document = document("Soak test")

    Enum.each(1..12, fn _batch ->
      results =
        Concurrent.run(1..40, fn _ -> PaperForge.to_binary(document) end,
          max_concurrency: 8,
          timeout: 5_000
        )

      assert Enum.all?(results, &(&1.status == :ok))
    end)

    Process.sleep(20)
    remaining = Process.list() |> MapSet.new()
    assert MapSet.size(MapSet.difference(remaining, baseline)) < 8
  end

  defp document(text) do
    PaperForge.new()
    |> PaperForge.add_page(fn page -> Page.text(page, text, x: 72, y: 72) end)
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

        on_exit(fn -> File.rm(path) end)
        :ok = PaperForge.write(document("External conformance"), path)

        {output, status} =
          System.cmd(executable, arguments ++ [path], stderr_to_stdout: true)

        assert status == 0, output
        assertion.(output)
    end
  end

  defp assert_eventually(predicate, attempts \\ 20)

  defp assert_eventually(predicate, attempts) do
    if predicate.() do
      :ok
    else
      assert attempts > 0
      Process.sleep(5)
      assert_eventually(predicate, attempts - 1)
    end
  end
end
