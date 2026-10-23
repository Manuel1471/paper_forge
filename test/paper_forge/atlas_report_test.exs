Code.require_file("../../examples/support/atlas_report.ex", __DIR__)
Code.require_file("../../examples/support/atlas_verification.ex", __DIR__)

defmodule PaperForge.AtlasReportTest do
  use ExUnit.Case, async: true
  alias PaperForge.Examples.{AtlasReport, AtlasVerification}

  @tag :tmp_dir
  test "large editorial report survives generation, inspection and transformation", %{
    tmp_dir: dir
  } do
    {document, layout} = AtlasReport.build()
    path = Path.join(dir, "report.pdf")
    PaperForge.write!(document, path)
    reopened = PaperForge.open!(path)
    result = AtlasVerification.verify!(reopened, layout)
    assert result["scheduled_trips"] == 34_140
    assert Enum.all?(result["checks"], fn {_, passed} -> passed end)
    checks = AtlasVerification.transformed_extract!(reopened, Path.join(dir, "extract.pdf"))
    assert Enum.all?(checks, fn {_, passed} -> passed end)
  end
end
