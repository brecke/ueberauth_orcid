# UeberauthOrcid

Orcid integration for Ueberauth (oauth2 authentication)

This was heavily inspired by the github official Ueberauth plugin.

Feel free to get in touch if you need help using this!

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ueberauth_orcid` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ueberauth_orcid, "~>0.2.5"},
    # or {:ueberauth_orcid, git: "https://github.com/brecke/ueberauth_orcid", tag: "0.2.5"}
  ]
end
```

and add it to the `extra_applications` too:

```elixir
def application do
[
  mod: {Benchlight.Application, []},
  extra_applications: [:logger, :runtime_tools, :ueberauth_orcid]
]
end

```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ueberauth_orcid>.

## Runtime contract (unreleased)

These changes are in this checkout, not the published `0.2.5` release.

Jason is now a runtime dependency, so the default JSON decoder is available in
production without Credo or ExDoc. Existing `config :ueberauth, Ueberauth,
json_library: ...` overrides remain supported; the selected module must implement
the JSON API expected by Ueberauth/OAuth2.

The tested pairs are Elixir 1.14.5/OTP 25.3.2.21 and Elixir 1.18.4/OTP 27.3.4.
The default transport uses OTP's native TLS helper (OTP 25.1 or newer). Applications
remaining on Elixir 1.14 must select a compatible Plug branch, for example
`{:plug, "~> 1.19.5"}` alongside this dependency. Newer Plug releases require
Elixir 1.15; an unlocked Hex resolution does not automatically select the older
branch for you. Audit the application's own lockfile, not just this repository's.

### Callback configuration and local development

There is no implicit localhost callback. Set the registered callback explicitly
in `config/runtime.exs`:

```elixir
callback_url = System.fetch_env!("ORCID_REDIRECT_URI")

config :ueberauth, Ueberauth,
  providers: [
    orcid: {Ueberauth.Strategy.Orcid, [callback_url: callback_url]}
  ]

config :ueberauth, Ueberauth.Strategy.Orcid.OAuth,
  client_id: System.fetch_env!("ORCID_CLIENT_ID"),
  client_secret: System.fetch_env!("ORCID_CLIENT_SECRET"),
  redirect_uri: callback_url
```

For local development, register your development callback with ORCID and set
`ORCID_REDIRECT_URI=http://localhost:4000/auth/orcid/callback` for an app listening
on port 4000. To use the sandbox, use separate sandbox credentials and add
`site: "https://sandbox.orcid.org"` to the OAuth configuration. Relative
authorization/token endpoints follow `site`; explicit absolute endpoint
overrides remain supported.

By default the strategy sends Ueberauth's effective callback URI in both the
authorization request and token exchange. An explicit provider `callback_url`
takes precedence over the client's `redirect_uri`. Without that provider option,
Ueberauth derives the URL from the connection: validate the host and normalize
scheme/port only behind a trusted reverse proxy before Ueberauth runs. The
strategy does not trust raw forwarded headers. With `send_redirect_uri: false`,
the client's explicitly configured URI is used for both exchanges.

Direct OAuth helper calls also require an explicit effective `redirect_uri`.
Missing/blank/invalid credentials raise `ArgumentError` identifying the key,
not its value; legacy `{:system, "ENV_NAME"}` credential configuration still works.

### Custom OAuth module migration

Every configured `oauth2_module` must now implement:

- `authorize_url!(params, client_options)` returning the authorization URL.
- `get_token(params, options)` returning `{:ok, %OAuth2.AccessToken{}}` or
  `{:error, reason}`.
- `get(token, url, headers, options)` returning OAuth2 response/error tuples.

Previous partial wrappers need the non-raising token and userinfo operations.
For a wrapper already delegating to `Ueberauth.Strategy.Orcid.OAuth` through
`@delegate`, add:

```elixir
def get_token(params, options), do: @delegate.get_token(params, options)
def get(token, url, headers, options), do: @delegate.get(token, url, headers, options)
```

The default helper's public `get_token!/2` remains available for direct callers:
it returns the token or raises a sanitized `OAuth2.Error`. Both token helpers
accept top-level `headers:`, `options:` (HTTP options), and `client_options:`.
The callback uses the non-raising operation; partial-module fallback is not
provided. Migrate the wrapper before adopting the next release.

### Authentication result and failure contract

Successful userinfo must be an HTTP 200 JSON object with a nonblank `sub`.
`uid_field` still defaults to `:sub`; a configured alternate claim must also be
a nonblank string. No email or optional name is used as an identity fallback.
`info.name` joins valid, trimmed given/family names, then falls back to the
credit-name claim `name`; `info.nickname` keeps that credit name. With no valid
name, both remain nil. `info.email` remains nil even if raw userinfo includes
an email; do not infer verified/private-email access or use it for account linking.

`credentials.scopes` contains whitespace-separated **granted** scopes, or `[]`
when omitted/empty. It does not copy the requested scopes; commas are not scope
delimiters. Refresh tokens and expiration remain optional, without invented
values. Both temporary connection fields are removed on callback cleanup.
`extra.raw_info.user` and `extra.raw_info.token` remain available for compatibility:
cleanup does **not** remove secrets from the returned auth struct.

Expected provider/transport failures assign `ueberauth_failure`, never a
successful auth result. Strategy categories are `access_denied`, `provider_error`,
`missing_code`, `token_exchange_failed`, `invalid_token`, `userinfo_failed`, and
`invalid_identity`; Ueberauth retains its own `csrf_attack` protection.
Provider descriptions, response bodies, and credentials are not copied into
these failures, and authorization-code exchange is not retried automatically.
Known Jason/Poison parser errors are normalized; unexpected serializer/programming
errors still propagate rather than being hidden.

Token requests use form-only
[`client_secret_post`](https://orcid.org/.well-known/openid-configuration),
not redundant Basic authentication. Userinfo uses the bearer token, without
adding the client secret to resource parameters.

### HTTP security and timeouts

The default `Tesla.Adapter.Httpc` transport verifies the certificate chain and
HTTPS hostname using the operating system CA store. Install CA certificates in
deployment images; do not disable verification to work around a missing store.
The defaults are a 5-second connection timeout and a 15-second request timeout.
Tesla's default redirect policy remains disabled.

To tune timeouts, merge this into the existing OAuth configuration in
`config/runtime.exs`:

```elixir
config :ueberauth, Ueberauth.Strategy.Orcid.OAuth,
  request_opts: [connect_timeout: 5_000, timeout: 15_000]
```

Explicit adapter options, client `request_opts`, and per-request options retain
their precedence. An explicit `ssl:` list replaces the default TLS options:
custom trust stores must retain `verify: :verify_peer` and hostname verification.
Other adapters are not changed; configure their verification and timeouts using
their own documented options. Do not enable automatic redirects for requests
carrying credentials.

Keep `config :oauth2, debug: false` in production and avoid HTTP payload-logging
middleware. OAuth2's debug output includes headers and bodies, which can contain
client secrets, authorization codes, and tokens. Report vulnerabilities through
the [security policy](https://github.com/brecke/ueberauth_orcid/blob/master/SECURITY.md).
