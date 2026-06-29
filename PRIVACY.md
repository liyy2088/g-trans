# Privacy

G-Trans is a local macOS menu bar app. It does not include telemetry, analytics,
or a hosted backend operated by this project.

## What May Leave Your Mac

When you translate text, G-Trans sends the selected or manually entered text to
the OpenAI-compatible chat completions endpoint configured in the app settings.
That endpoint may be a local service such as Ollama, or a remote provider chosen
by the user.

G-Trans also sends the configured model name and request options needed to
complete the translation request.

## Local Data

G-Trans stores app settings on the local Mac using macOS preferences. This
includes the configured API key, base URL, model name, target language, and
request preferences.

G-Trans writes local diagnostic logs to:

```text
~/Library/Application Support/GTrans/Logs/gtrans.log
```

Logs record app events, lengths, statuses, and error categories. They are not
automatically uploaded by G-Trans.

## Translation History

G-Trans does not persist translation history. Closing the translation panel
clears the current translation session context.

## Permissions

G-Trans requests macOS Accessibility permission so it can read selected text and
use a clipboard fallback when direct selection reading is unavailable.

## User Responsibility

Do not translate secrets, credentials, private keys, personal records, or other
sensitive material unless you trust the configured LLM endpoint and its data
handling policy.
