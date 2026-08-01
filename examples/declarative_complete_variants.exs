variants = [
  {"lumen_atlas.json", "paper_forge_declarative_lumen_atlas.pdf"},
  {"aurora_motion.json", "paper_forge_declarative_aurora_motion.pdf"}
]

renderer = Path.join(__DIR__, "paper_forge_0_6_complete.exs")

Enum.each(variants, fn {data_file, output_file} ->
  data_path = Path.join([__DIR__, "data", data_file])
  output_path = Path.expand("../output/pdf/#{output_file}", __DIR__)
  File.mkdir_p!(Path.dirname(output_path))

  System.put_env("PAPERFORGE_DATA", data_path)
  System.put_env("PAPERFORGE_OUTPUT", output_path)
  Code.eval_file(renderer)
end)

System.delete_env("PAPERFORGE_DATA")
System.delete_env("PAPERFORGE_OUTPUT")
