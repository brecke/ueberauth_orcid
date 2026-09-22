defmodule Ueberauth.Strategy.Orcid.OAuth do
  @moduledoc """
  OAuth2 client for ORCID.

  Configure credentials and, when using this module directly, a callback URI:

      config :ueberauth, Ueberauth.Strategy.Orcid.OAuth,
        client_id: System.get_env("ORCID_CLIENT_ID"),
        client_secret: System.get_env("ORCID_CLIENT_SECRET"),
        redirect_uri: "https://example.com/auth/orcid/callback"

  Credentials must be nonblank strings. The legacy `{:system, "ENV_NAME"}`
  credential form is also supported. Invalid configuration raises `ArgumentError`
  identifying the key, without including credential values.

  Set `site: "https://sandbox.orcid.org"` to use the sandbox. Authorization and
  token endpoints are relative to `site` unless explicitly overridden.
  """
  @behaviour OAuth2.Strategy

  import OAuth2.Client, only: [put_param: 3, merge_params: 2, put_header: 3, put_headers: 2]

  alias OAuth2.{AccessToken, Client, Response}
  alias OAuth2.Strategy.AuthCode
  alias Plug.Conn.Utils

  @defaults [
    strategy: __MODULE__,
    site: "https://orcid.org",
    authorize_url: "/oauth/authorize",
    token_url: "/oauth/token",
    headers: [{"user-agent", "ueberauth-orcid"}]
  ]

  @type token_error :: :token_exchange_failed | :invalid_response | :invalid_json | :invalid_token

  @doc """
  Builds an OAuth2 client, merging options over application configuration.

  The default Httpc adapter verifies TLS and uses bounded connection/request
  timeouts. Explicit request options and custom adapters remain supported.
  """
  @spec client(keyword()) :: Client.t()
  def client(opts \\ []) do
    config = Application.get_env(:ueberauth, __MODULE__, [])

    unless Keyword.keyword?(config) do
      raise ArgumentError, "ORCID OAuth configuration must be a keyword list"
    end

    client_opts =
      @defaults
      |> Keyword.merge(config)
      |> Keyword.merge(opts)
      |> check_credential(:client_id)
      |> check_credential(:client_secret)

    client_opts
    |> Keyword.put(:request_opts, request_opts(Keyword.get(client_opts, :request_opts, [])))
    |> Client.new()
    |> Client.put_serializer("application/json", Ueberauth.json_library())
  end

  @doc """
  Builds the authorization URL. `:redirect_uri` must be supplied in parameters
  or client configuration; parameters take precedence. `opts` are client options.
  """
  @spec authorize_url!(Client.params(), keyword()) :: String.t()
  def authorize_url!(params \\ [], opts \\ []) do
    opts
    |> client()
    |> Client.authorize_url!(params)
  end

  @doc """
  Fetches a resource using the access token as bearer authentication.

  Headers and HTTP options are forwarded to OAuth2. HTTP errors retain the
  dependency's response/error tuples; malformed JSON returns a safe error atom.
  """
  @spec get(AccessToken.t() | String.t(), String.t(), Client.headers(), keyword()) ::
          {:ok, Response.t()} | {:error, Response.t() | OAuth2.Error.t() | token_error()}
  def get(token, url, headers \\ [], opts \\ []) do
    client = client(token: token)
    token = client.token

    if token && header_token?(token.access_token) && bearer?(token.token_type) do
      request(%{client | token: %{token | token_type: "Bearer"}}, :get, url, "", headers, opts)
    else
      {:error, :invalid_token}
    end
  end

  @doc """
  Exchanges a code for `{:ok, %OAuth2.AccessToken{}}` or `{:error, reason}`.

  Options are top-level `:headers` (HTTP headers), `:options` (HTTP options), and
  `:client_options` (client configuration overrides). `:redirect_uri` must be
  provided in parameters or client configuration. Configuration errors raise
  `ArgumentError`; provider failures return only safe atoms, never response data.

  ORCID uses `client_secret_post`: credentials are sent in a POST form, not Basic
  authentication. Authorization headers are removed from token requests and the
  form content type is enforced. Other supplied headers/options are preserved.
  Tokens require a nonblank access token and Bearer token type (omission defaults
  to Bearer). Refresh tokens and expiry are optional; when present, refresh tokens
  must be nonblank strings and expiry must be a nonnegative integer or its string
  representation. Legacy `expires` is accepted when `expires_in` is absent/null.
  """
  @spec get_token(Client.params(), keyword()) :: {:ok, AccessToken.t()} | {:error, token_error()}
  def get_token(params \\ [], options \\ []) do
    client =
      options
      |> Keyword.get(:client_options, [])
      |> client()
      |> get_token(params, Keyword.get(options, :headers, []))

    case request(
           client,
           :post,
           client.token_url,
           client.params,
           [],
           Keyword.get(options, :options, [])
         ) do
      {:ok, %Response{status_code: 200, headers: headers, body: body}} ->
        if json_response?(headers) and is_map(body),
          do: token_from_body(body),
          else: {:error, :invalid_response}

      {:ok, _response} ->
        {:error, :invalid_response}

      {:error, reason} when reason in [:invalid_json, :invalid_response] ->
        {:error, reason}

      {:error, _reason} ->
        {:error, :token_exchange_failed}
    end
  end

  @doc """
  Like `get_token/2`, but returns the token or raises `OAuth2.Error` with a safe
  reason. Uses the same top-level header, HTTP and client options.
  """
  @spec get_token!(Client.params(), keyword()) :: AccessToken.t()
  def get_token!(params \\ [], options \\ []) do
    case get_token(params, options) do
      {:ok, token} -> token
      {:error, reason} -> raise OAuth2.Error, reason: "ORCID token exchange failed (#{reason})"
    end
  end

  @doc false
  @impl true
  def authorize_url(client, params) do
    client
    |> AuthCode.authorize_url(params)
    |> require_param!(:redirect_uri)
  end

  @doc false
  @impl true
  def get_token(client, params, headers) do
    client_headers =
      Enum.map(client.headers, fn {key, value} -> {String.downcase(key), value} end)

    client = %{client | headers: client_headers}

    client =
      if List.keymember?(client_headers, "accept", 0),
        do: client,
        else: put_header(client, "accept", "application/json")

    client =
      client
      |> put_param(:redirect_uri, client.redirect_uri)
      |> merge_params(params)
      |> require_param!(:redirect_uri)
      |> require_param!(:code)
      |> put_param(:grant_type, "authorization_code")
      |> put_param(:client_id, client.client_id)
      |> put_param(:client_secret, client.client_secret)
      |> put_headers(headers)
      |> put_header("content-type", "application/x-www-form-urlencoded")

    headers =
      Enum.reject(client.headers, fn {key, _} -> String.downcase(key) == "authorization" end)

    %{client | headers: headers, token: nil, token_method: :post}
  end

  defp request(client, method, url, body, headers, opts) do
    case method do
      :get -> Client.get(client, url, headers, opts)
      :post -> Client.post(client, url, body, headers, opts)
    end
  rescue
    error ->
      case error do
        %{__struct__: parser}
        when parser in [Jason.DecodeError, Poison.SyntaxError, Poison.ParseError] ->
          {:error, :invalid_json}

        %OAuth2.Error{reason: <<"bad content-type:", _::binary>>} ->
          {:error, :invalid_response}

        _ ->
          reraise error, __STACKTRACE__
      end
  end

  defp json_response?(headers) do
    case List.keyfind(headers, "content-type", 0) do
      {_, content_type} ->
        match?({:ok, "application", "json", _params}, Utils.media_type(content_type))

      nil ->
        false
    end
  end

  defp token_from_body(body) do
    expires_in = if is_nil(body["expires_in"]), do: body["expires"], else: body["expires_in"]

    with true <- header_token?(body["access_token"]),
         true <- is_nil(body["refresh_token"]) or nonblank?(body["refresh_token"]),
         true <- bearer?(body["token_type"]),
         {:ok, expiry} <- expiry(expires_in) do
      token =
        body
        |> Map.put("token_type", "Bearer")
        |> Map.put("expires_in", expiry)
        |> AccessToken.new()

      {:ok, token}
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp header_token?(value) when is_binary(value), do: Regex.match?(~r/\A[!-~]+\z/, value)
  defp header_token?(_value), do: false

  defp bearer?(nil), do: true
  defp bearer?(value) when is_binary(value), do: String.downcase(value) == "bearer"
  defp bearer?(_value), do: false

  defp expiry(nil), do: {:ok, nil}
  defp expiry(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp expiry(value) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, ""} when seconds >= 0 -> {:ok, seconds}
      _ -> {:error, :invalid_token}
    end
  end

  defp expiry(_value), do: {:error, :invalid_token}

  defp require_param!(client, key) do
    unless nonblank?(client.params[Atom.to_string(key)]) do
      raise ArgumentError, "ORCID OAuth requires a nonblank #{inspect(key)}"
    end

    client
  end

  defp request_opts(opts) do
    {adapter, adapter_opts} =
      case Application.get_env(:oauth2, :adapter, Tesla.Adapter.Httpc) do
        {adapter, adapter_opts} -> {adapter, adapter_opts}
        adapter -> {adapter, []}
      end

    if adapter == Tesla.Adapter.Httpc do
      adapter_opts
      |> Keyword.merge(opts)
      |> Keyword.put_new_lazy(:ssl, fn -> :httpc.ssl_verify_host_options(true) end)
      |> Keyword.put_new(:connect_timeout, 5_000)
      |> Keyword.put_new(:timeout, 15_000)
    else
      opts
    end
  end

  defp check_credential(config, key) do
    value =
      case Keyword.get(config, key) do
        {:system, env_key} when is_binary(env_key) and byte_size(env_key) > 0 ->
          if String.contains?(env_key, ["=", <<0>>]), do: nil, else: System.get_env(env_key)

        value ->
          value
      end

    unless nonblank?(value) do
      raise ArgumentError, "ORCID OAuth requires a nonblank #{inspect(key)}"
    end

    Keyword.put(config, key, value)
  end

  defp nonblank?(value), do: is_binary(value) and String.trim(value) != ""
end
