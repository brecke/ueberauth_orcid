# UeberauthOrcid

[![Hex version](https://img.shields.io/hexpm/v/ueberauth_orcid.svg)](https://hex.pm/packages/ueberauth_orcid)
[![CI](https://github.com/brecke/ueberauth_orcid/actions/workflows/ci.yml/badge.svg)](https://github.com/brecke/ueberauth_orcid/actions/workflows/ci.yml)
[![HexDocs](https://img.shields.io/badge/HexDocs-published-blue.svg)](https://hexdocs.pm/ueberauth_orcid/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

An [Ueberauth](https://hexdocs.pm/ueberauth/) strategy for authenticating an
[ORCID](https://orcid.org/) identity through the authorization-code flow and
`/oauth/userinfo`. It supplies an `Ueberauth.Auth` result, not an account database,
a session manager, a general ORCID API client, or an ID-token validator.

See the [changelog](CHANGELOG.md), [contributor/release guide](CONTRIBUTING.md),
and [security policy](SECURITY.md).

## 1. Install

In your application's `mix.exs`, add a normal runtime dependency:

```elixir
defp deps do
  [
    {:ueberauth_orcid, "~> 0.3.0"}
  ]
end
```

Fetch dependencies with `mix deps.get`.

Do not add a new application module or manually add `:ueberauth_orcid` to
`extra_applications`. [Mix infers runtime applications from dependencies](https://hexdocs.pm/mix/Mix.Tasks.Compile.App.html)
and starts them with your application. Keep this dependency at runtime (not
`runtime: false`); applications that explicitly override Mix's `:applications`
list must maintain that list themselves.

### Supported toolchains

The locally checked pairs are:

| Role | Elixir | Erlang/OTP |
| --- | --- | --- |
| Minimum compatibility | 1.14.5 | 25.3.2.21 |
| Additional compatibility | 1.18.4 | 27.3.4 |
| Canonical development | 1.20.4 | 27.3.4 |

The package declares Elixir `~> 1.14`; the default TLS transport requires
**OTP 25.1 or newer**. Use a supported Elixir/OTP pairing, not every combination
of those versions. On Elixir 1.14, also add `{:plug, "~> 1.19.5"}` to your app's
dependencies: Plug 1.20 requires Elixir 1.15, and an unlocked resolution does not
automatically choose the older compatible branch. The app's lockfile, not this
library's lockfile, determines its installed dependencies.

## 2. Register ORCID and configure runtime credentials

Follow ORCID's [client registration guide](https://info.orcid.org/documentation/integration-guide/registering-a-public-api-client/),
including the applicable Public API terms or Member API registration. Register
the **full callback URI**, including its path; ORCID requires matching domains
and separately registered subdomains. Registering only a host permits broader
callback paths and is not recommended. See ORCID's [redirect URI rules](https://info.orcid.org/ufaqs/how-do-redirect-uris-work/).

| Environment | Registration and accounts | OAuth `site` | Example registered callback |
| --- | --- | --- | --- |
| Production | [Production developer tools](https://orcid.org/developer-tools); production credentials/accounts | `https://orcid.org` | `https://app.example.org/auth/orcid/callback` |
| Sandbox/local | [Sandbox developer tools](https://sandbox.orcid.org/developer-tools); separate sandbox credentials/accounts | `https://sandbox.orcid.org` | `http://localhost:4000/auth/orcid/callback` |

Production callbacks must use HTTPS. HTTP is for local sandbox testing only;
your app must actually listen on the registered host/port. Keep sandbox identities,
credentials, and stored tokens separate from production. Record API hosts such
as `pub.orcid.org` and `api.orcid.org` are **not** the login `site`.

Put this in your application's `config/runtime.exs`. Supply the three environment
variables from your deployment's secret/configuration mechanism, never source
control. The provider name `:orcid` defines the default routes and returned
`auth.provider`.

```elixir
import Config

callback_url = System.fetch_env!("ORCID_REDIRECT_URI")

config :ueberauth, Ueberauth,
  providers: [
    orcid: {Ueberauth.Strategy.Orcid, [callback_url: callback_url]}
  ]

config :ueberauth, Ueberauth.Strategy.Orcid.OAuth,
  client_id: System.fetch_env!("ORCID_CLIENT_ID"),
  client_secret: System.fetch_env!("ORCID_CLIENT_SECRET"),
  redirect_uri: callback_url,
  site: "https://orcid.org"

config :oauth2, debug: false
```

For **sandbox**, change `site` in that same configuration to
`"https://sandbox.orcid.org"` and supply sandbox values for all three variables.
Relative authorization/token endpoints follow `site`; do not retain absolute
production endpoint overrides when switching environments.

There is no implicit localhost callback. The explicit provider `callback_url`
takes precedence over the OAuth client's `redirect_uri`, and the strategy sends
that effective URI in both authorization and token exchange. Configure both to
the same registered value as above. Direct OAuth helper calls also need an
explicit effective `redirect_uri` for authorization/token exchange. Missing,
blank, or wrong-type credentials raise an `ArgumentError` naming the key, not
its value. Legacy `{:system, "ENV_NAME"}` credential values still work.

### JSON contract

Jason is a runtime dependency and the default serializer; production does not
need Credo or ExDoc to decode JSON. An existing override remains supported:

```elixir
config :ueberauth, Ueberauth, json_library: Jason
```

A replacement must be a runtime module implementing `encode!/1` and `decode!/1`
as expected by Ueberauth/OAuth2; decoded JSON objects must have string keys.
Phoenix's own JSON configuration does not configure this client. This helper
uses the global `Ueberauth.json_library/0` selection. Known Jason/Poison parse
errors are normalized; arbitrary serializer/programming errors still propagate.

## 3. Wire a browser callback

The following is a complete **read-only Plug router**, usable with your existing
Plug-compatible HTTP server. It deliberately displays only the authenticated
identity: it creates no account, persists no tokens, and establishes no logged-in
account session. Visit `/` and follow the link to start; do not visit the callback
directly. Place the module in your application's `lib/` and configure your
server to call `MyApp.OrcidRouter` on the registered port.

Supply `SECRET_KEY_BASE` as a cryptographically random secret of at least 64 bytes
(the existing Phoenix endpoint secret is suitable). Configure TLS and host
validation at your endpoint/reverse proxy before this router. In production,
redirect HTTP to HTTPS before handling authentication; normalize the connection's
scheme only from a trusted proxy. The conditional cookie flag below permits
local HTTP sandbox development, not production HTTP.

```elixir
defmodule MyApp.OrcidRouter do
  use Plug.Router

  plug :browser_session
  plug Plug.CSRFProtection
  plug :authenticate
  plug :match
  plug :dispatch

  get "/" do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, ~s(<a href="/auth/orcid">Authenticate with ORCID</a>))
  end

  get "/auth/orcid/callback" do
    case conn.assigns do
      %{ueberauth_failure: %Ueberauth.Failure{}} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(401, "ORCID authentication failed. Start again from /.")

      %{ueberauth_auth: %Ueberauth.Auth{provider: :orcid, uid: uid}} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, "Authenticated ORCID iD: #{uid}\n")

      _ ->
        send_resp(conn, 400, "No authentication result")
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp browser_session(conn, _opts) do
    conn = %{conn | secret_key_base: System.fetch_env!("SECRET_KEY_BASE")}

    opts = Plug.Session.init(
      store: :cookie,
      key: "_my_app_session",
      signing_salt: "orcid-browser-session",
      same_site: "Lax",
      http_only: true,
      secure: conn.scheme == :https
    )

    conn
    |> Plug.Session.call(opts)
    |> fetch_session()
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
  end

  defp authenticate(conn, _opts) do
    conn = fetch_query_params(conn)

    if conn.request_path == "/auth/orcid" and Map.has_key?(conn.query_params, "scope") do
      conn |> send_resp(400, "Scope overrides are not enabled") |> halt()
    else
      Ueberauth.call(conn, Ueberauth.init([]))
    end
  end
end
```

Ueberauth intercepts `GET /auth/orcid` and halts with an ORCID redirect; the
callback continues to the success/failure branches above. Runtime initialization
in `authenticate/2` ensures the providers from `runtime.exs` are available.
The request guard is this example's fixed-scope policy, not a library default.
The module requires only the existing Plug/Ueberauth dependencies; it is also
callable through `Plug.Test` without creating a Phoenix project.

For an existing **Phoenix** app, use its endpoint's `Plug.Session` and browser
pipeline (`fetch_session`, `protect_from_forgery`, secure browser headers), and
route both `GET /auth/orcid` and `GET /auth/orcid/callback` to an auth controller.
Run Ueberauth before those actions and handle its two assignments exactly as
above; do not run a second session stack or require an already logged-in user
on the login/callback routes. Preserve a request-scope policy before Ueberauth.

### State, cookies, and trusted URLs

Ueberauth's OAuth state check is distinct from your app's ordinary form CSRF
protection. It uses the `ueberauth.state_param` cookie (SameSite `Lax` in
Ueberauth 0.10.8), requires the matching callback `state`, and needs the session
plug installed. Keep both protections enabled. Do not disable state checking to
fix a cookie problem. The state cookie is separate from your session cookie;
setting session attributes does not reconfigure it. Use a top-level GET callback,
the same browser and host throughout, HTTPS in production, and trusted proxy
normalization. Starting a second flow in another tab can replace the state cookie.

Prefer an explicit `callback_url`. Without one, Ueberauth 0.10.8's URL helper
consults `x-forwarded-proto`, `x-forwarded-host`, and `Host` headers as well as the
connection. It does **not** establish proxy trust or validate allowed hosts for
you. Strip untrusted forwarding headers at the edge, allowlist hosts, and normalize
scheme/port before authentication. Never rely on arbitrary client-supplied headers
to select a trusted callback. `callback_url` changes the URI sent to ORCID; its
path must still match your app's route and configured `callback_path`.

## Options and scope policy

Provider options go beside `callback_url` in the `providers` entry:

| Strategy option | Default | Meaning |
| --- | --- | --- |
| `uid_field` | `:sub` | Userinfo claim used as UID. A nonblank string `sub` is always required; any selected alternate claim must also be nonblank. Keep the default for account identity. |
| `default_scope` | `"openid email profile"` | Requested scope when the request has no `scope` parameter. |
| `send_redirect_uri` | `true` | Send Ueberauth's effective callback for both exchanges. With `false`, the client's explicit `redirect_uri` is used instead; it does not make redirects optional. |
| `oauth2_module` | `Ueberauth.Strategy.Orcid.OAuth` | Implementation for authorization, non-raising token exchange, and userinfo retrieval; see migration below. |

**Requested scopes are not proof of granted permissions.** The library preserves
`openid email profile` for compatibility. Production and sandbox [discovery](https://orcid.org/.well-known/openid-configuration)
([sandbox](https://sandbox.orcid.org/.well-known/openid-configuration)) advertise
`openid`, not `email` or `profile`, and list no email claim. This is not evidence
that ORCID rejects the additional strings: their acceptance has not been verified
in a live flow for this candidate. They do not establish email access.

ORCID's [OpenID documentation](https://github.com/ORCID/ORCID-Source/blob/master/orcid-web/ORCID_AUTH_WITH_OPENID_CONNECT.md)
documents `openid` as granting access to userinfo. A new integration may explicitly
choose `default_scope: "openid"` for that documented flow; this is an application
choice, not a changed library default. Verify it in sandbox before rollout.
Do not substitute `/authenticate` alone: this strategy retrieves identity from
userinfo, not the token response's `orcid` field. Member API permissions are a
separate integration concern, not implied by login.

Without the example's guard, `conn.params["scope"]` overrides `default_scope`
(including an empty string). The library does not allowlist it. If your app needs
reauthorization, validate a server-owned set of allowed scopes before Ueberauth;
do not pass arbitrary user input or interpret requested scopes as authorization.

### Common Ueberauth settings

These are inherited from [Ueberauth](https://hexdocs.pm/ueberauth/Ueberauth.html),
not additional ORCID features:

| Setting | Default / behavior |
| --- | --- |
| `base_path` | Global/plug option, `"/auth"`. |
| `request_path` | Provider option, `"/auth/orcid"` for this registration; absolute path. Request method is fixed to GET in Ueberauth 0.10.8; there is no `request_methods` option. |
| `callback_path` | Provider option, `"/auth/orcid/callback"`; absolute path. |
| `callback_methods` | Provider option, `["GET"]`; changing it also requires matching host routes/provider behavior and cookie/CSRF handling. Keep GET for this flow. |
| `callback_url` | Unset; explicit full URI recommended instead of header-derived URL. |
| `callback_scheme`, `callback_port` | Unset; override generated callback components when no explicit URL is supplied. |
| `request_scheme`, `request_port` | Unset; affect Ueberauth's request-URL helper, not ORCID endpoint selection. |
| `callback_params` | No parameters copied by default; allowlisted request parameter names included in a generated callback URL. Avoid for this fixed registered callback. |
| `providers`, `otp_app` | Plug options for provider filtering/application configuration; see upstream documentation. OAuth credentials and this helper's serializer still use the global configuration shown above. |

`allow_private_emails` is not a supported option and has no effect. There is no
ORCID provider option that grants private-email access or replaces state security.

### OAuth client and HTTP options

Configure `Ueberauth.Strategy.Orcid.OAuth` under application `:ueberauth`:

| Option | Default / behavior |
| --- | --- |
| `client_id`, `client_secret` | Required nonblank strings, or legacy environment tuples. |
| `redirect_uri` | No usable default; required when the strategy/provider does not supply one. |
| `site` | `"https://orcid.org"`. Userinfo is fetched at `/oauth/userinfo` on this site. |
| `authorize_url` | `"/oauth/authorize"`; relative or explicit absolute URL. |
| `token_url` | `"/oauth/token"`; relative or explicit absolute URL. |
| `headers` | `[{"user-agent", "ueberauth-orcid"}]`. Never add credentials-bearing logging. |
| `params` | OAuth2 client parameter map, empty by default; flow parameters take precedence. |
| `request_opts` | HTTP adapter options; Httpc defaults below. |

The helper uses its own OAuth2 strategy and POST token exchange; generic
`OAuth2.Client` fields are not promises of extra ORCID features (for example,
`token_method` does not switch this helper away from POST). See the
[OAuth2 client API](https://hexdocs.pm/oauth2/OAuth2.Client.html) for underlying
client structures. `client/1` merges per-call client options over application
configuration over library defaults.

Token requests use form-only `client_secret_post`, as advertised by ORCID
discovery, not redundant Basic authentication. Userinfo uses a Bearer token,
without adding the client secret to resource parameters.

## Result and application responsibilities

On success, `conn.assigns.ueberauth_auth` contains:

| Field | Contract |
| --- | --- |
| `provider`, `uid` | `:orcid` for the registration above; the selected userinfo claim, normally the bare ORCID `sub`, unchanged. No email/name fallback or new checksum restriction. |
| `info.name` | Valid trimmed given/family names joined, falling back to the credit-name claim `name`; `nil` if absent/invalid. |
| `info.nickname` | Valid trimmed credit name (`name`), otherwise `nil`. |
| `info.email` | Always `nil`, even if raw userinfo contains an email. No private/verified-email claim. |
| `credentials.scopes` | Whitespace-separated **granted** scopes from the token response; `[]` when missing/empty. Commas are not delimiters. |
| `credentials.token`, `token_type` | Validated access token and Bearer type from the helper. |
| `credentials.refresh_token` | Optional; do not require or invent it. |
| `credentials.expires_at`, `expires` | Optional expiration timestamp; `expires` is false when no timestamp exists. |
| `extra.raw_info.user`, `extra.raw_info.token` | Raw userinfo and token retained for compatibility; sensitive, not safe diagnostics. |

Successful userinfo must be an HTTP 200 JSON object with a nonblank `sub` and
selected UID claim. Optional profile omissions do not fail authentication.
Temporary `:orcid_user` and `:orcid_token` connection-private fields are cleaned
up, but this **does not remove secrets from the returned auth struct**.

The read-only callback above is the integration point for your own account
policy. Link an account using the authenticated provider/UID in the correct
production/sandbox namespace, never a supplied ORCID string, display name, or
unverified email. Linking an additional identity should require an authenticated
local account and confirmation; enforce uniqueness and handle conflicts rather
than silently merging accounts. After an intentional local login, rotate the
session identifier and store only the application's account/session identifier,
not the full auth struct. Store tokens only if your application needs them,
with access controls and encryption at rest; a signed cookie is not encryption.

The strategy uses an OIDC userinfo endpoint but does **not** validate an ID token's
signature, issuer, audience, expiry, or nonce. Do not treat a raw `id_token` as a
verified assertion or infer MFA from it. Local logout means clearing your own
session; it does not revoke ORCID tokens, remove consent, or end the ORCID session.

## Upgrading a custom OAuth module

`oauth2_module` now covers the entire flow. Every configured module must export:

- `authorize_url!(params, client_options)` returning an authorization URL.
- `get_token(params, options)` returning `{:ok, %OAuth2.AccessToken{}}` or
  `{:error, reason}`; **not** a client struct or a bare token.
- `get(token, url, headers, options)` returning `{:ok, %OAuth2.Response{}}` or
  `{:error, reason}`. A successful userinfo response must satisfy the JSON/status/
  identity contract above.

Here is a complete pass-through module; retain your intentional authorization
customizations while adding both non-raising operations:

```elixir
defmodule MyApp.OrcidOAuth do
  defdelegate authorize_url!(params, options), to: Ueberauth.Strategy.Orcid.OAuth
  defdelegate get_token(params, options), to: Ueberauth.Strategy.Orcid.OAuth
  defdelegate get(token, url, headers, options), to: Ueberauth.Strategy.Orcid.OAuth
end
```

Set `oauth2_module: MyApp.OrcidOAuth` in the provider options only when you need
that customization. Earlier partial wrappers exporting only authorization and
`get_token!` must migrate before upgrading; there is no partial-module fallback.
A custom module is trusted code responsible for safe transport and result shapes.

The default helper's public `get_token!/2` remains available to direct callers,
returning a token or raising a sanitized `OAuth2.Error`. Both token helpers accept
top-level `headers:` (HTTP headers), `options:` (HTTP adapter options), and
`client_options:` (client overrides). Authorization headers are removed and form
content type enforced for token exchange. `get/4` takes HTTP options as its fourth
argument. Expected provider failures return tuples; configuration/programming
errors are not blanket-rescued. Authorization-code exchange is never automatically
retried: codes are one-use credentials.

## Transport, logging, and troubleshooting

The default `Tesla.Adapter.Httpc` transport verifies the certificate chain and
HTTPS hostname using OTP's native TLS helper and operating-system CA store.
Install CA certificates in deployment images; do not disable verification to
work around a missing store. Defaults are a 5-second connection timeout and a
15-second request timeout. Merge timeout overrides into your OAuth configuration:

```elixir
config :ueberauth, Ueberauth.Strategy.Orcid.OAuth,
  request_opts: [connect_timeout: 5_000, timeout: 15_000]
```

Explicit Httpc adapter options are merged with client `request_opts`; client
options win, then per-request options win. An explicit `ssl:` list replaces the
default TLS options: custom trust stores must retain `verify: :verify_peer` and
hostname verification. Other adapters are not hardened by this helper; configure
their own TLS and timeout options. Default redirects remain disabled. Do not
enable automatic redirects for credential-bearing requests.

Keep OAuth2 debug logging off and avoid HTTP payload-logging middleware. Redact
codes, state, cookies, client secrets, tokens, and raw auth/provider data from
application, proxy, and error-reporting logs; filtering controller parameters
alone does not remove query strings from access logs. Never log the whole auth
struct or include real credentials/private records in bug reports.

Expected failures assign `ueberauth_failure`, not a successful auth result.
Inspect `failure.errors[*].message_key` for categories, not raw provider bodies:

| Symptom/category | Check or response |
| --- | --- |
| `csrf_attack` | Start again from the request route. Check the browser's state cookie, matching host, session plug, SameSite behavior, trusted HTTPS proxy settings, and overlapping tabs. Never bypass state validation. |
| ORCID redirect mismatch | Compare the fully registered callback with both configured URIs, route path, scheme, host, and port; check production/sandbox credentials are not mixed. |
| `access_denied` | Consent was declined; offer a fresh login without treating it as an application crash. |
| `provider_error` | ORCID returned another authorization error; offer a fresh attempt and check provider availability/configuration without reflecting its description. |
| `missing_code` | No nonblank authorization code arrived; begin a new authorization flow. |
| `token_exchange_failed` | Invalid/expired/reused code, credentials/redirect mismatch, rejected/malformed token response, or transport failure. Start a fresh flow; do not retry the code automatically. |
| `invalid_token` | A custom module returned a token that fails strategy validation. Invalid default-helper token responses appear as `token_exchange_failed`. |
| `userinfo_failed` | Check granted `openid` scope and provider status; includes non-200 responses, redirects, malformed JSON/content type, and transport failures. |
| `invalid_identity` | Userinfo lacks a nonblank `sub` or selected UID claim. Do not fall back to names/email. |
| Missing name/email/refresh token | These are optional; handle `nil` rather than rejecting or inventing profile data. Email is never supplied by `info.email`. |
| Configuration `ArgumentError` | Check the named key and runtime environment without printing its value. |
| TLS/timeouts or provider outages | Check CA installation, hostname, network/proxy configuration, and ORCID availability. Preserve verification and use bounded timeouts. |

Failure descriptions are sanitized: provider descriptions, response bodies, and
credentials are not copied into these strategy failures. See [CONTRIBUTING.md](CONTRIBUTING.md)
for maintenance and sandbox procedures and [SECURITY.md](SECURITY.md) for private
vulnerability reporting.
