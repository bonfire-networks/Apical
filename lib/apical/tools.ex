defmodule Apical.Tools do
  @default_content_mapping [{"application/yaml", YamlElixir}, {"application/json", Jason}]
  def decode(string, opts) do
    # content_type defaults to "application/yaml"
    content_type = Keyword.get(opts, :content_type, "application/yaml")

    opts
    |> Keyword.get(:decoders, [])
    |> List.keyfind(content_type, 0, List.keyfind(@default_content_mapping, content_type, 0))
    |> case do
      {_, YamlElixir} -> YamlElixir.read_from_string!(string)
      {_, Jason} -> Jason.decode!(string)
      nil -> raise "decoder for #{content_type} not found"
    end
  end

  @spec maybe_dump(Macro.t(), keyword) :: Macro.t()
  def maybe_dump(quoted, opts) do
    if Keyword.get(opts, :dump, false) do
      quoted
      |> Macro.to_string()
      |> IO.puts()

      quoted
    else
      quoted
    end
  end

  @terminating ~w(extra_plugs)a

  def deepmerge(into_list, src_list) when is_list(into_list) do
    Enum.reduce(src_list, into_list, fn
      {key, src_value}, so_far when key in @terminating ->
        deepmerge_terminating(so_far, src_value, key)

      {key, src_value}, so_far ->
        if kv = List.keyfind(into_list, key, 0) do
          {_k, v} = kv
          List.keyreplace(so_far, key, 0, {key, deepmerge(v, src_value)})
        else
          [{key, src_value} | so_far]
        end
    end)
  end

  def deepmerge(_, src), do: src

  defp deepmerge_terminating(so_far, src_value, key) do
    original = Keyword.get(so_far, key, [])

    merged = Enum.reduce(src_value, original, &maybe_replace/2)

    List.keyreplace(so_far, key, 0, {key, merged})
  end

  defp maybe_replace({k, :delete}, [k | rest]) do
    rest
  end

  defp maybe_replace(this = {k, _}, [{k, _} | rest]) do
    [this | rest]
  end

  defp maybe_replace(k, found = [k | _]), do: found

  defp maybe_replace(k, [different | rest]) do
    [different | maybe_replace(k, rest)]
  end

  defp maybe_replace(k, []), do: [k]

  def assert(condition, message, opts \\ []) do
    # todo: consider adding jsonschema path information here.
    unless condition do
      explained =
        if opts[:apical] do
          "Your schema violates the Apical requirement #{message}"
        else
          "Your schema violates the OpenAPI requirement #{message}"
        end

      raise CompileError, description: explained
    end
  end
end
