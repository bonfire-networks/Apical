defmodule Apical do
  @moduledoc """
  Generates a web router from an OpenAPI document.

  Building an OpenAPI-compliant Phoenix router can be as simple as:

  ```elixir
  defmodule MyRouter do
    require Apical

    Apical.router_from_file(
      "path/to/openapi.yaml",
      controller: MyProjectWeb.ApiController
    )
  end
  ```

  See https://spec.openapis.org/oas/v3.1.0 for details on how to compose an OpenAPI
  schema.

  Using the macros `router_from_string/2` or `router_from_file/2` you may generate a
  `Phoenix.Router` or an `Apical.Plug.Router` (for `Plug`-only deployments) that
  corresponds to OpenAPI document.

  > ### Tip {: .tip }
  >
  > In general, using `router_from_file/2` is should be preferred, especially if you
  > must maintain multiple versions of the schema, though you may find it easier to
  > iterate using `router_from_string/2` during early development.  In that case, it
  > is possible to switch to `router_from_file/2` when you are ready to finalize your
  > API design or start versioning


  The following activities are performed by the router generated by the macros:

  - Tagging inbound requests with API version
  - Constructing route and http verb matches in the router
  - Parameter operations
    - Supports:
      - Cookie parameters
      - Header parameters
      - Path parameters
      - Query parameters
    - Features:
      - Style decoding based on parameter styles (see https://spec.openapis.org/oas/v3.1.0#style-values)
      - Custom style decoding
      - Parameter marshalling (converting strings to types)
      - Parameter validation
  - Request body validation
    - content-length and content-type validation
    - matching content-type with request body plugs
    - Automatic json and `form-encoded` request body parsing
    - Parameter marshalling for `form-encoded` requests

  ### Options

  The following options are common to `router_from_string/2` and `router_from_file/2`.

  #### Global options
  - `for`: allows you to select which framework you would like to generate the router
    for.  Select one of:
    - `Phoenix`: (default) generates the interior code for a `Phoenix.Router` module
    - `Plug`: generates the interior code for an `Apical.Plug.Router` module.

      > #### Warning {: .warning }
      >
      > The `Apical.Plug.Router` module does not have the same interface as
      > `Plug.Router`, though it is a plug.

  - `encoding`: mimetype which describes how the schema is encoded.

    required in `router_from_string/2`, deduced from filename in `router_from_file/2`.

  - `decoders`:  A proplist of mimetype to decoders.

    If you use an encoding that isn't `application/json` or `application/yaml` you
    should provide this proplist, which, at a minimum, contains
    `[{encoding_mimetype, {module, function}}]`.  The call `module.function(string)`
    should return a map representing the OpenAPI schema, and should raise in the
    case that the content is not decodable.

  - `root`: the root path for the router.

    Defaults to `/v{major}` where `major` is the major version of the API, as declared
    under `info.version` in the schema.

  - `dump`: (For debugging), sends formatted code of the router to stdout.

    Defaults to `false`.  If set to `:all`, will also pass `dump: true` to Exonerate.

  #### Scopable options

  The following options are *scopable*.  They may be placed as top-level options
  or under the scopes (see below)

  - `controller`:  Plug module which contains code implementing the API.

    It is recommended to `use Phoenix.Controller` in this plug module, or the
    functions may or may not be targetted as expected.

    Controller modules should implement public functions corresponding to the
    `operationId` of each operation in the schema.  These functions must be
    cased in the same fashion as the `operationId`, and like all Phoenix Controller
    functions, take two arguments:

    - `conn`: the `Plug.Conn` for the request
    - `params`: a map containing the parameters for the operation.  This is
      identical to `conn.params`.

    > ### Important {: .warning }
    >
    > Unlike standard Phoenix controller functions, parameters declared in the
    > `parameters` list of the operation are made avaliable in the `params`
    > argument as well as in `conn.params`.  These parameters will overwrite
    > any fields present in body parameters that happen to have the same name.

    A single router may have its routes target more than one controller.

  - `extra_plugs`: a list of plugs to execute after the route has matched
    but before the parameter and body pipeline has been executed.

    These plugs are  defined using `{atom, [args...]}` where `args` is
    a list of plug options to be applied to the plug, or `atom` which
    is equivalent to `{atom, []}`.  These may be either a function plug
    or a module plug.

    > ### Route-level Security Plugs {: .tip }
    >
    > Route-level security checks should be performed in plugs declared in
    > `extra_plugs`, until `Apical` provides direct support for security
    > schemes.

    > ### Global plugs {: .tip }
    >
    > if you need plugs to be executed for all routes, declare those plugs
    > in the router module before the macro `Exonerate.router_from_*`.

    > ### Post-pipeline plugs {: .tip }
    >
    > if you need plugs to be executed after the parameter and body pipeline,
    > for example, for row-level security checks, declare those plugs in the
    > controller module.  Note that these plugs should be able to match on
    > the `operationId` atom using `conn.private.operation_id`.

  - `styles`: a proplist of custom styles and their corresponding parsers.

      Each parser is represented as `{module, function, [args...]}` or
      `{module, function}` which is equivalent too `{module, function []}`.

      The parsers are functions that are called as
      `module.function(string, args...)`,  and return `{:ok, value}` or
      `{:error, message}`.  The message should be a string describing the
      error.

      The following styles are supported by default and do not need to be
      included in the styles proplist:

      - `"matrix"`
      - `"label"`
      - `"simple"`
      - `"form"`
      - `"space_delimited"`
      - `"pipe_delimited"`
      - `"deep_object"`

      see https://spec.openapis.org/oas/v3.1.0#style-values for description
      of these styles.

      > ### Custom styles {: .warning }
      >
      > If you need to support a custom style, you *must* add it to the
      > `styles` proplist.

      > ### Form-exploded objects {: .error }
      >
      > Form-exploded style parameters with type `object` in their schema are
      > not supported due to ambiguity in their definition per the OpenAPI
      > specification.

  - `content_sources`: A proplist of media-types (as **string** keys) and
    functions to act as the source for request body.  These should be
    defined as `{media_type, {module, [opts...]}}`.  These opts will be
    passed into the `c:Apical.Plugs.RequestBody.Source.fetch/3`.

  - `nest_all_json`: Analogous to the option in `Plug.Parsers.JSON`, this
    option will nest all json request body payloads under the `"_json"` key.
    if this is not true, objects payloads will be merged into `conn.params`.

  #### Available scopes

  The scopes have the following precedence:

  operation_ids > groups > tags > parameters > global

  - `operation_ids`: A keywordlist of `operationId`s (as atom keys) and options
    to target to these operations.

    The keys must be cased in the same fashion as the `operationId` in the
    schema.

  - `tags`: A keywordlist of tags (as atom keys) and options to target to those
    tags.

    The tag keys must be cased in the same fashion as their tags in the schema.

  - `parameters`: A keywordlist of parameters (as atom keys) and options to
    target to those parameters.

    The parameter keys must be cased in the same fashion (including kebab-case)
    Note that this scope may be further nested inside of `tag` and
    `operation_ids` scopes.

  - `groups`: A keywordlist of groups (as atom keys) and options to target to
    those groups.  The group definition should start off with the names of the
    operationIds that are in the group (as atoms), followed by the options to
    send to them (as keyword lists)

  #### Scoped options

  The following options are only valid in a single scope:

  - `alias`: (scoped to `:operation_ids`) overrides the name of the function
    pointed to by the `operationId` in the schema.

  - `marshal`: (scoped to `parameters`) overrides the marshaller to use for
    parameter.  May be `atom` for a local function, `{atom, list}` for a
    local function with extra parameters, `{module, atom}` for a remote
    function, or `{module, atom, list}` for a remote function with extra
    parameters.  Note that the local function must be an exported function.
  """

  alias Apical.Router
  alias Apical.Tools

  @spec router_from_string(String.t(), Keyword.t()) :: any()
  @doc """
  Generates a web router from a String containing an OpenAPI document.

  ### Example:

  ```elixir
  defmodule MyRouter do
    require Apical

    Apical.router_from_string(
      \"""
      openapi: 3.1.0
      info:
        title: My API
        version: 1.0.0
      paths:
        "/":
          get:
            operationId: getOperation
            responses:
              "200":
                description: OK
      \""",
      controller: MyProjectWeb.ApiController,
      encoding: "application/yaml"
    )
  end
  ```

  For options see `Apical` module docs.
  """
  defmacro router_from_string(string, opts) do
    opts = Macro.expand_literals(opts, __CALLER__)

    router(string, opts)
  end

  @spec router_from_file(Path.t(), Keyword.t()) :: any()
  @doc """
  Generates a web router from a String containing an OpenAPI document.

  ### Example:

  ```elixir
  defmodule MyRouter do
    require Apical

    Apical.router_from_file(
      "path/to/openapi.yaml",
      controller: MyProjectWeb.ApiController
    )
  end
  ```

  For options see `Apical` module docs.
  """
  defmacro router_from_file(file, opts) do
    opts =
      opts
      |> Macro.expand_literals(__CALLER__)
      |> Keyword.merge(file: file)
      |> Keyword.put_new_lazy(:encoding, fn -> find_encoding(file, opts) end)

    file
    |> Macro.expand(__CALLER__)
    |> File.read!()
    |> router(opts)
  end

  defp router(string, opts) do
    string
    |> Tools.decode(opts)
    |> Router.build(string, opts)
    |> Tools.maybe_dump(opts)
  end

  defp find_encoding(filename, _opts) do
    case Path.extname(filename) do
      ".json" -> "application/json"
      ".yaml" -> "application/yaml"
      _ -> raise "unsupported file extension"
    end
  end
end
