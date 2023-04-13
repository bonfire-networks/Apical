defmodule Apical.Plugs.Query do
  @behaviour Plug

  alias Plug.Conn

  def init(parameters) do
    # NOTE: parameter motion already occurs
    Enum.reduce(parameters, %{query_context: %{}}, fn parameter, operations ->
      operations
      |> add_if_required(parameter)
      |> add_if_deprecated(parameter)
      |> add_type(parameter)
      |> add_style(parameter)
      |> add_inner_marshal(parameter)
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

  defp add_type(operations, %{"name" => name, "schema" => %{"type" => type}}) do
    types = to_type_list(type)
    Map.update!(operations, :query_context, &Map.put(&1, name, %{type: types}))
  end

  defp add_type(operations, _), do: operations

  @types ~w(null boolean integer number string array object)a
  @type_class Map.new(@types, &{"#{&1}", &1})
  @type_order Map.new(Enum.with_index(@types))

  defp to_type_list(type) do
    type
    |> List.wrap()
    |> Enum.map(&Map.fetch!(@type_class, &1))
    |> Enum.sort_by(&Map.fetch!(@type_order, &1))
  end

  defp add_style(operations, %{"style" => "deepObject", "name" => name}) do
    update_in(operations, [:query_context, :deep_object_keys], &[name | List.wrap(&1)])
  end

  defp add_style(operations, parameters = %{"name" => name}) do
    types = List.wrap(get_in(parameters, ["schema", "type"]))

    if "array" in types or "object" in types do
      selected_style =
        case Map.fetch(parameters, "style") do
          :error ->
            :form

          {:ok, "form"} ->
            :form

          {:ok, "spaceDelimited"} ->
            :space_delimited

          {:ok, "pipeDelimited"} ->
            :pipe_delimited
            # we'll handle "other things" later.
        end

      new_query_context =
        Map.update!(
          operations.query_context,
          name,
          &Map.put(&1, :style, selected_style)
        )

      %{operations | query_context: new_query_context}
    else
      operations
    end
  end

  defp add_inner_marshal(operations = %{query_context: context}, %{
         "schema" => schema,
         "name" => key
       })
       when is_map_key(context, key) do
    outer_type = context[key].type

    cond do
      :array in outer_type ->
        prefix_items_type =
          List.wrap(
            if prefix_items = schema["prefixItems"] do
              Enum.map(prefix_items, &to_type_list(&1["type"]))
            end
          )

        items_type =
          List.wrap(
            if items = schema["items"] || schema["additionalItems"] do
              to_type_list(items["type"] || ["string"])
            end
          )

        new_key_spec =
          Map.put(operations.query_context[key], :elements, {prefix_items_type, items_type})

        put_in(operations, [:query_context, key], new_key_spec)

      :object in outer_type ->
        property_types =
          schema
          |> Map.get("properties", %{})
          |> Map.new(fn {name, property} ->
            {name, to_type_list(property["type"])}
          end)

        pattern_types =
          schema
          |> Map.get("patternProperties", %{})
          |> Map.new(fn {regex, property} ->
            {Regex.compile!(regex), to_type_list(property["type"])}
          end)

        additional_types =
          schema
          |> get_in(["additionalProperties", "type"])
          |> Kernel.||("string")
          |> to_type_list()

        new_key_spec =
          Map.put(operations.query_context[key], :properties, {property_types, pattern_types, additional_types})

        put_in(operations, [:query_context, key], new_key_spec)

      true ->
        operations
    end
  end

  defp add_inner_marshal(operations, _), do: operations

  def call(conn, operations) do
    # TODO: refactor this out to the outside.
    conn
    |> Apical.Conn.fetch_query_params(operations.query_context)
    |> filter_required(operations)
    |> warn_deprecated(operations)
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
end