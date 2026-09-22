defmodule OrcidCallbackTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Ueberauth.Strategy.Orcid.OAuth

  @callback_url "https://public.example/auth/orcid/callback"
  @client_redirect "https://client.example/different/callback"
  @sub "0000-0000-0000-0001"
  @access_token "private-access-token-fixture"
  @refresh_token "private-refresh-token-fixture"
  @code "private-code-fixture"
  @client_secret "private-client-secret-fixture"
  @provider_secret "private-provider-description-fixture"
  @token %{"access_token" => @access_token, "token_type" => "bearer"}
  @user %{"sub" => @sub, "given_name" => "Ada", "family_name" => "Example"}

  defmodule CustomOAuth do
    alias Ueberauth.Strategy.Orcid.OAuth

    def authorize_url!(params, client_options) do
      OAuth.authorize_url!(Keyword.put(params, :prompt, "login"), client_options)
    end

    def get_token(params, options) do
      headers = [{"x-custom-token", "enabled"} | Keyword.get(options, :headers, [])]
      OAuth.get_token(params, Keyword.put(options, :headers, headers))
    end

    def get(token, url, headers, options) do
      OAuth.get(token, url, [{"x-custom-profile", "enabled"} | headers], options)
    end
  end

  defmodule InvalidTokenOAuth do
    alias Ueberauth.Strategy.Orcid.OAuth

    defdelegate authorize_url!(params, options), to: OAuth
    defdelegate get(token, url, headers, options), to: OAuth

    def get_token(params, options) do
      with {:ok, token} <- OAuth.get_token(params, options) do
        {:ok, %{token | access_token: []}}
      end
    end
  end

  setup do
    settings = [
      {:ueberauth, Ueberauth,
       [
         providers: [orcid: {Ueberauth.Strategy.Orcid, [callback_url: @callback_url]}],
         json_library: Jason
       ]},
      {:ueberauth, OAuth,
       [client_id: "test-client", client_secret: @client_secret, redirect_uri: @client_redirect]},
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

  test "missing state, mismatched state and missing browser cookie fail before HTTP", %{
    routes: routes
  } do
    request = request(routes)
    state = state(request)

    for {params, cookies} <- [
          {%{"code" => @code}, request},
          {%{"code" => @code, "state" => "different-state"}, request},
          {%{"code" => @code, "state" => state}, conn(:get, "/")}
        ] do
      callback =
        callback_conn(params)
        |> put_private(:orcid_token, @access_token)
        |> put_private(:orcid_user, @user)
        |> finish_callback(cookies, routes)

      assert_failure(callback, "csrf_attack")
    end
  end

  test "matching-state denial and provider errors take precedence over missing code", %{
    routes: routes
  } do
    for {params, key} <- [
          {%{"error" => "access_denied", "error_description" => @provider_secret},
           "access_denied"},
          {%{"error" => "server_error", "error_description" => @provider_secret},
           "provider_error"},
          {%{}, "missing_code"},
          {%{"code" => "  "}, "missing_code"}
        ] do
      request = request(routes)
      callback = callback(request, routes, Map.put(params, "state", state(request)))
      assert_failure(callback, key)
      assert callback.resp_cookies["ueberauth.state_param"].max_age == 0
    end
  end

  test "a consumed code is rejected by the provider and a cleared cookie independently blocks replay",
       %{
         routes: routes
       } do
    Process.put(:orcid_consumed_code, false)

    Tesla.Mock.mock(fn
      %{method: :post, url: "https://orcid.org/oauth/token", body: body} ->
        send(self(), {:http, :token})
        assert URI.decode_query(body)["code"] == @code

        if Process.get(:orcid_consumed_code) do
          json_response(400, %{
            "error" => "invalid_grant",
            "error_description" => @provider_secret
          })
        else
          Process.put(:orcid_consumed_code, true)
          json_response(200, @token)
        end

      %{method: :get, url: "https://orcid.org/oauth/userinfo"} ->
        send(self(), {:http, :userinfo})
        json_response(200, @user)
    end)

    request = request(routes)
    first = callback(request, routes)
    assert_auth(first)
    assert_calls([:token, :userinfo])

    callback(request, routes) |> assert_failure("token_exchange_failed")
    assert_calls([:token])

    callback_conn(%{"code" => @code, "state" => state(request)})
    |> finish_callback(first, routes)
    |> assert_failure("csrf_attack")

    assert_calls([])
  end

  test "a complete custom OAuth module controls authorization, token and userinfo exchanges" do
    routes = routes(oauth2_module: CustomOAuth, callback_url: @callback_url)

    Tesla.Mock.mock(fn
      %{method: :post, url: "https://orcid.org/oauth/token", headers: headers} ->
        send(self(), {:http, :token})
        assert {"x-custom-token", "enabled"} in headers
        json_response(200, @token)

      %{method: :get, url: "https://orcid.org/oauth/userinfo", headers: headers} ->
        send(self(), {:http, :userinfo})
        assert {"x-custom-profile", "enabled"} in headers
        assert {"authorization", "Bearer " <> @access_token} in headers
        json_response(200, @user)
    end)

    request = request(routes)
    assert authorization_params(request)["prompt"] == "login"
    auth = request |> callback(routes) |> assert_auth()
    assert auth.uid == @sub
    assert_calls([:token, :userinfo])
  end

  test "an explicit callback overrides client redirect and untrusted forwarded headers", %{
    routes: routes
  } do
    mock_redirect_exchange(@callback_url)

    request =
      conn(:get, "/auth/orcid")
      |> put_req_header("x-forwarded-host", "attacker.example")
      |> put_req_header("x-forwarded-proto", "http")
      |> then(&request(routes, &1))

    assert authorization_params(request)["redirect_uri"] == @callback_url

    callback_conn(%{"code" => @code, "state" => state(request)})
    |> put_req_header("x-forwarded-host", "attacker.example")
    |> put_req_header("x-forwarded-proto", "http")
    |> finish_callback(request, routes)
    |> assert_auth()

    assert_calls([:token, :userinfo])
  end

  test "a trusted proxy-normalized connection uses the same public URI for both exchanges" do
    routes = routes([])
    expected = "https://proxy.example:8443/auth/orcid/callback"
    mock_redirect_exchange(expected)

    request = request(routes, trusted_proxy(conn(:get, "http://internal/auth/orcid")))
    assert authorization_params(request)["redirect_uri"] == expected

    callback_conn(%{"code" => @code, "state" => state(request)})
    |> trusted_proxy()
    |> finish_callback(request, routes)
    |> assert_auth()

    assert_calls([:token, :userinfo])
  end

  for stage <- [:token, :userinfo],
      boundary <- [
        400,
        401,
        403,
        429,
        500,
        302,
        307,
        :timeout,
        :connection,
        :malformed_json,
        :html
      ] do
    @tag stage: stage, boundary: boundary
    test "#{stage} rejects #{boundary} without retries or leaked provider data", %{
      routes: routes,
      stage: stage,
      boundary: boundary
    } do
      response = boundary_response(boundary, stage)

      if stage == :token do
        mock_responses(response, json_response(200, @user))
      else
        mock_responses(json_response(200, @token), response)
      end

      request(routes) |> callback(routes) |> assert_failure()
      assert_calls(if(stage == :token, do: [:token], else: [:token, :userinfo]))
    end
  end

  for {label, body} <- [
        {"missing", %{}},
        {"empty", %{"access_token" => ""}},
        {"blank", %{"access_token" => " \t"}},
        {"wrong type", %{"access_token" => 12}},
        {"JSON list", []},
        {"JSON scalar", "not-a-token-object"},
        {"JSON null", nil}
      ] do
    test "token response with #{label} identity cannot authenticate", %{routes: routes} do
      mock_responses(json_response(200, unquote(Macro.escape(body))), json_response(200, @user))
      request(routes) |> callback(routes) |> assert_failure("token_exchange_failed")
      assert_calls([:token])
    end
  end

  test "text/plain token-shaped responses are not accepted as JSON tokens", %{routes: routes} do
    response = %Tesla.Env{
      status: 200,
      headers: [{"content-type", "text/plain"}],
      body: "access_token=" <> @access_token
    }

    mock_responses(response, json_response(200, @user))
    request(routes) |> callback(routes) |> assert_failure("token_exchange_failed")
    assert_calls([:token])
  end

  test "a non-JSON response decoded into a profile map still cannot authenticate", %{
    routes: routes
  } do
    response = %Tesla.Env{
      status: 200,
      headers: [{"content-type", "application/x-www-form-urlencoded"}],
      body: URI.encode_query(@user)
    }

    mock_responses(json_response(200, @token), response)
    request(routes) |> callback(routes) |> assert_failure("userinfo_failed")
    assert_calls([:token, :userinfo])
  end

  test "an invalid AccessToken returned by a custom module cannot reach userinfo" do
    routes = routes(oauth2_module: InvalidTokenOAuth, callback_url: @callback_url)
    mock_responses(json_response(200, @token), json_response(200, @user))
    request(routes) |> callback(routes) |> assert_failure("invalid_token")
    assert_calls([:token])
  end

  for {label, body} <- [
        {"missing subject", %{}},
        {"empty subject", %{"sub" => ""}},
        {"blank subject", %{"sub" => " \t"}},
        {"wrong-type subject", %{"sub" => 12}},
        {"list", []},
        {"scalar", "not-a-profile-object"},
        {"null", nil}
      ] do
    test "userinfo with #{label} cannot authenticate", %{routes: routes} do
      mock_responses(json_response(200, @token), json_response(200, unquote(Macro.escape(body))))
      request(routes) |> callback(routes) |> assert_failure()
      assert_calls([:token, :userinfo])
    end
  end

  test "userinfo must be HTTP 200 even when a different success status contains a valid profile",
       %{
         routes: routes
       } do
    mock_responses(json_response(200, @token), json_response(201, @user))
    request(routes) |> callback(routes) |> assert_failure("userinfo_failed")
    assert_calls([:token, :userinfo])
  end

  test "a configured UID still requires both a subject and a nonblank configured claim" do
    routes = routes(uid_field: :researcher_id, callback_url: @callback_url)

    for user <- [
          %{"researcher_id" => "local-id"},
          Map.put(@user, "researcher_id", " "),
          Map.put(@user, "researcher_id", []),
          @user
        ] do
      mock_responses(json_response(200, @token), json_response(200, user))
      request(routes) |> callback(routes) |> assert_failure("invalid_identity")
      assert_calls([:token, :userinfo])
    end

    mock_responses(
      json_response(200, @token),
      json_response(200, Map.put(@user, "researcher_id", "local-id"))
    )

    auth = request(routes) |> callback(routes) |> assert_auth()
    assert auth.uid == "local-id"
    assert_calls([:token, :userinfo])
  end

  test "optional names preserve valid claims and Unicode without inventing missing email", %{
    routes: routes
  } do
    for {claims, name, nickname} <- [
          {%{}, nil, nil},
          {%{"email" => "unverified@example.test"}, nil, nil},
          {%{"given_name" => "  ", "family_name" => "", "name" => " Credit Name "}, "Credit Name",
           "Credit Name"},
          {%{"given_name" => [], "family_name" => 42, "name" => "Credit Name"}, "Credit Name",
           "Credit Name"},
          {%{"given_name" => " Zoë ", "family_name" => " 李 ", "name" => " Z. 李 "}, "Zoë 李",
           "Z. 李"},
          {%{"given_name" => "Ada", "name" => %{}}, "Ada", nil},
          {%{"family_name" => "Example", "name" => "  "}, "Example", nil}
        ] do
      user = Map.put(claims, "sub", @sub)
      mock_responses(json_response(200, @token), json_response(200, user))
      auth = request(routes) |> callback(routes) |> assert_auth()
      assert auth.info.name == name
      assert auth.info.nickname == nickname
      assert is_nil(auth.info.email)
      assert auth.extra.raw_info.user == user
      assert auth.extra.raw_info.token.access_token == @access_token
      assert is_nil(auth.credentials.refresh_token)
      refute auth.credentials.expires
      assert is_nil(auth.credentials.expires_at)
      assert_calls([:token, :userinfo])
    end
  end

  test "credentials expose granted space-delimited scopes, never merely requested scopes", %{
    routes: routes
  } do
    for {scope, expected} <- [
          {:missing, []},
          {"", []},
          {"openid   profile\temail", ["openid", "profile", "email"]},
          {"openid", ["openid"]}
        ] do
      token = if scope == :missing, do: @token, else: Map.put(@token, "scope", scope)
      mock_responses(json_response(200, token), json_response(200, @user))
      request = request(routes)
      assert authorization_params(request)["scope"] == "openid email profile"
      auth = request |> callback(routes) |> assert_auth()
      assert auth.credentials.scopes == expected
      assert_calls([:token, :userinfo])
    end
  end

  test "optional refresh and expiration survive credential mapping and raw token retention", %{
    routes: routes
  } do
    token = Map.merge(@token, %{"refresh_token" => @refresh_token, "expires_in" => 3600})
    mock_responses(json_response(200, token), json_response(200, @user))
    before = System.system_time(:second)
    auth = request(routes) |> callback(routes) |> assert_auth()
    assert auth.credentials.refresh_token == @refresh_token
    assert auth.credentials.expires
    assert auth.credentials.expires_at >= before + 3600
    assert auth.credentials.expires_at <= System.system_time(:second) + 3600
    assert auth.extra.raw_info.token.refresh_token == @refresh_token
    assert auth.extra.raw_info.token.access_token == auth.credentials.token
    assert_calls([:token, :userinfo])
  end

  defp routes(options) do
    Application.put_env(:ueberauth, Ueberauth,
      providers: [orcid: {Ueberauth.Strategy.Orcid, options}],
      json_library: Jason
    )

    Ueberauth.init()
  end

  defp request(routes, connection \\ conn(:get, "/auth/orcid")) do
    connection |> fetch_query_params() |> Ueberauth.call(routes)
  end

  defp callback(request, routes, params \\ nil) do
    params = params || %{"code" => @code, "state" => state(request)}
    params |> callback_conn() |> finish_callback(request, routes)
  end

  defp callback_conn(params) do
    conn(:get, "/auth/orcid/callback?" <> URI.encode_query(params))
  end

  defp finish_callback(connection, cookies, routes) do
    connection
    |> fetch_query_params()
    |> recycle_cookies(cookies)
    |> fetch_cookies()
    |> init_test_session(%{})
    |> Ueberauth.call(routes)
  end

  defp state(request), do: request.resp_cookies["ueberauth.state_param"].value

  defp authorization_params(request) do
    [location] = get_resp_header(request, "location")
    location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
  end

  defp trusted_proxy(connection) do
    connection
    |> put_req_header("x-forwarded-host", "proxy.example")
    |> put_req_header("x-forwarded-proto", "https")
    |> put_req_header("x-forwarded-port", "8443")
    |> Plug.RewriteOn.call([:x_forwarded_host, :x_forwarded_proto, :x_forwarded_port])
  end

  defp json_response(status, body) do
    %Tesla.Env{
      status: status,
      headers: [{"content-type", "application/json"}],
      body: Jason.encode!(body)
    }
  end

  defp boundary_response(status, stage) when is_integer(status) do
    body = if stage == :token, do: @token, else: @user

    body =
      if status >= 400 do
        Map.merge(body, %{"error" => "provider_error", "error_description" => @provider_secret})
      else
        body
      end

    json_response(status, body)
  end

  defp boundary_response(:timeout, _stage), do: {:error, :timeout}
  defp boundary_response(:connection, _stage), do: {:error, :econnrefused}

  defp boundary_response(:malformed_json, _stage) do
    %Tesla.Env{
      status: 200,
      headers: [{"content-type", "application/json"}],
      body: "{\"secret\":\"" <> @provider_secret
    }
  end

  defp boundary_response(:html, _stage) do
    %Tesla.Env{
      status: 200,
      headers: [{"content-type", "text/html"}],
      body: "<html>" <> @provider_secret <> "</html>"
    }
  end

  defp mock_responses(token, userinfo) do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://orcid.org/oauth/token"} ->
        send(self(), {:http, :token})
        token

      %{method: :get, url: "https://orcid.org/oauth/userinfo"} ->
        send(self(), {:http, :userinfo})
        userinfo
    end)
  end

  defp mock_redirect_exchange(expected) do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://orcid.org/oauth/token", body: body} ->
        send(self(), {:http, :token})
        assert URI.decode_query(body)["redirect_uri"] == expected
        json_response(200, @token)

      %{method: :get, url: "https://orcid.org/oauth/userinfo"} ->
        send(self(), {:http, :userinfo})
        json_response(200, @user)
    end)
  end

  defp assert_calls(stages) do
    Enum.each(stages, fn stage -> assert_receive {:http, ^stage} end)
    refute_receive {:http, _stage}, 0
  end

  defp assert_cleaned(connection) do
    assert is_nil(connection.private[:orcid_token])
    assert is_nil(connection.private[:orcid_user])
  end

  defp assert_failure(connection, key \\ nil) do
    refute Map.has_key?(connection.assigns, :ueberauth_auth)
    assert %{errors: [_ | _] = errors} = connection.assigns.ueberauth_failure
    if key, do: assert(Enum.any?(errors, &(&1.message_key == key)))

    for secret <- [@access_token, @refresh_token, @code, @client_secret, @provider_secret] do
      refute inspect(connection.assigns.ueberauth_failure) =~ secret
    end

    assert_cleaned(connection)
    connection
  end

  defp assert_auth(connection) do
    refute Map.has_key?(connection.assigns, :ueberauth_failure)
    assert %Ueberauth.Auth{} = auth = connection.assigns.ueberauth_auth
    assert connection.resp_cookies["ueberauth.state_param"].max_age == 0
    assert_cleaned(connection)
    auth
  end
end
