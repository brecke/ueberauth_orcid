# Contributing to Ueberauth Orcid

## Toolchains and quick start

The library retains its Elixir `~> 1.14` requirement. CI checks two explicit
[compatible Elixir/OTP pairs](https://hexdocs.pm/elixir/compatibility-and-deprecations.html#between-elixir-and-erlang-otp),
not every combination:

| Purpose | Elixir build | Erlang/OTP |
| --- | --- | --- |
| Compatibility floor | `1.14.5-otp-25` | `25.3.2.21` |
| Canonical development | `1.18.4-otp-27` | `27.3.4` |

The floor preserves existing consumer compatibility; it is not a recommendation
to deploy an end-of-life Elixir release. The canonical pair is intentionally
reproducible, not a claim to track the latest release. Elixir 1.18 with OTP 28 is
unsupported and excluded. Other pairs are not covered by this CI matrix.

Install [mise](https://mise.jdx.dev/getting-started.html), then run these commands
from the repository root. `.tool-versions` selects the canonical pair locally;
there is no need to change global defaults:

```sh
mise install
mise exec -- mix local.hex --force
mise exec -- mix local.rebar --force
export MIX_ENV=test
mise exec -- mix deps.get --check-locked
mise exec -- mix compile
mise exec -- mix format --check-formatted
mise exec -- mix test
```

CI installs Hex/Rebar through `setup-beam`, then runs the same four Mix commands
with `MIX_ENV=test` on Ubuntu 24.04. To check the floor locally, install
`mise install erlang@25.3.2.21 elixir@1.14.5-otp-25` and replace `mise exec --`
with `mise exec erlang@25.3.2.21 elixir@1.14.5-otp-25 --` above.

When switching OTP versions in an existing checkout, recompile dependency
artifacts with `MIX_ENV=test mise exec -- mix deps.compile --force` before
running the checks. Old BEAM files from a different OTP version can fail to
load even when the source is compatible. CI starts from a fresh checkout.

Tests use synthetic identities and the installed HTTP client's test adapter:
after dependency installation, they need no ORCID credentials or network calls.
Tests changing application environment must use `async: false` and restore
every changed key in `on_exit`. A passing offline suite is not proof of a live
ORCID login or Benchpro deployment.

## Development tools and current limits

Credo is development/test-only and bounded to `~> 1.7.19`.
[ExDoc 0.36.1](https://hex.pm/api/packages/ex_doc/releases/0.36.1) is bounded to
the last line supporting Elixir 1.14; newer lines require Elixir 1.15. This is a
compatibility pin, not a claim of upstream backports. Use the canonical
Elixir 1.18.4/OTP 27.3.4 pair for development and documentation tooling;
the Elixir 1.14 floor is checked with `MIX_ENV=test`, not documentation builds.
These tools are not runtime applications. Runtime OAuth
dependencies remain unchanged in this phase.

The baseline still has the unused `allow_private_emails` source variable and
dependency deprecation warnings. CI deliberately uses ordinary compilation
and tests, without suppressing warnings or ignoring failed steps. Enable
warnings-as-errors only after those warnings are addressed. Credo's strict
gate, dependency advisory remediation/auditing, Dialyzer, Sobelow, coverage,
documentation/release checks, and live sandbox acceptance remain later roadmap
work, not passing checks implied by this workflow.

CI runs on pushes to `master` and `pull_request`, including fork contributions,
using a read-only token, no repository secrets, and full action commit pins.
Review upstream release notes and action inputs before changing those pins.
Hosted CI results must be checked on GitHub; local results do not establish
that a remote run has passed.

## Pull Requests Welcome

1. Fork ueberauth_orcid
2. Create a topic branch
3. Make logically-grouped commits with clear commit messages
4. Push commits to your fork
5. Open a pull request against ueberauth_orcid/master

## Issues

If you believe there to be a bug, please provide the maintainers with enough
detail to reproduce or a link to an app exhibiting unexpected behavior. For
help, please get in touch!
