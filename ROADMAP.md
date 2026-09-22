# Maintenance roadmap

Assessment date: 2026-09-18. Scope: maintain `ueberauth_orcid` as a small, reliable Ueberauth strategy, not turn it into a general ORCID API client.

Benchpro's existing integration works. Preserve that behavior while making upgrades, failures, and future maintenance predictable. Checked items record completed research or verified implementation; unchecked items remain work to do, not claims that checks have passed.

## Recommended order

1. Restore a useful development/test baseline and establish minimal CI.
2. Triage dependency advisories and make production dependencies explicit.
3. Harden the authentication boundary, backed by behavioral regression tests.
4. Finish static analysis and compatibility checks.
5. Publish complete documentation, honest badges, and a verified release.
6. Add optional ORCID capabilities only when a concrete consumer needs them.

No rewrite, new supervision tree, general HTTP abstraction, or full Phoenix example application is needed for this work.

## What the assessment actually found

| Finding | Evidence | Consequence |
| --- | --- | --- |
| Published version is `0.2.5`, from June 2023 | [Hex metadata](https://hex.pm/api/packages/ueberauth_orcid) | Treat existing consumers as a compatibility constraint. |
| Credo is already installed, not missing | `mix.exs:47`: `~> 0.8`; lockfile: `0.10.2` | Upgrade it rather than add a second linter. |
| Tests currently cannot start on the available runtime | `mix test`, Elixir 1.18.4 / OTP 28: Credo compilation fails while embedding `@regex` | This is a development-tooling failure, not evidence that Benchpro login is broken. |
| The only test is generated and invalid | `test/ueberauth_orcid_test.exs` calls `UeberauthOrcid.hello/0`; that function is absent | Replace it with real strategy tests, not a new `hello/0`. |
| Production compilation succeeds, with warnings | `MIX_ENV=prod mix compile`; unused `allow_private_emails`, plus dependency deprecations | There is a working runtime baseline worth preserving. |
| Formatting already passes | `MIX_ENV=prod mix format --check-formatted` | Add a check; no style rewrite is justified. |
| Locked transitive dependencies have advisories | `mix hex.audit` exits 1 for Plug 1.14.2 and Tesla 1.7.0 | Prioritize dependency triage; an advisory does not by itself establish reachable exploitation in this strategy or Benchpro. |
| JSON availability depends on the consuming app | Clean production probe returns `{Jason, false}` for `{Ueberauth.json_library(), Code.ensure_loaded?(Ueberauth.json_library())}` | Document or explicitly supply the runtime JSON dependency; dev/test Credo must not accidentally make tests pass. |
| A missing family name raises | Direct `info/1` probe with only `given_name` raises `ArgumentError`; `orcid.ex:93` concatenates both fields | Handle optional profile claims without failing login. |
| Space-separated scopes are not split | Direct credentials probe yields `["openid email profile"]`; `orcid.ex:72` splits on commas | Correct the OAuth scope representation and test empty/missing scope too. |
| Cleanup retains the private token | Direct `handle_cleanup!/1` probe leaves `:orcid_token`; only `:orcid_user` is cleared | Clear temporary state; separately define the intended credentials/raw-info contract. |
| OAuth configuration has correctness traps | `authorize_utl` typo, localhost redirect default, rewritten `options` variable in `get_token!/2` | Test effective URLs and request options, not merely keyword lists. |
| The configurable OAuth module is only partially used | Request/token steps use `:oauth2_module`; `fetch_user/2` hardcodes the default module | Make configuration consistent across the whole flow; useful for consumers and tests. |
| Documentation/release metadata is incomplete | Empty module docs; UID docs say `:id` while code uses `:sub`; `source_ref: "#v{@version}"`; changelog URL returns 404 | Fix consumer instructions and release links before presenting the project as refreshed. |
| No CI configuration exists in the checkout | Repository inventory | Start small: Linux, deterministic tests, no ORCID secrets. |

Baseline commands fetched the existing locked dependencies without upgrading them. No live ORCID login, Benchpro deployment, Dialyzer run, or Sobelow scan was performed. Local edge probes exercised strategy functions only, not the complete Ueberauth pipeline. Build/dependency directories are ignored artifacts.

Runtime caveat: the host has Elixir 1.18.4 with OTP 28, whereas the [official compatibility table](https://hexdocs.pm/elixir/compatibility-and-deprecations.html) lists OTP 25–27 for Elixir 1.18. The observed failure is real, but it is not a supported-pair compatibility verdict. Start implementation on a documented supported pair.

## Compatibility rules

- Keep provider/module names, configuration keys, routes, and successful authentication shape unless a change is explicitly documented and versioned.
- Preserve the current UID representation until Benchpro's storage and account-linking behavior are checked. Never substitute email or display name for the ORCID identity.
- Do not silently change default scopes, introduce extra permissions, or add a new network request to the normal login path.
- A dependency bump, new Elixir minimum, and authentication behavior change should be independently reviewable.
- Protect tokens and client secrets even if that requires a documented compatibility change. Do not retain an unsafe behavior merely to avoid release notes.
- Use Benchpro as the integration acceptance environment, not as a runtime dependency of this package.

## Phase 1 — Useful baseline and minimal CI

**Priority: first. Outcome: contributors can run meaningful checks before changing authentication.**

- [x] Record the Elixir/OTP, Ueberauth, OAuth2, JSON library, adapter, callback URL, scopes, and configuration actually used by Benchpro. Record configuration shape only, never credentials.
- [x] Document which `Ueberauth.Auth` fields Benchpro persists or reads, including UID, name, nickname, email, scopes, credentials, and `extra.raw_info`.
- [x] Choose a supported Elixir/OTP policy. `elixir: "~> 1.14"` currently advertises a broad range; do not silently drop its lower bound just to accommodate tooling. Check valid Elixir/OTP pairings rather than creating an arbitrary Cartesian matrix.
- [x] Upgrade Credo to a maintained release compatible with the selected floor. Keep development tools out of runtime applications. Bound ExDoc to an intentional compatible range instead of `>= 0.0.0`.
- [x] Delete the generated greeting test. Add an offline request-redirect test and a successful callback/auth-result test using synthetic ORCID data.
- [x] Establish one test seam using the existing configurable OAuth module and/or the installed HTTP client's test facility. Do not add mocks, a local server, and an HTTP wrapper all at once.
- [x] Add a minimal GitHub Actions workflow for pull requests and pushes: dependency fetch, compilation, format check, tests. Add subsequent gates when their baselines are clean, not as permanently ignored failures.
- [x] Keep application environment changes isolated and restored in tests; tests that mutate global configuration must not race under `async: true`.

### Benchpro compatibility baseline (read-only source review, 2026-09-18)

Evidence below is from the sibling `../benchpro` checkout, not a running deployment. No secret files, credentials, database records, or live ORCID responses were inspected. The working-login report remains the integration baseline; checked-in declarations do not establish the deployed toolchain, lockfile, environment overrides, or granted permissions.

| Concern | Checked-in contract and evidence |
| --- | --- |
| Runtime declaration | `.tool-versions` declares Elixir `1.18.4-otp-28` and Erlang `28.1`. This is outside Elixir 1.18's documented OTP 25–27 range; it is not proof of the runtime serving Benchpro. The library's canonical supported local pair is Elixir `1.18.4-otp-27` / OTP `27.3.4`, not a claim that Benchpro was migrated. |
| Consumer resolution | `mix.lock` locks `ueberauth_orcid 0.2.5`, Ueberauth `0.10.8`, OAuth2 `2.1.1`, Tesla `1.20.0`, and Jason `1.4.5`. These differ from this library's own runtime dependency lock and must be validated separately before rollout. |
| JSON and HTTP adapter | `config/config.exs:197-210` configures Phoenix's JSON library as Jason and the ORCID provider. No Ueberauth JSON override or OAuth2 adapter override was found in the inspected `config/` and application source. The inspected dependency sources default Ueberauth JSON to Jason (`deps/ueberauth/lib/ueberauth.ex:258-260`) and OAuth2 HTTP to `Tesla.Adapter.Httpc` (`deps/oauth2/lib/oauth2/request.ex:88-93`). These are source-derived defaults, not observations of a deployed adapter; Benchpro also having Finch installed does not select it for this OAuth flow. |
| Callback configuration | `config/runtime.exs:44-76,181-196,358-372` derives `app_base_url` from `APP_BASE_URL` or scheme/host/port defaults. `ORCID_REDIRECT_URI` overrides the default `#{app_base_url}/auth/orcid/callback`; the same value is passed as provider `callback_url` and OAuth client `redirect_uri`. Absent overrides, the production configuration defaults to `https://benchpro.ai/auth/orcid/callback` and development to `http://benchpro.local.gd:4000/auth/orcid/callback`. Production/staging checks require HTTPS and the canonical callback (`runtime.exs:425-466`). Actual environment values and the registered ORCID callback were not inspected. |
| Credentials and scopes | `runtime.exs:186-223` reads client ID/secret from environment, with synthetic test fallbacks only. The scope is `openid email profile`, adding `/read-limited` when `ORCID_MEMBER_API_ENABLED` is true (default false outside tests, true in tests). The strategy receives that scope through provider `default_scope`; a reauthorization request also supplies `Orcid.authorization_scope()` as the request scope (`user_session_controller.ex:54-62`). Configured scope is not proof of granted scope. |
| Custom OAuth contract | `lib/benchpro/orcid/prompt_login_oauth.ex:1-13` exports only `authorize_url!/1,2` and `get_token!/1,2`. Authorization adds `prompt=login`, then delegates to `Ueberauth.Strategy.Orcid.OAuth`; token exchange delegates unchanged. It has no `get/4`. Preserve the current split: custom module for authorize/token, default module for userinfo. Making `oauth2_module` apply to userinfo later requires a coordinated consumer change, not an incidental Phase 1 refactor. |

The callback entry point is `lib/benchpro_web/controllers/user_session_controller.ex`, which plugs Ueberauth for request/callback actions and consumes its `:ueberauth_auth` / `:ueberauth_failure` assignments (`:4,21-50`). Actual account consumers establish the following contract:

| Auth field | Actual read/persistence behavior |
| --- | --- |
| `provider`, `uid` | The generic callback reads both, uppercases the provider to `"ORCID"`, and passes UID unchanged into `user_identity` (`user_session_controller.ex:68-104,565-569`). `Accounts.get_user_by_orcid/1` delegates to `Accounts.Users`, whose query accepts trimmed input plus canonical/checksum-case variants and returns only an unambiguous user (`accounts.ex:19`, `accounts/users.ex:36-61`). `Accounts.User.get_orcid/1` exposes the stored UID only for provider `"ORCID"` (`accounts/user.ex:356-365`). Do not replace the ORCID subject with email, name, or a different UID representation. |
| `info.name`, `info.nickname`, `extra.raw_info.user` | `orcid_name_fields/1` reads raw `given_name` and `family_name`; `info.nickname` is the preferred credit name, with raw `name` as fallback. If both raw names are absent/blank, it splits `info.name`; it also supports the info-only case (`user_session_controller.ex:516-563`). The resulting given/family/credit names are registration attributes persisted by the user changeset (`accounts/user.ex:112-114,390-399`, `accounts/registration.ex:32-35`). Raw userinfo is therefore an active consumer contract, not unused debug output. |
| `info.email` | The callback does not use it: it initializes email to nil and separately calls `Orcid.fetch_email(uid)` for a public email on new-account login, with a manual-email/pending-registration path if absent (`user_session_controller.ex:82-115,142-179,276-280`). `get_or_create_user/1` may link an existing account by that separately obtained email (`:188-225`); this is not evidence that auth-info email drives account identity. |
| `credentials.token`, `refresh_token` | Both are read into identity attributes on login and reauthorization (`user_session_controller.ex:68-94,327-359`). `Accounts.UserIdentity` persists both through `Benchpro.Encrypted.Binary` ciphertext columns and requires both in its changeset (`accounts/user_identity.ex:11-28`). Existing-identity rotation checks provider and equivalent ORCID UID before updating tokens/scopes (`accounts/registration.ex:55-156`); reauthorization additionally checks the currently logged-in account and return target. Optional refresh-token changes therefore need consumer validation. |
| `credentials.scopes` | Stored as `granted_scopes`, with nil becoming `[]` at the callback. The identity changeset already splits each entry on commas or whitespace and deduplicates (`accounts/user_identity.ex:25-36`), so this consumer compensates for the library's current multi-scope parsing bug. `Orcid.Api` checks for `/read-limited` before using the stored UID/access token for member funding calls (`orcid/api.ex:485-520`). Preserve requested-versus-granted scope distinction; do not bless the library bug as correct. |
| Other credentials / raw token | No callback read of `credentials.expires`, `expires_at`, or `token_type` was found (the generic callback has only a commented-out `expires_at` binding). No consumer of `extra.raw_info.token` was found in the inspected application source. This does not justify removing it silently: `extra.raw_info.user` is actively read, and any token-duplication change belongs to the later documented compatibility review. |

### Phase 1 implementation status

The generated greeting test has been replaced with offline public `Ueberauth.call/2` request, full code-exchange/userinfo success, and mismatched-state rejection cases. The only HTTP seam is installed `Tesla.Mock`; state is copied from the request cookie into the callback with CSRF protection left enabled. Global application settings are restored in `on_exit`, and the suite is non-async. A single granted `openid` scope avoids pinning the known broken multi-scope split. Runtime `lib/` code and Benchpro are unchanged.

Verified on 2026-09-18 in clean temporary source copies: locked dependency fetch, compilation, format check, and all three tests pass on Elixir 1.14.5 / OTP 25.3.2.21 and Elixir 1.18.4 / OTP 27.3.4. The ordinary working checkout also passes on the canonical pair after recompiling stale artifacts from the previously selected OTP. A separate in-process smoke check confirms the tests restore both pre-existing application settings and absent keys.

Credo 1.7.19 starts on both pairs; ExDoc 0.36.1 generates documentation on the canonical development pair. This is tooling smoke coverage, not a clean Credo analysis or a documentation-link audit. Existing source/dependency warnings remain visible, including Credo's `Map.intersect/2` warning in its check-author test helper on Elixir 1.14.

The GitHub Actions definition passes actionlint 1.7.12. It uses two explicit supported pairs, read-only permissions, pinned actions, and no ORCID secrets or external test service. Hosted GitHub execution remains unverified until pushed; no remote CI success, live login, deployed Benchpro inspection, missing-profile fix, scope-parsing fix, or runtime dependency upgrade is claimed. See [CONTRIBUTING.md](CONTRIBUTING.md) for reproducible commands.

**Acceptance:** a fresh checkout can follow the documented commands and pass real authentication tests without credentials or external network calls after dependency installation. CI runs on fork pull requests. Any unsupported runtime is explicitly excluded and documented.

## Phase 2 — Dependency and supply-chain safety

**Priority: high; do not wait for cosmetic cleanup.**

- [x] Triage all current `mix hex.audit` findings against actual adapter/middleware use. Record package, affected range, fixed release, reachability, and disposition. Consult advisories again at implementation time; this list is a snapshot.
- [x] Upgrade OAuth2, Ueberauth, and their dependency resolutions in reviewable groups. Check release notes and reproduce the successful login contract after each group; do not run an indiscriminate update and assume compilation proves compatibility.
- [x] Review both the library lockfile and Benchpro's lockfile. A library's lockfile is not the dependency resolution installed by its Hex consumers.
- [x] Raise dependency lower bounds only where required for correctness/security, and explain why. Review the application resolution too; change it where remediation is needed. Publishing this library alone does not upgrade Benchpro.
- [x] Make the JSON contract explicit: either declare the supported default as a runtime dependency, or require and document the consumer-provided serializer as Ueberauth does. Preserve configured alternative serializers where supported. Test the chosen contract in a production-only consumer.
- [x] Audit the actual production HTTP adapter: TLS peer/hostname verification, timeout behavior, redirect policy, and credential handling. Do not assume every Tesla adapter/middleware has the same behavior.
- [x] Pin/log a maintained Hex version and add `mix hex.audit` to maintenance/CI. Current Hex checks both security advisories and retired releases; older versions only checked retirement. Use `mix hex.outdated --all` for review, not a rule requiring every dependency to be newest.
- [x] Add one dependency-update mechanism, preferably Dependabot for Mix and GitHub Actions. Use a low-noise schedule and reviewed updates; do not auto-merge authentication dependencies without passing tests. GitHub currently supports Mix version updates but not Mix security-update PRs, so the bot does not replace scheduled Hex auditing.
- [x] Add private vulnerability-reporting instructions and enable available GitHub dependency/security alerts. Keep secrets, real tokens, and private ORCID records out of issue templates and fixtures.

Current examples include [Plug multipart parsing DoS](https://osv.dev/vulnerability/EEF-CVE-2026-8468) and [Tesla cross-origin redirect authorization leakage](https://osv.dev/vulnerability/EEF-CVE-2026-48595). Their presence in a lockfile is a triage signal, not a finding that either behavior is exercised by this package.

**Acceptance:** no untriaged advisory remains; any accepted risk has a reason and review date. The supported production consumer decodes JSON successfully without pulling in Credo or ExDoc. Benchpro's own resolved dependencies are reviewed before rollout.

### Phase 2 implementation status (2026-09-18, unreleased)

Two targeted runtime update groups each passed the three existing authentication
tests. The repository now locks OAuth2 2.1.1, Ueberauth 0.10.8, Plug 1.19.5,
Tesla 1.21.3, Jason 1.4.5, PlugCrypto 2.2.0, MIME 2.0.7, and telemetry 1.4.2.
Development-tool bounds remain unchanged from Phase 1.

[OAuth2 2.1.1](https://github.com/ueberauth/oauth2/releases/tag/v2.1.1) updates
Tesla for security fixes, but its `~> 1.18` requirement still admits vulnerable
1.18.0–1.18.2. This library therefore explicitly requires Tesla >= 1.18.3 and
< 2.0.0. Plug has separate fixed maintenance branches: the published constraint
permits 1.16.6+, 1.17.4+, 1.18.5+, and 1.19.5+ within their respective minors,
or >= 1.20.3 and < 2.0.0. A single `>= 1.16.6` would incorrectly admit vulnerable
releases in newer branches. No dependency override is needed.

The lock selects [Plug 1.19.5](https://hex.pm/api/packages/plug/releases/1.19.5)
because it supports Elixir 1.14; [1.20.3](https://hex.pm/api/packages/plug/releases/1.20.3)
requires 1.15. Unlocked Elixir 1.14 consumers must select a compatible Plug
branch explicitly, as documented in the README.
[Ueberauth 0.10.8](https://github.com/ueberauth/ueberauth/releases/tag/v0.10.8)
fixes callback URL port handling; the floor also excludes retired 0.10.6 and its
reverted routing change. OAuth2 remains open to compatible 2.x releases.

#### Advisory disposition

Intervals below include their lower bound and exclude their upper bound.
All eight original findings are **fixed in the new library resolution**; none is
waived or left untriaged. Reachability is assessed against the default OAuth2
middleware list (`[]`) and `Tesla.Adapter.Httpc`, not arbitrary host configuration.

| Advisory / package | Affected intervals | First fixed releases | Default-flow reachability |
| --- | --- | --- | --- |
| [8468](https://api.osv.dev/v1/vulns/EEF-CVE-2026-8468), Plug multipart header exhaustion | [1.4.0,1.15.4), [1.16.0,1.16.3), [1.17.0,1.17.1), [1.18.0,1.18.2), [1.19.0,1.19.2) | 1.15.4 / 1.16.3 / 1.17.1 / 1.18.2 / 1.19.2 | No multipart parser in this strategy; host multipart endpoints may be exposed. |
| [56814](https://api.osv.dev/v1/vulns/EEF-CVE-2026-56814), Plug multipart temp-file exhaustion | [1.4.0,1.16.6), [1.17.0,1.17.4), [1.18.0,1.18.5), [1.19.0,1.19.5), [1.20.0,1.20.3) | 1.16.6 / 1.17.4 / 1.18.5 / 1.19.5 / 1.20.3 | Same host multipart condition. |
| [56813](https://api.osv.dev/v1/vulns/EEF-CVE-2026-56813), Plug cookie attribute injection | [0.1.0,1.16.6), then the same 1.17–1.20 intervals as 56814 | 1.16.6 / 1.17.4 / 1.18.5 / 1.19.5 / 1.20.3 | Ueberauth writes a cryptographically random, URL-safe state cookie with fixed default attributes; no attacker-controlled attribute path demonstrated here. |
| [48598](https://api.osv.dev/v1/vulns/EEF-CVE-2026-48598), Tesla multipart disposition injection | [0.8.0,1.18.3) | 1.18.3 | No Tesla multipart API; token requests are form-urlencoded. |
| [48595](https://api.osv.dev/v1/vulns/EEF-CVE-2026-48595), Tesla redirect authorization leakage | EEF: [1.4.0,1.18.3); GHSA alias: [0.6.0,1.18.3) | 1.18.3 | No FollowRedirects middleware; native redirects disabled. OAuth2 also lowercases headers before Tesla, avoiding this casing-specific bypass. |
| [48597](https://api.osv.dev/v1/vulns/EEF-CVE-2026-48597), Tesla Mint atom exhaustion | [1.3.0,1.18.3) | 1.18.3 | Requires Mint and attacker-influenced URLs; neither is the default flow. |
| [48594](https://api.osv.dev/v1/vulns/EEF-CVE-2026-48594), Tesla decompression bomb | [0.6.0,1.18.3) | 1.18.3 | Compression/DecompressResponse middleware is absent by default. |
| [48596](https://api.osv.dev/v1/vulns/EEF-CVE-2026-48596), Tesla multipart Content-Type injection | [0.8.0,1.18.3) | 1.18.3 | No multipart content-type parameter API is used. |

The [48595 upstream advisory](https://github.com/elixir-tesla/tesla/security/advisories/GHSA-9m9w-gxf7-rh8m)
has inconsistent starting versions in its metadata and impact text; both cover
the original Tesla 1.7.0 lock and agree on the patch floor. EEF/GHSA aliases are
not counted as separate findings.

Benchpro already locks Plug 1.20.3 and Tesla 1.20.0, fixing all eight findings.
Its endpoint does enable multipart parsing, but the resolved parser is patched.
A read-only copy of its complete lockfile also passes Hex 2.5.1 `mix hex.audit`.
No Benchpro files or resolution were changed: there was no dependency advisory
requiring a bump. Its published ueberauth_orcid 0.2.5 remains unchanged; deployment
of this unreleased library and live login acceptance are still separate work.

#### Transport correction and verification

The supported OTP 25 default did not verify HTTPS peers:
[httpc default SSL options](https://github.com/erlang/otp/blob/OTP-25.3.2.21/lib/inets/src/http_client/httpc.erl#L1024-L1032)
were empty, and SSL defaulted to `verify_none`. A local self-signed HTTPS server
returned HTTP 200 through the real OAuth helper before the fix. The retained
regression also failed before the fix. Canonical OTP 27 already supplied
[verified HTTPS defaults](https://github.com/erlang/otp/blob/OTP-27.3.4/lib/inets/src/http_client/httpc.erl#L808-L816);
do not generalize the OTP 25 finding to all runtimes or Benchpro's deployment.

The OAuth client now supplies native `:httpc.ssl_verify_host_options(true)`,
a 5-second connect timeout, and a 15-second request timeout when using Httpc.
This fixes the shared token/userinfo client without adding an adapter or CA
dependency. Explicit adapter/client/request options keep their precedence;
custom SSL lists must retain verification. Other adapters remain untouched.
Native redirects remain disabled. OAuth2 debug logging includes credentials-bearing
headers/bodies; the README documents keeping it off. Expected network-error
translation and rejection of 3xx userinfo responses remain Phase 3 work.

Verified locally on **both supported pairs**:

- Isolated source copies pass locked dependency fetch, compilation, format, and
  **4 tests, 0 failures**, including the native loopback TLS regression.
- Fresh `MIX_ENV=prod` consumers decode userinfo JSON using default Jason and
  honor a configured serializer, without Credo or ExDoc in the installed graph.
  Canonical resolves Plug 1.20.3; the floor explicitly selects Plug 1.19.5.
- Real transport smoke checks accept a trusted local CA with a matching hostname,
  reject a mismatched hostname, preserve configured adapter trust options, and
  do not follow a credential-bearing 302. Stalled requests time out at 15,001 ms;
  a per-call 100 ms override returns at 101 ms. No real credentials/provider calls.
- Hex 2.5.1 reports no retired or advisory-affected packages for the library and
  both production consumers. This is a registry snapshot, not a future guarantee.

The branch-aware dependency constraints were checked at each vulnerable/fixed
boundary. A local `mix hex.build` succeeds and includes `SECURITY.md` and the
runtime dependency requirements; nothing was published. Broader package metadata
and documentation-link checks remain Phase 5 work.

CI retains the supported matrix and adds a pinned/logged Hex 2.5.1 audit on PRs,
master pushes, manual dispatch, and weekly Tuesday runs. Scheduled runs audit
without repeating the matrix. The workflow passes actionlint 1.7.12; Dependabot
YAML parses successfully. Monthly Mix proposals separate runtime/dev tools with
at most two open PRs; Actions updates form one group with at most one open PR.
No auto-merge. Mix security-update PRs are unsupported, so the weekly audit is
the advisory-monitoring mechanism.

Private reporting, dependency alerts, secret scanning, and push protection were
enabled and confirmed through GitHub's API. `SECURITY.md` supplies private reporting
and an email fallback. Scheduled automation and update proposals require these
files on the default branch; hosted CI, live ORCID login, and deployed Benchpro
settings remain unverified. No Phase 2 commit, push, release, or deployment is
implied by these local results.

## Phase 3 — Authentication correctness and security

**Priority: high. Fix at the shared boundary, with a reproducing test for each defect.**

### Request, callback, and errors

- [x] Correct `authorize_utl` to the supported client option and test the resulting authorization URL. An upstream fallback may mask the typo today.
- [x] Make callback/redirect URI handling consistent between authorization and token exchange. Test deployment behind a correctly configured HTTPS reverse proxy and explicit callback overrides; never derive trusted redirect configuration from arbitrary untrusted headers.
- [x] Remove the implicit localhost production trap while keeping a documented local-development recipe. Missing required configuration should fail clearly without exposing values.
- [x] Preserve the intended `get_token!/2` options structure: headers, HTTP options, and client options are currently obscured by rebinding. Characterize existing callers before changing the public helper contract.
- [x] Use `:oauth2_module` consistently for authorization, token exchange, and userinfo retrieval.
- [x] Handle provider denial (`error`, `error_description`) distinctly from a missing authorization code. Return Ueberauth failures with sanitized, stable categories.
- [x] Use non-raising dependency APIs for expected token-exchange failures where available. Do not turn timeouts, bad/expired codes, revoked tokens, or invalid JSON into unhandled request crashes; do not blanket-rescue programming errors either.
- [x] Handle actual OAuth2 success/error tuple shapes for 400, 401, 403, 429, 5xx, transport errors, and malformed bodies. Do not accept redirects or arbitrary `200..399` responses as a valid userinfo document.
- [x] Validate the access token and required identity claim at the trust boundary before constructing a successful auth result. Reject empty/wrong-type values; optional profile omissions must remain valid.
- [x] Preserve Ueberauth's existing state protection, rather than implement a second mechanism. Locked Ueberauth 0.10.8 generates/checks cookie-backed state and deletes the cookie after a successful callback. Test matching/missing/mismatched state and missing cookies through the public pipeline; calling `handle_callback!/1` alone cannot prove CSRF protection. Separately test that replaying a consumed authorization code cannot authenticate again.
- [x] Remove the redundant `client_secret` parameter and duplicate client construction in `OAuth.get/4`. Baseline source tracing confirmed that OAuth2 2.1.0 does **not** serialize that parameter on the ordinary resource GET; this is not a demonstrated wire leak. Capture real outgoing requests to preserve bearer-only userinfo access across upgrades.
- [x] Verify token-endpoint authentication against ORCID's advertised `client_secret_post` method. The current code adds body credentials while OAuth2's AuthCode strategy also adds Basic auth. Use the supported provider contract without removing working body authentication on the assumption that generic Basic auth is sufficient.
- [x] Keep provider/network errors free of authorization codes, tokens, client secrets, and raw sensitive response bodies. Do not blindly retry authorization-code exchange; codes are one-use credentials.

### Identity, profile, and temporary state

- [x] Keep ORCID `sub` as the current stable UID source; explicitly define behavior for missing/invalid identity. Consider any alternate `/authenticate` flow separately rather than changing UID lookup implicitly.
- [x] Make name mapping nil-safe and tolerant of absent, blank, and malformed optional fields. Define fallback behavior using ORCID's available name claims, not invented profile data.
- [x] Review `nickname: user["name"]` against existing consumers before remapping it. An apparently nicer mapping can still be an API break.
- [x] Define email behavior explicitly: an email request is not a guarantee of an email response. Never fail login for missing email or use an unverified/private email assumption to link accounts.
- [x] Remove the unused `allow_private_emails` variable and misleading documentation/advertised options, if any. Do not implement access to private email just to justify dead code.
- [x] Parse granted scopes as OAuth space-delimited values, with a clear empty/missing-scope result. Keep requested scopes distinct from actually granted scopes.
- [x] Preserve optional refresh-token and expiration semantics; do not invent expiration or assume a refresh token is always issued.
- [x] Clear both temporary private user and token fields on success/failure cleanup. This is distinct from credentials intentionally returned in `Ueberauth.Auth`.
- [x] Review token duplication in `extra.raw_info`. Prefer not duplicating secrets, but first check Benchpro's contract and document/version any removal. Warn consumers not to log the complete auth struct even after cleanup.
- [x] Tighten configuration errors for missing, nil, blank, wrong-type, and unavailable environment-based credentials. Errors should identify the key, never print its value.
- [x] Remove obsolete comments and generator remnants, fix empty module docs and the incorrect UID default documentation, and add useful public API typespecs. Avoid mechanical abstractions or callback renames.

**Acceptance:** successful auth retains the agreed consumer-visible contract; every expected provider/network failure produces a controlled failure; optional profile omissions do not crash; state/credential protections are exercised through the real request boundary.

### Phase 3 implementation status (2026-09-18, unreleased)

Phase 2 was committed as `25a1584`. Phase 3 changes are not yet committed or
released. The README now documents callback configuration, a local-development
recipe, the custom-module migration, and consumer-visible result/failure behavior.

#### Request and response boundaries

- Fixed the authorization option and made default authorization/token paths
  relative to `site`, so a sandbox site does not retain a production token URL.
  Explicit absolute endpoint overrides remain available.
- Authorization and token exchange use the same effective Ueberauth callback.
  There is no implicit localhost URI. Direct helpers require an effective
  explicit redirect; `send_redirect_uri: false` uses the configured client URI.
  Tests cover explicit callbacks despite spoofed forwarding headers and a trusted
  proxy-normalized connection with a nondefault HTTPS port. Phase 5 documentation
  review corrected the earlier trust claim: without `callback_url`, Ueberauth's
  helper reads Host and forwarded headers. Use an explicit trusted callback or
  validate/strip those headers at the host application's proxy boundary.
- The callback uses non-raising token exchange. The helper validates HTTP 200,
  JSON object shape, access-token/Bearer fields and optional expiry/refresh values
  before constructing a token. It uses public `OAuth2.Client` request APIs rather
  than the upstream token helper, which constructs tokens before these checks.
- [ORCID discovery](https://orcid.org/.well-known/openid-configuration) advertises
  `client_secret_post`. Token requests now use POST form credentials without
  duplicate Basic authentication. Userinfo uses bearer authentication and no
  added client-secret parameter; the redundant client construction is gone.
- Expected provider/status/transport/JSON failures become controlled, sanitized
  Ueberauth failures. Denial is distinct from missing code. Redirects, non-200
  userinfo and non-JSON profile/token bodies cannot authenticate. There are no
  automatic token retries. Known JSON-parser exceptions and the dependency's
  malformed-content-type error are handled narrowly; programmer errors propagate.
  Jason and a configured wrapper serializer are exercised; optional Poison
  exception handling is implemented, not a claim that Poison was installed/tested.
- The public bang token API is retained with sanitized exceptions. Its
  `headers`, `options`, and `client_options` remain top-level and influence the
  actual request. Credential errors cover missing/nil/blank/wrong-type and legacy
  environment-based values without reflecting those values.

#### Identity and compatibility decisions

- A nonblank string `sub` remains mandatory; configurable `uid_field` selection
  is preserved and its selected claim must also be nonblank. No invented ORCID
  checksum/format restriction or email fallback was introduced.
- Valid given/family names are trimmed and joined; credit name is the fallback.
  `info.nickname` retains the credit-name claim consumed by Benchpro. Missing,
  blank, malformed or Unicode optional names do not crash authentication.
  `info.email` remains nil, even when raw userinfo includes an email.
- Granted scopes are whitespace-delimited, with missing/empty values producing
  `[]`; requested scopes remain unchanged. Optional refresh/expiry values are
  preserved rather than invented.
- Cleanup removes both temporary private fields, including on CSRF/provider
  failure. Raw userinfo and the raw token are deliberately retained in
  `extra.raw_info` to avoid an unrelated public-result removal. Benchpro's
  inspected consumer needs raw name claims; no raw-token consumer was identified,
  but absence in that app is not proof that other consumers do not use it.
  The README warns that returned auth structs still contain secrets.
- Custom OAuth modules now implement `authorize_url!/2`, `get_token/2` and `get/4`;
  all stages use the configured module. No partial-module fallback was added.
  With explicit user approval, `../benchpro/lib/benchpro/orcid/prompt_login_oauth.ex`
  gained the non-raising token and userinfo delegates. Its existing authorization
  customization and real bang API remain; the latter is still used by Benchpro's
  currently locked 0.2.5. No Benchpro lockfile, configuration, persistence schema,
  or other source file was changed, and no Benchpro changes were committed.

#### Verification

- Against isolated sources from `25a1584`, the 50 new public-callback regressions
  fail, exposing the old crashes, accepted invalid data, redirect mismatch and
  retained temporary credentials. With the fixes, all **71 tests pass** on both
  Elixir 1.14.5/OTP 25.3.2.21 and Elixir 1.18.4/OTP 27.3.4. Existing successful
  login, state and native TLS tests remain intact.
- Clean checkouts on both pairs pass locked dependency fetch, compilation and
  formatting. Library source compilation is warning-free. The floor still emits
  the known Credo check-author helper warning; it is not hidden.
- Fresh production-only consumers on both pairs compile the **actual approved
  Benchpro wrapper** against this library and complete the real Ueberauth flow
  over native Httpc to a loopback provider. Checks cover encoded form-only
  credentials, `prompt=login`, matching callback, minimal userinfo, granted scopes,
  cleanup, and controlled rejection of a consumed code. A top-level token HTTP
  timeout of 80 ms returns at 81 ms on both pairs. Credo/ExDoc are absent.
- Canonical `mix test --cover` passes: **98.05% total** (strategy 97.01%, OAuth
  helper 98.85%). No coverage threshold was lowered or new coverage dependency
  added. This measures exercised code, not security completeness.
- Hex 2.5.1 audit remains clean. ExDoc builds the new public API documentation;
  existing documentation-tool dependency deprecations remain visible. This is
  not a documentation-link/package-release audit. Benchpro wrapper formatting
  also passes.

The loopback consumer is not the running Benchpro application or its database.
Live ORCID consent, actual deployment/proxy configuration, application persistence,
hosted CI and rollout remain unverified. Normal tests require no ORCID account
or real credentials. Phase 4 quality-tool/CI gates and later release acceptance
remain separate work.

## Required behavioral test inventory

Use ExUnit and `Plug.Test` already available through the stack. Keep fixtures synthetic and small. Mock the external boundary, not the strategy logic under test. Add cases alongside their fixes, rather than a large unrelated test-only rewrite.

| Area | Observable cases to protect |
| --- | --- |
| Authorization request | Trusted production/sandbox endpoint; encoded client ID, scope, callback URL, state; configuration overrides honored. |
| Complete successful callback | Correct UID, defined profile fields, granted scopes, token type/expiration, and configured OAuth implementation used end-to-end. |
| State boundary | Matching state reaches exchange; missing/mismatched state or missing cookie fails before exchange; success clears the state cookie; consumed-code replay cannot authenticate again. |
| Provider refusal | Access denied, missing code, expired/reused code, malformed token response, missing/empty token. |
| Userinfo failure | Unauthorized/forbidden, rate limit, server error, timeout, connection error, invalid JSON, unexpected content type/body, redirects rejected as profile data. |
| Profile/identity | Minimal valid identity, absent family/given names, Unicode names, absent/private email, wrong-type claims, missing identity; no email-based identity fallback. |
| Credentials | Space-delimited/missing/empty granted scopes, absent refresh token, expiring/non-expiring token. |
| Configuration | Production and sandbox do not mix; callback consistency; supported serializer; bad credentials fail clearly and safely; HTTP/client options affect the actual request. |
| Secret handling | Token exchange secrets not sent to unrelated hosts/resources, no sensitive failure output, temporary private fields cleaned. |
| Packaging | Fresh production-only consuming application can install, start required applications, decode responses, and run the documented integration. |

Use `mix test --cover` initially; set an explicit realistic threshold after meaningful tests exist (Mix has a default threshold, so measurement can itself fail). Coverage is a gap detector, not evidence that authentication is secure. No need for ExCoveralls or a hosted coverage service until a coverage report/badge provides real value.

Keep a separate, explicitly invoked ORCID sandbox smoke procedure. Normal CI must not require live ORCID, credentials, consenting accounts, or network availability. A real sandbox login is a release check, not a deterministic unit test.

## Phase 4 — Quality tools and sustainable CI

| Check | Decision | Gate |
| --- | --- | --- |
| Formatter | Use built-in `mix format --check-formatted`. | Every PR. |
| Compiler | `MIX_ENV=test mix compile --warnings-as-errors`, plus `mix test --warnings-as-errors` for test compilation. Review dependency warnings without blanket suppression. | Every supported test pairing. |
| ExUnit | `mix test`; coverage on one canonical pairing. | Every PR. |
| Credo | Upgrade existing dependency; run `mix credo --strict` after fixing actionable findings. No giant configuration file unless needed. | One canonical pairing. |
| Dialyzer | Add Dialyxir as a development-only, non-runtime dependency; run `mix dialyzer`. Fix types/contracts, not blanket ignore files. | One canonical pairing; cache PLTs by OS/OTP/Elixir/dependencies. |
| Sobelow | Evaluated and retained for generic unsafe Elixir patterns; it is not an OAuth audit and this library has no Phoenix router. | `mix sobelow --private --exit low` fails on every confidence level (confidence is not severity); no exclusions. |
| Dependency audit | Native Hex advisory/retirement checks; review outdated packages separately. | PRs plus scheduled checks to catch newly published advisories. |
| Documentation/package | Build ExDoc and `mix hex.build`; inspect links and package contents. | Canonical pairing and release preparation. |

### CI hosting and safety

- [x] Use GitHub Actions on standard GitHub-hosted Linux runners for this public GitHub repository. Verify current billing rules before enabling paid runner classes or changing visibility.
- [x] Test the supported minimum and a current stable Elixir/OTP pairing; include Benchpro's pair if neither covers it. Pin explicit versions and use a valid compatibility table when choosing them.
- [x] Run analysis/docs on one pairing, not on the whole matrix. Avoid macOS/Windows jobs unless a platform-specific support need emerges.
- [x] Start without caches if builds are already quick. If useful, cache dependencies/builds by OS/architecture, Elixir, OTP, environment, and lockfile; cache Dialyzer PLTs separately. Never cache secrets or the entire Hex home; a cold build must work, and release jobs must not trust PR-built artifacts.
- [x] Use read-only default token permissions, pinned action revisions, timeouts, and cancellation of superseded PR builds. Keep third-party actions minimal and update pins deliberately.
- [x] Run untrusted contributions with `pull_request`, without secrets. Never run PR code in a privileged `pull_request_target` job. Keep publishing separate from PR validation.
- [x] Add a scheduled audit and dependency update review. Consider an unlocked/latest-compatible dependency job only after the locked baseline is stable; it answers a different question from reproducible CI.
- [x] Require the small stable check set before merging. Keep manual release approval; release automation can come later.

**Free versus open source:** [standard GitHub-hosted runners are free for public repositories](https://docs.github.com/en/billing/concepts/product-billing/github-actions); larger runners are charged, and storage/cache allowances still matter. GitHub Actions' hosted service is not a fully open-source CI system, although its [runner is MIT-licensed](https://github.com/actions/runner/blob/main/LICENSE). If an open-source control plane is a requirement, [Woodpecker](https://woodpecker-ci.org/docs/intro) is an Apache-2.0 alternative; [Forgejo Actions](https://forgejo.org/docs/latest/user/actions/overview/) is another route on a Forgejo instance. Neither guarantees free hosted compute. Use an existing instance rather than operate another CI stack just for this library.

**Acceptance:** all documented local checks can be reproduced in CI; fork PRs work without secrets; the supported matrix is honest; no permanently allowed-failing quality job or unexplained warning suppression remains.

### Phase 4 implementation status (2026-09-18, unreleased)

- Babysitter run `01M2TWATNT7JV22DRJH421FBYG`: the user approved CLI-driven
  execution without Pi session binding and explicitly approved merge protection.
  No session ID was invented; nothing was committed, pushed or released.
- Added dev-only, non-runtime Dialyxir 1.4.8 and Sobelow 0.15.0; moved Credo
  1.7.19 to dev-only. Only Dialyxir, Erlex 0.2.9 and Sobelow were added to the
  lockfile. Runtime requirements/resolutions and Benchpro files are unchanged.
- [Elixir 1.20.4](https://github.com/elixir-lang/elixir/releases/tag/v1.20.4)
  is the current stable release; the official compatibility table supports
  OTP 27. Canonical development/analysis now uses 1.20.4-otp-27 / OTP 27.3.4.
  Tests retain 1.14.5-otp-25 / 25.3.2.21 and 1.18.4-otp-27 / 27.3.4.
  Benchpro's declared 1.18/OTP 28 pair remains unsupported, not a CI promise.
- All three test jobs enforce compiler/test warnings as errors. Coverage runs
  on the canonical test job; formatter, strict Credo, Dialyzer, Sobelow, docs and
  package build run once in the canonical quality job. Six Credo findings were
  fixed with aliases, ordering and flatter token validation, preserving behavior.
- Public visibility and current GitHub standard-runner billing were confirmed.
  CI stays on Ubuntu 24.04 with pinned actions, read-only permissions, no
  secrets/privileged PR trigger, bounded timeouts and cancellation. Only PLTs
  are cached, keyed by OS/architecture/Elixir/OTP/environment/lockfile, with no
  restore fallback. No dependency/build/Hex-home caches or release artifacts.
- Weekly auditing and monthly grouped Dependabot updates remain. Reviewed
  outdated dependencies separately; no unlocked job before stable hosted
  history. Older doc tooling and the floor-compatible Plug lock are retained.
- GitHub API confirmed `master` requires `test floor`, `test consumer`,
  `test current`, `quality`, and `audit` from GitHub Actions app 15368, with
  strict/up-to-date checks and administrator enforcement; force pushes/deletion
  are disabled. **The workflow must be pushed before PRs can satisfy these
  checks.** Publication remains manual.
- Corrected ExDoc source refs: actual `0.2.5`-style release tag by default,
  `SOURCE_REF` override for CI's commit SHA. Packaged the existing contributor
  guide and removed the nonexistent Changelog metadata link. Broader Phase 5
  setup-guide/changelog/badge/release work remains separate.

Verification:

- Fresh isolated floor and consumer checkouts resolved the lockfile, compiled
  with warnings-as-errors and passed **71 tests each**, also rerun after the
  source refinement. Current canonical: **71 passed, 98.06% coverage**.
  No lowered threshold, new framework or permanent CI-plumbing tests.
- Strict Credo: zero issues across seven files. Dialyzer: cold PLTs built in
  about 53 seconds; zero errors/skips, including all runtime transitive apps;
  warm rerun also passed. No analysis configuration/ignore files needed.
- Sobelow: zero findings, exit 0. An isolated injected `Code.eval_string(input)`
  produced a low-confidence RCE finding and exit 1, proving gate relevance.
  The expected missing-router notice is documented, not suppressed.
- Hex audit: no retirement/security advisories. `hex.outdated --all` returned
  its expected nonzero status for available updates; it is a review command,
  not a required freshness gate.
- ExDoc and Hex build passed. All ten generated HTML pages had valid local
  link targets/anchors; source links honored `SOURCE_REF=updates`. Remote links
  cannot show unpushed changes yet. Inspected package contents/metadata:
  intended source/docs only, no tests/PLTs/build/dependency/orchestration files,
  and no development-tool runtime requirements.
- Checksum-verified actionlint 1.7.12 accepted the workflow; upstream APIs
  confirmed the action pins. **Local/static evidence is not a hosted CI run
  or a fork-PR execution.** No real ORCID or Benchpro app/database test is implied.
- Reviewed Elixir 1.20 dependency warnings: Plug 1.19.5's deprecated `xref`/
  bitstring syntax and one inferred unreachable clause; older ExDoc/Makeup/
  NimbleParsec deprecation/type warnings. Project source/tests are warning-free.
  Mix's project warnings-as-errors flag does not promote dependency warnings;
  no global suppression, dependency patch or allowed-failing job was added.


## Phase 5 — Documentation, badges, and release

### README and HexDocs

- [x] Replace generated installation prose with a real setup guide: dependency, runtime credentials, Ueberauth provider registration, host app session/pipeline requirements, request/callback routes, and success/failure handling.
- [x] Remove the unrelated `Benchlight.Application` example. Check application auto-start behavior before telling users to manually extend `extra_applications`.
- [x] Show production and sandbox registration/setup separately; explain callback registration, HTTPS, environment-specific credentials, scopes, JSON configuration, and the expected returned auth fields.
- [x] Document every supported option and its default, including scope override policy, callback override, custom OAuth module, and credential configuration. Do not advertise settings that do nothing.
- [x] Explain optional names/emails, token privacy, logging precautions, account linking, and the division of responsibilities between ORCID, the strategy, Ueberauth, and the consuming app.
- [x] Add troubleshooting for state/cookie failures, redirect mismatches, consent denial, missing profile data, configuration errors, and upstream outages. Never request users' secrets in bug reports.
- [x] Update `CONTRIBUTING.md` with exact setup/check commands, supported runtime policy, isolated test rules, and sandbox testing instructions.
- [x] Add a changelog and security-reporting policy; include the appropriate documentation files in the Hex package and ExDoc extras. Avoid creating a large governance-document collection for a tiny library.
- [x] Fix ExDoc source refs to actual tags. Existing tags are `0.2.5`-style, not `v0.2.5`; the current `"#v{@version}"` string is not interpolation. Completed during Phase 4 package/link checks; CI uses its actual commit SHA.
- [ ] Verify generated source links, README links, module docs, and the advertised changelog URL before publishing. Local pages/anchors, source-ref generation and existing public README/badge destinations passed; final `0.3.0` tag/source/HexDocs URLs remain gated on authorized publication.

### Badges worth adding

Start with **CI status**, **Hex version**, **HexDocs**, and **MIT license**. Link each badge to the actual workflow, package, documentation, or license. Add them only when their destinations exist and accurately describe the released/default-branch state.

Coverage is optional, only with a maintained report. Skip downloads, stars, build-tool logos, or generic “secure” badges: they do not establish quality. A Sobelow badge is not proof that the OAuth integration is secure.

### Release checklist

- [x] Choose release numbering from the actual compatibility impact. Security/bug fixes, new opt-in features, and changed defaults need distinct release notes; pre-1.0 is not permission for silent breaks.
- [x] Run the full documented check set from a clean dependency/build state on the supported matrix.
- [x] Build the package, inspect its contents, and install it in a disposable production-mode consumer. Ensure no credentials, fixtures with private data, or development tooling are shipped as runtime dependencies.
- [x] Perform sandbox login and denial flows using registered sandbox credentials. Inspect returned UID/profile/credentials without writing secrets to logs.
- [x] Record the previous dependency version/lockfile and rollback procedure before rolling out Benchpro. Any identity or data migration needs its own reversible plan. Source baseline and full-lock checksum recorded; actual deployed image/runtime/configuration must still be captured before deployment.
- [ ] Publish matching package/docs/tag/release notes, then verify the public package installation, HexDocs links, and badges. Do not publish as a side effect of an ordinary branch push.
- [x] Establish a lightweight maintenance cadence: scheduled automated audit/update proposals, periodic triage, and a sandbox check before authentication-affecting releases.

**Acceptance:** a new user can install and configure the package from the README
without relying on knowledge from Benchpro, and the released artifact works
independently.

**Downstream adoption:** Benchpro should separately validate existing-account
identity, fresh-account behavior, missing optional profile data, denial and
duplicate prevention before deploying its dependency upgrade to production.
That consumer-owned staging check is not a gate for publishing this library.

### Phase 5 release-candidate status (2026-09-22)

The user authorized commit, push and release work after registered sandbox
acceptance completed. Benchpro staging was reclassified as downstream adoption,
not a library publication gate. Babysitter run
`01M2VBPT6ZRV8RRAHJEC16SWV8` records the earlier preparation scope.

- `mix.exs` now prepares **0.3.0**: the full custom OAuth module contract,
  explicit callback requirements and effective OTP floor warrant a minor
  release, not a silent 0.2.x patch. `CHANGELOG.md` separates compatibility,
  security, fixes and tooling. No dependency or authentication behavior changed
  in this preparation phase.
- README now includes an executable read-only Plug router, runtime configuration,
  separate sandbox/production setup, every supported strategy option, scope
  override policy, custom-module migration, result/privacy contracts and
  troubleshooting. The host owns accounts and sessions; the example does not
  invent persistence.
- Corrected the forwarding-header trust documentation in README, module docs
  and the earlier roadmap note. The inherited Ueberauth URL helper reads
  forwarded/Host headers when no explicit callback is supplied. The recommended
  configuration pins a trusted callback; no new runtime policy was introduced.
- Added CHANGELOG and SECURITY to ExDoc extras and CHANGELOG to package files.
  The versioned Changelog metadata URL points at the 0.3.0 docs. Hex/HexDocs/
  MIT/CI badges target their release destinations; hosted CI must pass before
  publication.
- Contributor instructions cover clean verification, secret-safe live acceptance,
  exact Benchpro 0.2.5 source-lock checksums, full-artifact rollback, guarded
  manual publication and maintenance cadence. Deployed Benchpro image/runtime/
  configuration remain unknown; no sibling files or lockfile were changed.

Verification:

- Three new source copies began without `deps`, `_build` or PLTs. All resolved
  the lockfile and passed warnings-as-errors compilation/tests: **71 passed**
  on each supported pair. Canonical coverage: **98.06%**. Strict Credo, cold
  Dialyzer (zero errors/skips), Sobelow and Hex audit passed; documented upstream
  warnings and Sobelow's non-Phoenix router notice were not suppressed.
- Final ExDoc generated **12 pages** with `SOURCE_REF=0.3.0` and no missing
  local link targets or anchors. All **17 external README/badge URLs** had
  returned HTTP 200 after redirects during preparation.
- Built and inspected the finalized `ueberauth_orcid-0.3.0.tar`: nine intended
  source/docs files, runtime dependencies only, no tests/fixtures/credentials/
  PLTs/orchestration/development tools. Tarball SHA-256:
  `eb92d5439370dabcd2c8800be5c5040730ed84a0b7873131b65be2f34904f4ec`.
- Installed that finalized tarball's extracted contents, not the working
  checkout, into a fresh production-mode consumer on Elixir 1.20.4/OTP 27.3.4.
  It compiled with warnings as errors, passed Hex audit, started normally as a
  dependency at version 0.3.0, and did not expose Credo or ExDoc at runtime.
  Earlier separate floor/canonical consumers exercised the exact README router
  and runtime snippets with real loopback token/userinfo HTTP, minimal profile,
  denial, invalid/missing state, scope rejection, cleanup and sandbox routing.
  Consumer audits passed with Plug 1.19.5 and Plug 1.20.3.
- Repeated the packaged canonical flow with the actual read-only Benchpro
  wrapper, including its `prompt=login` parameter. This proves source-wrapper
  compatibility, **not staging account identity, database behavior or deployment**.
- Registered ORCID sandbox acceptance subsequently passed against the 0.3.0
  candidate using the exact configured callback. A real authorization returned
  a stable nonblank UID, optional name, nil email, granted `openid` scope,
  refresh token and expiry without logging secrets. A separate sandbox identity
  denied consent; the callback returned the sanitized `access_denied` failure.
  The disposable server, browser session and local artifacts were removed.
- Hosted CI, tag creation, public installation and publication remained pending
  at this checkpoint. Benchpro staging is tracked by that downstream consumer,
  not as a library release gate.


## Phase 6 — ORCID capability review, not automatic scope expansion

The current implementation requests `openid email profile` and fetches `/oauth/userinfo`. [Live production discovery](https://orcid.org/.well-known/openid-configuration) and [sandbox discovery](https://sandbox.orcid.org/.well-known/openid-configuration) advertise `openid`, not the `email` or `profile` scope names; their claims list includes names and `sub`, but no email. The current upstream userinfo model likewise has no email field. This does **not** establish that the extra scope strings are rejected in Benchpro's working flow: no authenticated scope experiment was performed.

For the existing userinfo architecture, assess `openid` as the minimal default after characterizing Benchpro compatibility, and document any change. `/authenticate` is a different valid login path: its identity comes from the token response's `orcid` field, and substituting that scope alone would leave the current userinfo request without its required `openid` permission. Discovery is not an exhaustive catalog of ordinary ORCID API scopes.

Production login endpoints use `orcid.org`; sandbox uses `sandbox.orcid.org`. Since Phase 3, default authorization/token paths are relative, so overriding `site` selects the sandbox coherently unless absolute endpoint overrides remain in application configuration. Record APIs instead use `pub.orcid.org`/`api.orcid.org` and their sandbox counterparts. Preserve the current bare ORCID UID and supported `uid_field` customization; isolate sandbox accounts from production rather than silently changing UID format.

| Capability | Roadmap disposition |
| --- | --- |
| Sandbox support | Document and test coherent environment-specific endpoints and credentials now; a convenience option is warranted only if existing configuration is too error-prone. |
| Identity-only `/authenticate` flow | Evaluate as a distinct optional mode if Benchpro or another consumer wants it. It requires an explicit token-response identity mapping, not just swapping the current scope string. |
| Profile/email claims | Names can be absent/null; email is not a supported userinfo promise. Tolerate omissions and remove misleading private-email expectations rather than request broader API access for login. |
| ORCID record URL/display | Document canonical ORCID links and official display guidelines; only add mapped fields if consumers need them. Keep UI rendering out of the strategy. |
| Authorization UX parameters | Consider documented language/login/prompt/account-selection parameters only for a concrete UX need. Allowlist supported parameters; do not blindly forward arbitrary query parameters. |
| PKCE | Not implemented here; provider support remains unverified. Neither inspected discovery document advertises `code_challenge_methods_supported`. Absence alone does not prove lack of support. Require authoritative support and sandbox S256 success/failure checks before advertising it. |
| Full OIDC ID-token validation | If ID tokens become an identity source, require signature, issuer, audience, expiry, nonce, and subject consistency checks with a maintained implementation. Merely requesting `openid` is not a claim of full OIDC-client validation. |
| Refresh/revoke helpers | ORCID documents both capabilities, but this package has no dedicated lifecycle API. Credentials already expose refresh/expiry fields; generic dependency refresh support does not prove ORCID wire-auth compatibility. Document token storage/disconnection ownership first; add explicit helpers only for a consumer need, not a background worker. Local logout is not ORCID token revocation. |
| Member API scopes, affiliations, works, record writes, webhooks | Outside this maintenance release. These require distinct permissions, privacy/consent handling, and often ORCID membership; use a separate API client/integration if needed. |

## Suggested PR-sized delivery sequence

1. **Development baseline:** Credo/ExDoc compatibility, replace generated test with actual request/success tests, support policy, minimal CI.
2. **Dependency safety:** advisory triage, targeted runtime dependency updates, explicit JSON contract, production-consumer check, audit/update automation.
3. **Callback hardening:** request/client option consistency, error handling, optional profile data, scopes, state-boundary tests, cleanup and secret handling. Split further by independently testable behavior if needed.
4. **Quality gates:** typespec corrections, Dialyxir, scoped Sobelow, complete supported matrix and coverage visibility.
5. **Release readiness:** README/HexDocs/changelog/security guidance, source links, badges, registered sandbox acceptance and release.
6. **Demand-driven features:** only separately accepted ORCID capability work from Phase 6.

The maintenance release is done after PRs 1–5 meet their acceptance criteria. Phase 6 is a decision backlog, not a prerequisite or a promise to implement everything.

## Primary references

These informed the roadmap; recheck provider/tool behavior when implementing it.

- **ORCID:** [OIDC guide](https://github.com/ORCID/ORCID-Source/blob/main/orcid-web/ORCID_AUTH_WITH_OPENID_CONNECT.md), [supported OAuth scopes](https://info.orcid.org/ufaqs/what-is-an-oauth-scope-and-which-scopes-does-orcid-support/), [redirect registration rules](https://info.orcid.org/ufaqs/how-do-redirect-uris-work/), [userinfo model](https://github.com/ORCID/ORCID-Source/blob/main/orcid-core/src/main/java/org/orcid/core/oauth/openid/OpenIDConnectUserInfo.java), [refresh protocol](https://github.com/ORCID/ORCID-Source/blob/main/orcid-api-web/tutorial/refresh_tokens.md), [revocation protocol](https://github.com/ORCID/ORCID-Source/blob/main/orcid-api-web/tutorial/revoke.md).
- **Existing security boundary:** [Ueberauth 0.10.5 state implementation](https://github.com/ueberauth/ueberauth/blob/v0.10.5/lib/ueberauth/strategy.ex#L318-L429), [OAuth2 2.1.0 request serialization](https://github.com/ueberauth/oauth2/blob/v2.1.0/lib/oauth2/request.ex), [authorization-code strategy](https://github.com/ueberauth/oauth2/blob/v2.1.0/lib/oauth2/strategy/auth_code.ex).
- **Quality tooling:** [Credo usage](https://hexdocs.pm/credo/basic_usage.html), [Dialyxir](https://hexdocs.pm/dialyxir/readme.html), [Sobelow](https://github.com/nccgroup/sobelow), [native Mix coverage](https://hexdocs.pm/mix/1.14.5/Mix.Tasks.Test.html#module-coverage), [Hex audit](https://hexdocs.pm/hex/Mix.Tasks.Hex.Audit.html), [Hex outdated](https://hexdocs.pm/hex/Mix.Tasks.Hex.Outdated.html).
- **CI and maintenance:** [GitHub Actions security](https://docs.github.com/en/actions/reference/security/secure-use), [Dependabot ecosystem support](https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories), [workflow badges](https://docs.github.com/en/actions/how-tos/monitor-workflows/add-a-status-badge), [setup-beam](https://github.com/erlef/setup-beam).
- **Publishing:** [Hex build](https://hexdocs.pm/hex/Mix.Tasks.Hex.Build.html), [Hex publish/dry run](https://hexdocs.pm/hex/Mix.Tasks.Hex.Publish.html), [existing release tags](https://api.github.com/repos/brecke/ueberauth_orcid/tags).
