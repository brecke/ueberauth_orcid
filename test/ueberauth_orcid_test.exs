defmodule UeberauthOrcidTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Ueberauth.Strategy.Orcid.OAuth

  @callback_url "https://client.example/auth/orcid/callback"

  setup do
    settings = [
      {:ueberauth, Ueberauth,
       [
         providers: [orcid: {Ueberauth.Strategy.Orcid, [callback_url: @callback_url]}],
         json_library: Jason
       ]},
      {:ueberauth, Ueberauth.Strategy.Orcid.OAuth,
       [client_id: "test-client", client_secret: "test-secret", redirect_uri: @callback_url]},
      {:oauth2, :adapter, Tesla.Mock}
    ]

    previous =
      Enum.map(settings, fn {app, key, _value} ->
        {app, key, Application.fetch_env(app, key)}
      end)

    on_exit(fn ->
      Enum.each(previous, fn
        {app, key, {:ok, value}} -> Application.put_env(app, key, value)
        {app, key, :error} -> Application.delete_env(app, key)
      end)
    end)

    Enum.each(settings, fn {app, key, value} -> Application.put_env(app, key, value) end)
    Tesla.Mock.mock(fn _request -> flunk("unexpected HTTP exchange") end)

    %{routes: Ueberauth.init()}
  end

  test "request redirects to ORCID with callback, scopes and cookie-backed state", %{
    routes: routes
  } do
    request = conn(:get, "/auth/orcid") |> fetch_query_params() |> Ueberauth.call(routes)
    [location] = get_resp_header(request, "location")
    uri = URI.parse(location)
    params = URI.decode_query(uri.query)

    assert request.status == 302
    assert uri.scheme == "https"
    assert uri.host == "orcid.org"
    assert uri.path == "/oauth/authorize"
    assert params["client_id"] == "test-client"
    assert params["redirect_uri"] == @callback_url
    assert params["response_type"] == "code"
    assert params["scope"] == "openid email profile"
    assert params["state"] == request.resp_cookies["ueberauth.state_param"].value
    assert is_binary(params["state"]) and byte_size(params["state"]) > 0
  end

  test "matching request state exchanges code and maps userinfo into authentication", %{
    routes: routes
  } do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://orcid.org/oauth/token", body: body} ->
        params = URI.decode_query(body)
        assert params["code"] == "test-code"
        assert params["grant_type"] == "authorization_code"
        assert params["redirect_uri"] == @callback_url

        %Tesla.Env{
          status: 200,
          headers: [{"content-type", "application/json"}],
          body:
            Jason.encode!(%{
              access_token: "test-access-token",
              refresh_token: "test-refresh-token",
              token_type: "bearer",
              expires_in: 3600,
              scope: "openid"
            })
        }

      %{method: :get, url: "https://orcid.org/oauth/userinfo", headers: headers} ->
        assert {"authorization", "Bearer test-access-token"} in headers

        %Tesla.Env{
          status: 200,
          headers: [{"content-type", "application/json"}],
          body:
            Jason.encode!(%{
              sub: "0000-0000-0000-0001",
              given_name: "Ada",
              family_name: "Example",
              name: "A. Example"
            })
        }

      _request ->
        flunk("unexpected HTTP exchange")
    end)

    request = conn(:get, "/auth/orcid") |> fetch_query_params() |> Ueberauth.call(routes)
    state = request.resp_cookies["ueberauth.state_param"].value
    started_at = System.system_time(:second)

    callback =
      conn(:get, "/auth/orcid/callback?" <> URI.encode_query(%{code: "test-code", state: state}))
      |> fetch_query_params()
      |> recycle_cookies(request)
      |> fetch_cookies()
      |> init_test_session(%{})
      |> Ueberauth.call(routes)

    refute Map.has_key?(callback.assigns, :ueberauth_failure)
    auth = callback.assigns.ueberauth_auth
    assert auth.provider == :orcid
    assert auth.uid == "0000-0000-0000-0001"
    assert auth.info.name == "Ada Example"
    assert auth.info.nickname == "A. Example"
    assert auth.extra.raw_info.user["given_name"] == "Ada"
    assert auth.extra.raw_info.user["family_name"] == "Example"
    assert auth.credentials.token == "test-access-token"
    assert auth.credentials.refresh_token == "test-refresh-token"
    assert auth.credentials.token_type == "Bearer"
    assert auth.credentials.scopes == ["openid"]
    assert auth.credentials.expires
    assert auth.credentials.expires_at >= started_at + 3600
    assert auth.credentials.expires_at <= System.system_time(:second) + 3600
    assert callback.resp_cookies["ueberauth.state_param"].max_age == 0
  end

  test "mismatched state fails before any HTTP exchange", %{routes: routes} do
    request = conn(:get, "/auth/orcid") |> fetch_query_params() |> Ueberauth.call(routes)

    callback =
      conn(:get, "/auth/orcid/callback?code=test-code&state=mismatched")
      |> fetch_query_params()
      |> recycle_cookies(request)
      |> fetch_cookies()
      |> init_test_session(%{})
      |> Ueberauth.call(routes)

    refute Map.has_key?(callback.assigns, :ueberauth_auth)
    assert [%{message_key: "csrf_attack"}] = callback.assigns.ueberauth_failure.errors
  end

  @tag capture_log: true
  test "default HTTP transport rejects an untrusted TLS certificate" do
    Application.delete_env(:oauth2, :adapter)

    certificate =
      :public_key.pkix_test_data(%{
        root: [digest: :sha256, key: {:rsa, 2048, 65_537}],
        peer: [digest: :sha256, key: {:rsa, 2048, 65_537}]
      })

    {:ok, listener} =
      :ssl.listen(0, certificate ++ [ip: {127, 0, 0, 1}, active: false, reuseaddr: true])

    on_exit(fn -> :ssl.close(listener) end)
    {:ok, {_, port}} = :ssl.sockname(listener)

    server =
      Task.async(fn ->
        {:ok, socket} = :ssl.transport_accept(listener, 5_000)

        case :ssl.handshake(socket, 5_000) do
          {:ok, socket} ->
            :ssl.close(socket)
            :accepted

          error ->
            error
        end
      end)

    assert {:error, %OAuth2.Error{reason: :econnrefused}} =
             OAuth.get(
               %OAuth2.AccessToken{access_token: "test-access-token"},
               "https://localhost:#{port}/oauth/userinfo"
             )

    assert {:error, {:tls_alert, {:unknown_ca, _}}} = Task.await(server)
  end
end
