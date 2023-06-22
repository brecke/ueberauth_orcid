defmodule Ueberauth.Strategy.Orcid do
  @moduledoc """
  """

  use Ueberauth.Strategy,
    uid_field: :id,
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
      name: user["name"],
      description: user["bio"],
      nickname: user["login"],
      email: maybe_fetch_email(user, allow_private_emails),
      location: user["location"],
      image: user["avatar_url"],
      urls: %{
        followers_url: user["followers_url"],
        avatar_url: user["avatar_url"],
        events_url: user["events_url"],
        starred_url: user["starred_url"],
        blog: user["blog"],
        subscriptions_url: user["subscriptions_url"],
        organizations_url: user["organizations_url"],
        gists_url: user["gists_url"],
        following_url: user["following_url"],
        api_url: user["url"],
        html_url: user["html_url"],
        received_events_url: user["received_events_url"],
        repos_url: user["repos_url"]
      }
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

  defp fetch_uid("email", conn) do
    # private email will not be available as :email and must be fetched
    allow_private_emails = Keyword.get(options(conn), :allow_private_emails, false)
    fetch_email!(conn.private.orcid_user.user, allow_private_emails)
  end

  defp fetch_uid(field, conn) do
    conn.private.orcid_user[field]
  end

  defp fetch_email!(user, allow_private_emails) do
    maybe_fetch_email(user, allow_private_emails) ||
      raise "Unable to access the user's email address"
  end

  defp maybe_fetch_email(user, _allow_private_emails) do
    user["email"] ||
      maybe_get_primary_email(user)
  end

  defp maybe_get_primary_email(user) do
    if user["emails"] && Enum.count(user["emails"]) > 0 do
      Enum.find(user["emails"], & &1["primary"])["email"]
    end
  end

  defp fetch_user(conn, token) do
    conn = put_private(conn, :orcid_token, token)
    # Will be better with Elixir 1.3 with/else
    case Ueberauth.Strategy.Orcid.OAuth.get(token, "/user") do
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
