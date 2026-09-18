defmodule OrcidOAuthTest do
  use ExUnit.Case, async: false

  alias Ueberauth.Strategy.Orcid.OAuth

  @callback_url "https://client.example/auth/orcid/callback"
  @credentials [
    client_id: "test-client",
    client_secret: "test-secret",
    redirect_uri: @callback_url
  ]

  defmodule WrappedJSON do
    def encode!(value), do: Jason.encode!(value)
    def decode!("wrapped:" <> body), do: Jason.decode!(body)
  end

  defmodule BrokenJSON do
    def encode!(value), do: Jason.encode!(value)
    def decode!(_body), do: raise(ArgumentError, "serializer programming failure")
  end

  setup do
    settings = [
      {:ueberauth, Ueberauth, [json_library: Jason]},
      {:ueberauth, OAuth, @credentials},
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
    :ok
  end

  test "site-only sandbox configuration controls both OAuth endpoints" do
    Application.put_env(
      :ueberauth,
      OAuth,
      Keyword.put(@credentials, :site, "https://sandbox.orcid.org")
    )

    uri = OAuth.authorize_url!(scope: "openid", state: "state") |> URI.parse()
    assert uri.host == "sandbox.orcid.org"
    assert uri.path == "/oauth/authorize"

    assert URI.decode_query(uri.query) == %{
             "client_id" => "test-client",
             "redirect_uri" => @callback_url,
             "response_type" => "code",
             "scope" => "openid",
             "state" => "state"
           }

    Tesla.Mock.mock(fn request ->
      assert request.url == "https://sandbox.orcid.org/oauth/token"
      assert URI.decode_query(request.body)["redirect_uri"] == @callback_url
      json(%{"access_token" => "sandbox-token"})
    end)

    assert {:ok, %OAuth2.AccessToken{access_token: "sandbox-token"}} =
             OAuth.get_token(code: "code")
  end

  test "explicit absolute endpoints and request redirect take precedence" do
    callback = "https://client.example/alternate"

    client_options = [
      site: "https://sandbox.orcid.org",
      authorize_url: "https://authorize.example/consent",
      token_url: "https://token.example/exchange"
    ]

    uri = OAuth.authorize_url!([redirect_uri: callback], client_options) |> URI.parse()
    assert {uri.host, uri.path} == {"authorize.example", "/consent"}
    assert URI.decode_query(uri.query)["redirect_uri"] == callback

    Tesla.Mock.mock(fn request ->
      assert request.url == "https://token.example/exchange"
      assert URI.decode_query(request.body)["redirect_uri"] == callback
      json(%{"access_token" => "endpoint-token"})
    end)

    assert {:ok, %OAuth2.AccessToken{access_token: "endpoint-token"}} =
             OAuth.get_token([code: "code", redirect_uri: callback],
               client_options: client_options
             )
  end

  test "authorization and token exchange require an explicit effective redirect" do
    Application.put_env(:ueberauth, OAuth, Keyword.delete(@credentials, :redirect_uri))
    assert_raise ArgumentError, fn -> OAuth.authorize_url!() end
    assert_raise ArgumentError, fn -> OAuth.get_token(code: "code") end

    uri = OAuth.authorize_url!(redirect_uri: @callback_url) |> URI.parse()
    assert URI.decode_query(uri.query)["redirect_uri"] == @callback_url

    Tesla.Mock.mock(fn request ->
      assert URI.decode_query(request.body)["redirect_uri"] == @callback_url
      json(%{"access_token" => "explicit-redirect-token"})
    end)

    assert {:ok, %OAuth2.AccessToken{access_token: "explicit-redirect-token"}} =
             OAuth.get_token(code: "code", redirect_uri: @callback_url)
  end

  test "top-level options reach HTTP and token credentials appear only in the POST form" do
    Tesla.Mock.mock(fn request ->
      assert request.method == :post
      assert request.url == "https://sandbox.orcid.org/oauth/token"
      assert request.query == %{}
      assert URI.parse(request.url).query == nil

      assert URI.decode_query(request.body) == %{
               "code" => "private-code",
               "grant_type" => "authorization_code",
               "client_id" => "override-client",
               "client_secret" => "override-secret",
               "redirect_uri" => @callback_url
             }

      assert {"content-type", "application/x-www-form-urlencoded"} in request.headers
      assert {"x-request", "request-header"} in request.headers
      assert {"x-client", "client-header"} in request.headers
      assert {"accept", "application/json; charset=utf-8"} in request.headers
      refute Enum.any?(request.headers, fn {key, _value} -> key == "authorization" end)
      assert request.opts[:adapter][:timeout] == 222
      assert request.opts[:adapter][:connect_timeout] == 111
      assert request.opts[:adapter][:custom_transport_option] == :preserved
      json(%{"access_token" => "options-token"})
    end)

    assert %OAuth2.AccessToken{access_token: "options-token"} =
             OAuth.get_token!([code: "private-code"],
               headers: [{"x-request", "request-header"}, {"Authorization", "Basic unwanted"}],
               options: [timeout: 222, custom_transport_option: :preserved],
               client_options: [
                 site: "https://sandbox.orcid.org",
                 client_id: "override-client",
                 client_secret: "override-secret",
                 token_method: :get,
                 headers: [
                   {"x-client", "client-header"},
                   {"Content-Type", "application/json"},
                   {"Accept", "application/json; charset=utf-8"}
                 ],
                 request_opts: [timeout: 999, connect_timeout: 111]
               ]
             )
  end

  test "userinfo uses bearer authentication without credentials in its URL or body" do
    Tesla.Mock.mock(fn request ->
      assert request.method == :get
      assert request.url == "https://orcid.org/oauth/userinfo"
      assert request.query == %{}
      assert request.body == ""

      assert Enum.filter(request.headers, fn {key, _value} -> key == "authorization" end) ==
               [{"authorization", "Bearer user-token"}]

      assert {"x-resource", "resource-header"} in request.headers
      assert request.opts[:adapter][:timeout] == 123
      refute inspect(request) =~ "test-secret"
      json(%{"sub" => "0000-0000-0000-0001"})
    end)

    assert {:ok, %OAuth2.Response{body: %{"sub" => "0000-0000-0000-0001"}}} =
             OAuth.get(
               %OAuth2.AccessToken{access_token: "user-token", token_type: "bearer"},
               "/oauth/userinfo",
               [{"x-resource", "resource-header"}],
               timeout: 123
             )
  end

  test "unsafe access-token fields fail before userinfo HTTP requests" do
    for token <- [
          %OAuth2.AccessToken{access_token: nil},
          %OAuth2.AccessToken{access_token: "token\nInjected: value"},
          %OAuth2.AccessToken{access_token: "token", token_type: %{}},
          %OAuth2.AccessToken{access_token: "token", token_type: "MAC"}
        ] do
      assert {:error, :invalid_token} = OAuth.get(token, "/oauth/userinfo")
    end
  end

  test "optional token fields can be absent or explicitly null" do
    for fields <- [%{}, %{"refresh_token" => nil, "expires_in" => nil, "token_type" => nil}] do
      Tesla.Mock.mock(fn _request -> json(Map.put(fields, "access_token", "optional-token")) end)

      assert {:ok,
              %OAuth2.AccessToken{
                access_token: "optional-token",
                refresh_token: nil,
                expires_at: nil,
                token_type: "Bearer"
              }} = OAuth.get_token(code: "code")
    end
  end

  test "numeric expiry, refresh token and token metadata survive conversion" do
    for expiry_fields <- [%{"expires_in" => 60}, %{"expires_in" => "60"}, %{"expires" => "60"}] do
      Tesla.Mock.mock(fn _request ->
        json(
          Map.merge(expiry_fields, %{
            "access_token" => "complete-token",
            "refresh_token" => "refresh-token",
            "token_type" => "bEaReR",
            "scope" => "openid email",
            "id_token" => "sensitive-id-token"
          })
        )
      end)

      started = System.system_time(:second)
      assert {:ok, token} = OAuth.get_token(code: "code")
      assert token.token_type == "Bearer"
      assert token.refresh_token == "refresh-token"
      assert token.expires_at >= started + 60
      assert token.expires_at <= System.system_time(:second) + 60
      assert token.other_params["scope"] == "openid email"
      assert token.other_params["id_token"] == "sensitive-id-token"
    end
  end

  test "zero expiry is present, not an omitted expiry" do
    Tesla.Mock.mock(fn _request -> json(%{"access_token" => "token", "expires_in" => 0}) end)
    started = System.system_time(:second)
    assert {:ok, token} = OAuth.get_token(code: "code")
    assert token.expires_at >= started
    assert token.expires_at <= System.system_time(:second)
  end

  test "invalid expiry and optional token fields fail without conversion crashes" do
    fields = [
      {"expires_in", "not-an-integer"},
      {"expires_in", "60seconds"},
      {"expires_in", -1},
      {"expires_in", 1.5},
      {"expires_in", false},
      {"expires_in", %{}},
      {"expires", "bad-legacy-expiry"},
      {"refresh_token", 42},
      {"refresh_token", " "},
      {"token_type", "MAC"},
      {"token_type", 42},
      {"token_type", "Bearer\r\nInjected: value"}
    ]

    for {field, value} <- fields do
      Tesla.Mock.mock(fn _request -> json(%{"access_token" => "token", field => value}) end)
      assert {:error, :invalid_token} = OAuth.get_token(code: "code")
    end
  end

  test "blank, wrong-type and header-unsafe access tokens are rejected" do
    for value <- [
          nil,
          "",
          " \t\n",
          42,
          false,
          [],
          %{},
          "Bearer token",
          "token\r\nInjected: value",
          "token\0"
        ] do
      Tesla.Mock.mock(fn _request -> json(%{"access_token" => value}) end)
      assert {:error, :invalid_token} = OAuth.get_token(code: "code")
    end
  end

  test "malformed JSON, nonobject JSON and non-JSON token responses fail safely" do
    for response <- [
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/json"}],
            body: "{private-invalid-json"
          },
          json(nil),
          json([]),
          json("private-scalar"),
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "text/plain"}],
            body: "access_token=private-form-token"
          },
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "not-a-mime-private"}],
            body: "private-body"
          },
          %Tesla.Env{status: 200, headers: [], body: "{\"access_token\":\"private-token\"}"}
        ] do
      Tesla.Mock.mock(fn _request -> response end)
      assert {:error, reason} = OAuth.get_token(code: "private-code")
      assert reason in [:invalid_json, :invalid_response]
      refute inspect(reason) =~ "private"
    end
  end

  test "non-200 responses and transport failures never become tokens or leak provider data" do
    for response <- [
          json(%{"access_token" => "private-token"}, 201),
          json(%{"access_token" => "private-token"}, 302),
          json(
            %{"error" => "private-provider-error", "error_description" => "private-detail"},
            400
          ),
          {:error, {:timeout, "private-transport-detail"}}
        ] do
      Tesla.Mock.mock(fn _request -> response end)
      assert {:error, reason} = OAuth.get_token(code: "private-code")
      assert reason in [:invalid_response, :token_exchange_failed]
      exception = assert_raise OAuth2.Error, fn -> OAuth.get_token!(code: "private-code") end
      refute Exception.message(exception) =~ "private"
      refute Exception.message(exception) =~ "test-secret"
    end
  end

  test "configured JSON serializers are used and expected parser failures are sanitized" do
    Application.put_env(:ueberauth, Ueberauth, json_library: WrappedJSON)

    Tesla.Mock.mock(fn _request ->
      %Tesla.Env{
        status: 200,
        headers: [{"content-type", "application/json"}],
        body: "wrapped:{\"access_token\":\"wrapped-token\"}"
      }
    end)

    assert {:ok, %OAuth2.AccessToken{access_token: "wrapped-token"}} =
             OAuth.get_token(code: "code")

    Tesla.Mock.mock(fn _request ->
      %Tesla.Env{
        status: 200,
        headers: [{"content-type", "application/json"}],
        body: "wrapped:{private-invalid"
      }
    end)

    assert {:error, :invalid_json} = OAuth.get_token(code: "code")

    assert {:error, :invalid_json} =
             OAuth.get(%OAuth2.AccessToken{access_token: "token"}, "/oauth/userinfo")
  end

  test "unexpected serializer programming errors are not rescued" do
    Application.put_env(:ueberauth, Ueberauth, json_library: BrokenJSON)
    Tesla.Mock.mock(fn _request -> json(%{"access_token" => "token"}) end)
    assert_raise ArgumentError, fn -> OAuth.get_token(code: "code") end
  end

  test "credential configuration errors identify keys without exposing values" do
    for key <- [:client_id, :client_secret],
        value <- [
          nil,
          "",
          " \t",
          42,
          [private: "private-value"],
          {:system, 42},
          {:system, "PRIVATE=INVALID"}
        ] do
      Application.put_env(:ueberauth, OAuth, Keyword.put(@credentials, key, value))
      exception = assert_raise ArgumentError, fn -> OAuth.authorize_url!() end
      assert Exception.message(exception) =~ Atom.to_string(key)
      refute Exception.message(exception) =~ "private-value"
      refute Exception.message(exception) =~ "PRIVATE=INVALID"
      refute Exception.message(exception) =~ "test-secret"
    end

    for key <- [:client_id, :client_secret] do
      Application.put_env(:ueberauth, OAuth, Keyword.delete(@credentials, key))
      assert_raise ArgumentError, fn -> OAuth.client() end
    end

    for config <- [
          nil,
          %{"client_secret" => "private-value"},
          ["private-value"],
          [{:client_id, "id"}, "private-value"]
        ] do
      Application.put_env(:ueberauth, OAuth, config)
      exception = assert_raise ArgumentError, fn -> OAuth.client() end
      refute Exception.message(exception) =~ "private-value"
    end

    Application.delete_env(:ueberauth, OAuth)
    assert_raise ArgumentError, fn -> OAuth.client() end
  end

  test "legacy environment credentials resolve and unavailable or blank variables fail safely" do
    env_name = "UEBERAUTH_ORCID_TEST_CREDENTIAL"
    previous = System.get_env(env_name)

    on_exit(fn ->
      if is_nil(previous),
        do: System.delete_env(env_name),
        else: System.put_env(env_name, previous)
    end)

    Application.put_env(
      :ueberauth,
      OAuth,
      Keyword.put(@credentials, :client_secret, {:system, env_name})
    )

    System.put_env(env_name, "private-environment-secret")

    Tesla.Mock.mock(fn request ->
      assert URI.decode_query(request.body)["client_secret"] == "private-environment-secret"
      json(%{"access_token" => "environment-token"})
    end)

    assert {:ok, %OAuth2.AccessToken{access_token: "environment-token"}} =
             OAuth.get_token(code: "code")

    for value <- [nil, "", " "] do
      if is_nil(value), do: System.delete_env(env_name), else: System.put_env(env_name, value)
      exception = assert_raise ArgumentError, fn -> OAuth.client() end
      assert Exception.message(exception) =~ "client_secret"
      refute Exception.message(exception) =~ env_name
      refute Exception.message(exception) =~ "private-environment-secret"
    end
  end

  defp json(body, status \\ 200) do
    %Tesla.Env{
      status: status,
      headers: [{"content-type", "application/json"}],
      body: Jason.encode!(body)
    }
  end
end
