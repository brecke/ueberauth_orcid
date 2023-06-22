defmodule Ueberauth.Strategy.Orcid do
  @moduledoc """
  """

  use Ueberauth.Strategy,
    uid_field: :sub,
    default_scope: "openid email profile",
    send_redirect_uri: true,
    oauth2_module: Ueberauth.Strategy.Orcid.OAuth

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra

  @doc """
  Handles the initial redirect to the orcid authentication page.
  """

  def handle_request!(conn) do
    opts =
      []
      |> with_scopes(conn)
      |> with_state_param(conn)
      |> with_redirect_uri(conn)

    module = option(conn, :oauth2_module)
    redirect!(conn, apply(module, :authorize_url!, [opts]))
  end

  @doc """
  """
  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    module = option(conn, :oauth2_module)
    token = apply(module, :get_token!, [[code: code]])

    if token.access_token == nil do
      set_errors!(conn, [
        error(token.other_params["error"], token.other_params["error_description"])
      ])
    else
      fetch_user(conn, token)
    end
  end

  @doc false
  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  @doc """
  """
  def handle_cleanup!(conn) do
    conn
    |> put_private(:orcid_user, nil)
  end

  @doc """
  Fetches the `:uid` field from the Orcid response.

  This defaults to the option `:uid_field` which in-turn defaults to `:id`
  """
  def uid(conn) do
    conn |> option(:uid_field) |> to_string() |> fetch_uid(conn)
  end

  @doc """
  Includes the credentials from the Orcid response.
  """
  def credentials(conn) do
    token = conn.private.orcid_token
    scope_string = token.other_params["scope"] || ""
    scopes = String.split(scope_string, ",")

    %Credentials{
      token: token.access_token,
      refresh_token: token.refresh_token,
      expires_at: token.expires_at,
      token_type: token.token_type,
      expires: !!token.expires_at,
      scopes: scopes
    }
  end

  @doc """
  Fetches the fields to populate the info section of the `Ueberauth.Auth`
  struct.
  """
  def info(conn) do
    user = conn.private.orcid_user
    allow_private_emails = Keyword.get(options(conn), :allow_private_emails, false)

    %Info{
      name: user["given_name"] <> " " <> user["family_name"],
      nickname: user["name"]
    }
  end

  @doc """
  Stores the raw information (including the token) obtained from the Orcid
  callback.
  """
  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private.orcid_token,
        user: conn.private.orcid_user
      }
    }
  end

  defp fetch_uid(field, conn) do
    conn.private.orcid_user[field]
  end

  defp fetch_user(conn, token) do
    conn = put_private(conn, :orcid_token, token)
    # Will be better with Elixir 1.3 with/else
    case Ueberauth.Strategy.Orcid.OAuth.get(token, "/oauth/userinfo") do
      {:ok, %OAuth2.Response{status_code: 401, body: _body}} ->
        set_errors!(conn, [error("token", "unauthorized")])

      {:ok, %OAuth2.Response{status_code: status_code, body: user}}
      when status_code in 200..399 ->
        put_private(conn, :orcid_user, user)

      {:error, %OAuth2.Error{reason: reason}} ->
        set_errors!(conn, [error("OAuth2", reason)])

      {:error, %OAuth2.Response{body: %{"message" => reason}}} ->
        set_errors!(conn, [error("OAuth2", reason)])

      {:error, _} ->
        set_errors!(conn, [error("OAuth2", "unknown error")])
    end
  end

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
