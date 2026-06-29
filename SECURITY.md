# Security Policy

## Reporting a Vulnerability

Please do not open a public issue for suspected vulnerabilities, leaked secrets,
or reports that include private user data.

Report security concerns by contacting the maintainer directly through the
GitHub account that owns this repository:

```text
https://github.com/liyy2088
```

If you are unsure whether a report is security-sensitive, treat it as private.

## What To Include

- A short description of the issue.
- Steps to reproduce, if available.
- The affected commit, tag, or release.
- Any relevant logs with secrets and translated content removed.

## Scope

Security-sensitive areas include:

- Handling of configured API keys and local preferences.
- Diagnostic log redaction.
- macOS Accessibility permission behavior.
- Clipboard fallback behavior.
- Network requests to configured LLM endpoints.

## Supported Versions

The project is currently in MVP stage. Security fixes target the default branch
until versioned releases are introduced.
