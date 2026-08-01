defmodule PaperForge.DeclarativeCliTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "validates a template and data without rendering a PDF" do
    root = temporary_directory!()
    template = Path.join(root, "invoice.paperforge")
    data = Path.join(root, "invoice.json")

    File.write!(
      template,
      Jason.encode!(%{
        version: "1",
        variables: %{customer: %{type: "string", required: true, min_length: 2}},
        blocks: [%{type: "paragraph", text: "Invoice for {{customer}}"}]
      })
    )

    File.write!(data, Jason.encode!(%{customer: "Lumen Atlas"}))
    Mix.Task.reenable("paper_forge.validate")

    assert capture_io(fn ->
             Mix.Tasks.PaperForge.Validate.run([template, data])
           end) =~ "Valid .paperforge template"
  end

  test "reports structured validation failures" do
    root = temporary_directory!()
    template = Path.join(root, "invoice.paperforge")
    data = Path.join(root, "invoice.json")

    File.write!(
      template,
      Jason.encode!(%{
        version: "1",
        variables: %{customer: %{type: "string", required: true}},
        blocks: []
      })
    )

    File.write!(data, Jason.encode!(%{}))
    Mix.Task.reenable("paper_forge.validate")

    output =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, fn ->
          Mix.Tasks.PaperForge.Validate.run([template, data])
        end
      end)

    assert output =~ "$.data.customer"
    assert output =~ "[required]"
  end

  test "validates standalone component files without application data" do
    root = temporary_directory!()
    component = Path.join(root, "badge.paperforge")

    File.write!(
      component,
      Jason.encode!(%{
        version: "1",
        kind: "component",
        name: "badge",
        props: %{label: %{type: "string", required: true}},
        blocks: [%{type: "paragraph", text: "{{label}}"}]
      })
    )

    Mix.Task.reenable("paper_forge.validate")

    assert capture_io(fn ->
             Mix.Tasks.PaperForge.Validate.run([component])
           end) =~ "Valid .paperforge template"
  end

  test "prints exact data-file line and column for semantic errors" do
    root = temporary_directory!()
    template = Path.join(root, "invoice.paperforge")
    data = Path.join(root, "invoice.json")

    File.write!(
      template,
      Jason.encode!(%{
        version: "1",
        variables: %{customer: %{type: "string", required: true}},
        blocks: []
      })
    )

    File.write!(data, "{\n  \"customer\": 42\n}\n")
    Mix.Task.reenable("paper_forge.validate")

    output =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, fn ->
          Mix.Tasks.PaperForge.Validate.run([template, data])
        end
      end)

    assert output =~ "#{Path.expand(data)}:2:3 $.data.customer"
    assert output =~ "[invalid_type]"
  end

  defp temporary_directory! do
    path = Path.join(System.tmp_dir!(), "paper_forge_cli_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
