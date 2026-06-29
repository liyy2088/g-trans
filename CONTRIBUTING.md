# Contributing

Thanks for taking the time to improve G-Trans.

## Development Setup

Requirements:

- macOS 13 Ventura or later.
- Swift toolchain / Command Line Tools.
- An OpenAI-compatible chat completions endpoint for manual app testing.

Run the local checks before opening a pull request:

```bash
./scripts/check.sh
./scripts/build_app.sh
```

The GitHub Actions workflow runs `swift test` and `./scripts/check.sh` on
macOS.

## Pull Requests

- Keep changes scoped to one behavior or fix.
- Add or update tests for core logic changes.
- Include screenshots or short notes for visible UI changes.
- Do not commit API keys, logs, generated app bundles, `.build/`, or local
  diagnostics.

## Local App Testing

For manual testing, build and install the app locally:

```bash
./scripts/build_app.sh
ditto .build/manual/GTrans.app /Applications/GTrans.app
open -a /Applications/GTrans.app
```

The current build script produces an ad-hoc signed app for local validation.
Developer ID signing and notarization are separate release tasks.

## Privacy and Security

Do not paste secrets, credentials, personal records, or private translation
content into public issues or pull requests. See `PRIVACY.md` and `SECURITY.md`
for the project boundaries.
