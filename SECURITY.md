# Security Policy

## Reporting a vulnerability

Please report security issues **privately** through GitHub's private
vulnerability reporting for this repository:

- Go to the repository's **Security** tab → **Report a vulnerability**
  (GitHub Security Advisories).

This routes the report directly to the maintainer ([@moiesk](https://github.com/moiesk))
without disclosing it publicly. Please do not open a public issue for security
problems, and please don't include secrets or credentials in the report.

## Expectations

This is one person's **personal dotfiles**, shared publicly for reference — not
a supported product. It is provided **as-is**, with no warranty and no
guarantee of maintenance or response times (see [LICENSE](LICENSE)).

Adopters use it **at their own risk**: review the configuration and scripts
before applying any of it to your own machine, and adapt anything
environment-specific (paths, identifiers, credentials) to your own setup.

## Secret scanning and hygiene

When this repository is public, GitHub's
[secret scanning](https://docs.github.com/code-security/secret-scanning/about-secret-scanning)
and [private vulnerability reporting](https://docs.github.com/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
are the preferred channels for surfacing exposed credentials or security
concerns. If you spot a leaked secret, report it privately as described above so
it can be rotated.
