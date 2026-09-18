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
