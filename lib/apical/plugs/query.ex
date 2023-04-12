defmodule Apical.Plugs.Query do
  @behaviour Plug

  alias Plug.Conn

  def init(parameters) do
    # NOTE: parameter motion already occurs
    Enum.reduce(parameters, %{}, fn parameter, operations ->
      operations
      |> add_if_required(parameter)
      |> add_if_deprecated(parameter)
      |> add_style_parsers(parameter)
    end)
  end

  defp add_if_required(operations, %{"required" => true, "name" => name}) do
    Map.update(operations, :required, [name], &[name | &1])
  end

  defp add_if_required(operations, _parameters), do: operations

  defp add_if_deprecated(operations, %{"deprecated" => true, "name" => name}) do
    Map.update(operations, :deprecated, [name], &[name | &1])
  end

  defp add_if_deprecated(operations, _parameters), do: operations

  @style_type_mappings %{"array" => :array_styles, "object" => :object_styles}
  @style_types Map.keys(@style_type_mappings)

  defp add_style_parsers(
         operations,
         parameter = %{
           "name" => name,
           "schema" => %{"type" => type}
         }
       )
       when type in @style_types do
    type_key = Map.fetch!(@style_type_mappings, type)
    style = Map.get(parameter, "style", "default")
    Map.update(operations, type_key, [{name, style}], &[{name, style} | &1])
  end

  defp add_style_parsers(operations, _parameters), do: operations

  def call(conn, operations) do
    # TODO: refacor this out to the outside.
    conn
    |> Conn.fetch_query_params()
    |> filter_required(operations)
    |> warn_deprecated(operations)
    |> parse_array_style(operations)
    |> parse_object_style(operations)
  end

  defp filter_required(conn, %{required: required}) do
    if Enum.all?(required, &is_map_key(conn.query_params, &1)) do
      conn
    else
      # TODO: raise so that this message can be customized
      conn
      |> Conn.put_status(400)
      |> Conn.halt()
    end
  end

  defp filter_required(conn, _), do: conn

  defp warn_deprecated(conn, %{deprecated: deprecated}) do
    Enum.reduce(deprecated, conn, fn param, conn ->
      if is_map_key(conn.query_params, param) do
        Conn.put_resp_header(
          conn,
          "warning",
          "299 - the query parameter `#{param}` is deprecated."
        )
      else
        conn
      end
    end)
  end

  defp warn_deprecated(conn, _), do: conn

  @style_delimiters %{
    "default" => ",",
    "form" => ",",
    "spaceDelimited" => " ",
    "pipeDelimited" => "|"
  }
  @default_styles Map.keys(@style_delimiters)

  defp parse_array_style(conn, %{array_styles: styles}) do
    Enum.reduce(styles, conn, fn
      {param, style}, conn = %{params: params}
      when is_map_key(params, param) and style in @default_styles ->
        delimiter = Map.fetch!(@style_delimiters, style)
        %{conn | params: Map.update!(params, param, &String.split(&1, delimiter))}

      _, conn ->
        conn
    end)
  end

  defp parse_array_style(conn, _), do: conn

  defp parse_object_style(conn, %{object_styles: styles}) do
    Enum.reduce(styles, conn, fn
      {param, style}, conn = %{params: params}
      when is_map_key(params, param) and style in @default_styles ->
        delimiter = Map.fetch!(@style_delimiters, style)
        %{conn | params: Map.update!(params, param, &pairs_to_object(&1, delimiter, param))}

      _, conn ->
        conn
    end)
  end

  defp parse_object_style(conn, _), do: conn

  defp pairs_to_object(string, delimiter, param) do
    string
    |> String.split(delimiter)
    |> pairs_to_object_inner(%{}, param)
  end

  defp pairs_to_object_inner([], object, _), do: object

  defp pairs_to_object_inner([_lone], _object, _param) do
    # for now
    raise "some sort of format error"
  end

  defp pairs_to_object_inner([key, value | rest], object, param) do
    pairs_to_object_inner(rest, Map.put(object, key, value), param)
  end
end
