# Security policy

## Reporting a vulnerability

Please [report vulnerabilities privately through GitHub](https://github.com/brecke/ueberauth_orcid/security/advisories/new). If private reporting is unavailable, email the maintainer at [me@miguellaginha.com](mailto:me@miguellaginha.com).

Include affected package/dependency versions, impact, and a minimal reproduction using synthetic data. Do not post client secrets, real tokens, private ORCID records, or undisclosed vulnerability details in public issues or pull requests.

## Supported versions

Security reports are assessed against the latest published release. Fixes target a new release; older-version backports and response times are not guaranteed.

## Dependency monitoring

CI checks locked dependencies for Hex security advisories and retired releases on pull requests, pushes to `master`, and weekly. Dependabot proposes monthly version updates for Mix and GitHub Actions for maintainer review, without auto-merge. Mix security-update pull requests are not supported by GitHub; the scheduled audit is the advisory-monitoring path. Applications must audit their own dependency resolutions too.
