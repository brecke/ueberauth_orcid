defmodule Ueberauth.Strategy.Orcid do
  @moduledoc """
  ORCID authorization-code authentication through Ueberauth.

  The default identity is the nonblank `sub` claim. Optional name claims may be
  absent; email is not mapped or used as an identity fallback. Granted scopes,
  not requested scopes, populate the returned credentials.

  A custom `:oauth2_module` must implement `authorize_url!/2`, `get_token/2`
  returning a token result tuple, and `get/4` returning an OAuth2 response tuple.
  All three authentication stages use that module.

  Configure an explicit trusted `:callback_url`. Without it, Ueberauth derives
  the URL using connection data and Host/forwarded headers; the host application
  must validate the host and strip untrusted forwarding headers at its proxy
  boundary. With `:send_redirect_uri` disabled, configure the OAuth client's
  redirect URI explicitly.

  Credentials and `extra.raw_info.token` intentionally contain secrets.
  Never log the complete auth struct or raw provider data.
  """

  use Ueberauth.Strategy,
    uid_field: :sub,
    default_scope: "openid email profile",
    send_redirect_uri: true,
    oauth2_module: Ueberauth.Strategy.Orcid.OAuth

  alias Plug.Conn.Utils
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra
  alias Ueberauth.Auth.Info

  @doc "Redirects to ORCID with Ueberauth's state and the effective callback URI."
  @spec handle_request!(Plug.Conn.t()) :: Plug.Conn.t()
  def handle_request!(conn) do
    params =
      []
      |> with_scopes(conn)
      |> with_state_param(conn)
      |> with_redirect_uri(conn)

    module = option(conn, :oauth2_module)
    redirect!(conn, module.authorize_url!(params, []))
  end

  @doc "Exchanges the code and validates userinfo after Ueberauth checks state."
  @spec handle_callback!(Plug.Conn.t()) :: Plug.Conn.t()
  def handle_callback!(%Plug.Conn{params: %{"error" => reason}} = conn) do
    if reason == "access_denied" do
      set_errors!(conn, [error("access_denied", "ORCID authorization was denied")])
    else
      set_errors!(conn, [error("provider_error", "ORCID authorization failed")])
    end
  end

  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) when is_binary(code) do
    if is_nil(text(code)) do
      set_errors!(conn, [error("missing_code", "No authorization code received")])
    else
      module = option(conn, :oauth2_module)
      params = with_redirect_uri([code: code], conn)

      with {:ok, %OAuth2.AccessToken{} = token} <- module.get_token(params, []),
           true <- valid_token?(token) do
        fetch_user(conn, token)
      else
        false ->
          set_errors!(conn, [error("invalid_token", "ORCID returned an invalid token")])

        _ ->
          set_errors!(conn, [error("token_exchange_failed", "ORCID token exchange failed")])
      end
    end
  end

  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No authorization code received")])
  end

  @doc "Removes temporary provider data after both successful and failed callbacks."
  @spec handle_cleanup!(Plug.Conn.t()) :: Plug.Conn.t()
  def handle_cleanup!(conn) do
    %{conn | private: Map.drop(conn.private, [:orcid_user, :orcid_token])}
  end

  @doc "Returns the validated `:uid_field` claim, which defaults to `:sub`."
  @spec uid(Plug.Conn.t()) :: String.t()
  def uid(conn) do
    conn.private.orcid_user[to_string(option(conn, :uid_field))]
  end

  @doc "Returns granted scopes and the provider's optional refresh/expiry values."
  @spec credentials(Plug.Conn.t()) :: Credentials.t()
  def credentials(conn) do
    token = conn.private.orcid_token

    scopes =
      case text(token.other_params["scope"]) do
        nil -> []
        scope -> String.split(scope)
      end

    %Credentials{
      token: token.access_token,
      refresh_token: token.refresh_token,
      expires_at: token.expires_at,
      token_type: token.token_type,
      expires: not is_nil(token.expires_at),
      scopes: scopes
    }
  end

  @doc """
  Joins valid given/family names, falling back to the credit-name claim `name`.
  The credit name remains the nickname. Missing names and email remain nil.
  """
  @spec info(Plug.Conn.t()) :: Info.t()
  def info(conn) do
    user = conn.private.orcid_user

    name =
      [text(user["given_name"]), text(user["family_name"])]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> text()

    %Info{name: name || text(user["name"]), nickname: text(user["name"])}
  end

  @doc """
  Returns raw userinfo and the token for compatibility with existing consumers.
  This data is sensitive even after temporary connection fields are cleaned.
  """
  @spec extra(Plug.Conn.t()) :: Extra.t()
  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private.orcid_token,
        user: conn.private.orcid_user
      }
    }
  end

  defp fetch_user(conn, token) do
    module = option(conn, :oauth2_module)

    case module.get(token, "/oauth/userinfo", [], []) do
      {:ok, %OAuth2.Response{status_code: 200, body: user, headers: headers}}
      when is_map(user) and is_list(headers) ->
        cond do
          not json_response?(headers) ->
            set_errors!(conn, [error("userinfo_failed", "ORCID userinfo request failed")])

          is_nil(text(user["sub"])) or
              is_nil(text(user[to_string(option(conn, :uid_field))])) ->
            set_errors!(conn, [error("invalid_identity", "ORCID returned an invalid identity")])

          true ->
            conn
            |> put_private(:orcid_token, token)
            |> put_private(:orcid_user, user)
        end

      _ ->
        set_errors!(conn, [error("userinfo_failed", "ORCID userinfo request failed")])
    end
  end

  defp valid_token?(token) do
    header_value?(token.access_token) and header_value?(token.token_type) and
      (is_nil(token.refresh_token) or is_binary(token.refresh_token)) and
      (is_nil(token.expires_at) or is_integer(token.expires_at)) and
      is_map(token.other_params)
  end

  defp header_value?(value) when is_binary(value), do: Regex.match?(~r/\A[!-~]+\z/, value)
  defp header_value?(_value), do: false

  defp json_response?(headers) do
    Enum.any?(headers, fn
      {key, value} when is_binary(key) and is_binary(value) ->
        String.downcase(key) == "content-type" and
          match?({:ok, "application", "json", _}, Utils.media_type(value))

      _ ->
        false
    end)
  end

  defp text(value) when is_binary(value) do
    if String.valid?(value) do
      case String.trim(value) do
        "" -> nil
        value -> value
      end
    end
  end

  defp text(_value), do: nil

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end

  defp with_scopes(opts, conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)

    opts |> Keyword.put(:scope, scopes)
  end

  defp with_redirect_uri(opts, conn) do
    if option(conn, :send_redirect_uri) do
      opts |> Keyword.put(:redirect_uri, callback_url(conn))
    else
      opts
    end
  end
end
