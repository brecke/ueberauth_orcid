# Changelog

## 0.3.0 — 2026-09-22

No historical 0.2.5 change list is reconstructed here.

### Compatibility

- Retain Elixir `~> 1.14`; the default Httpc transport now requires **OTP 25.1+**
  for native verified TLS options. Supported tested pairings are documented in
  [CONTRIBUTING.md](CONTRIBUTING.md), not every Elixir/OTP combination.
- **Breaking:** a custom `:oauth2_module` must implement `authorize_url!/2`,
  nonraising `get_token/2` returning `{:ok, %OAuth2.AccessToken{}}` or
  `{:error, reason}`, and `get/4` returning OAuth2 response/error tuples.
  The same module now handles authorization, token exchange and userinfo;
  bang-only token wrappers must migrate.
- **Breaking:** remove the implicit localhost redirect. Supply an explicit
  callback through Ueberauth or OAuth configuration, including when disabling
  `:send_redirect_uri`. Missing/blank credentials, malformed configuration and
  missing redirects raise clear configuration errors without secret values.
- Provider/transport token failures use safe nonraising results in the strategy;
  the direct `get_token!/2` convenience helper still raises a sanitized error.
  Custom implementations must preserve this safe failure contract.

### Security

- Verify certificate chains and hostnames with the default Httpc adapter,
  including OTP 25; add 5-second connect and 15-second request timeouts.
  Explicit adapter/client/request overrides retain precedence and must keep
  verification enabled; other adapters retain their own transport policy.
- Use ORCID's `client_secret_post` token form; remove Authorization headers
  from token exchange and avoid forwarding client credentials to userinfo.
- Reject invalid tokens and non-200/non-JSON/malformed profile responses;
  require a nonblank `sub` and configured UID claim before authentication.
  Preserve Ueberauth's state boundary and reject redirects as profile data.
- Sanitize strategy failures instead of exposing provider responses, tokens or
  secrets. Clear temporary `:orcid_user` and `:orcid_token` connection fields
  after callbacks. Successful credentials and `extra.raw_info.token` remain
  sensitive and intentionally preserved for compatibility; do not log them.
- Require patched OAuth2, Tesla and branch-aware Plug versions; provide Jason
  explicitly at runtime and honor Ueberauth's configured JSON serializer.
  Applications must audit their own resolution, not rely on this library lock.

### Fixes

- Honor authorization endpoint/configuration overrides, callback consistency,
  and top-level token HTTP headers/options/client overrides.
- Split granted scopes on whitespace; missing/blank scopes become `[]`.
  Default requested scopes remain `openid email profile`, and a request's
  `scope` still overrides the configured default.
- Accept missing given/family names without crashing, with credit-name fallback;
  absent names remain nil. `info.email` remains nil rather than guessing an
  identity. Preserve the bare ORCID subject and raw userinfo/token contract.
- Validate optional refresh/expiry fields; support non-expiring tokens and the
  legacy `expires` field when `expires_in` is absent/null.

### Tooling and release

- Replace the generated test with offline authentication, failure, state and
  TLS regressions; define a three-pair runtime matrix and canonical coverage.
- Refresh development-only Credo/ExDoc; add development-only Dialyzer and
  Sobelow gates, pinned Hex advisory auditing, CI, weekly audit configuration
  and monthly dependency-update configuration.
- Expand setup/API/security documentation, package extras, source references,
  secret-safe sandbox acceptance, downstream rollout and rollback guidance.
