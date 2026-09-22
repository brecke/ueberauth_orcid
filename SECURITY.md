# Security policy

## Reporting a vulnerability

Please [report vulnerabilities privately through GitHub](https://github.com/brecke/ueberauth_orcid/security/advisories/new). If private reporting is unavailable, email the maintainer at [me@miguellaginha.com](mailto:me@miguellaginha.com).

Include affected package/dependency versions, impact, and a minimal reproduction using synthetic data. Do not post client secrets, real tokens, private ORCID records, or undisclosed vulnerability details in public issues or pull requests.

## Supported versions

Security reports are assessed against the latest published release. Fixes target a new release; older-version backports and response times are not guaranteed.

## Dependency monitoring

The checked-in CI configuration audits locked dependencies for Hex security
advisories and retired releases on pull requests, pushes to `master`, and weekly.
Dependabot configuration proposes monthly Mix and GitHub Actions version updates
for maintainer review, without auto-merge. As of 2026-09-18 these configurations
are not on the default branch; hosted monitoring is not yet active or verified.
Until activation, maintainers must run the documented audit manually each week
and review failure notifications after activation. Mix security-update pull
requests are not supported by GitHub; scheduled Hex auditing is the intended
advisory-monitoring path. Applications must audit their own resolutions too.
