# Contributing to TESS

Thanks for helping make TESS better! Bug reports, ideas and pull requests are all welcome.

## Building

```bash
./build.sh --dev --install  # build and launch "TESS Dev" for testing (recommended)
./build.sh --dev            # just build build.noindex/TESS Dev.app
./build.sh --install        # build and install the release flavour as TESS.app
```

### TESS Dev

`--dev` builds **TESS Dev**, a separate app you can run next to the TESS you download from GitHub:

| | TESS | TESS Dev |
|---|---|---|
| App | `/Applications/TESS.app` | `/Applications/TESS Dev.app` |
| Bundle ID (settings, permissions) | `app.tess.assistant` | `app.tess.assistant.dev` |
| Data folder | `~/Library/Application Support/TESS` | `~/Library/Application Support/TESS Dev` |
| Keychain item | `app.tess.assistant` | `app.tess.assistant.dev` |
| Wake word | "Hey Tess" | "Hey Dev" |
| Morning briefing on unlock | on | off |
| Updates | from GitHub | rebuild it |

TESS Dev starts with empty settings and data and needs its own API keys and permissions once. It's signed with your local "TESS Local Signing" certificate, so its permissions survive rebuilds. `build.sh --dev --install` only ever quits, resets or replaces TESS Dev. The names live in `AppFlavor.swift`; the release values there must never change.

Only the Xcode Command Line Tools are required. Every pull request is also built on GitHub Actions.

## Tests

```bash
swift test
```

Tests live in `Tests/TESSTests` and use XCTest, which ships with full Xcode (not the Command Line Tools), so they may not run on a Mac with only the Command Line Tools. GitHub Actions runs them on every pull request, and a pull request can only be merged when they pass.

Test logic, not macOS: keep decisions in small pure functions (see `ConfirmationGate`, `Agent.repaired`, `AnthropicProvider.parse`) and use a fake `LLMProvider` instead of real API calls.

Anything that sends something on the user's behalf must go through a `DraftBox`, so it can only be sent after a clear yes.

## Code conventions

- **No SwiftUI property-wrapper macros** (`@State`, `@Observable`, `@Entry`, `#Preview`). On recent SDKs these need a compiler plugin that ships only with full Xcode, and TESS must build with the Command Line Tools alone. Keep view state in `UIState.shared` (see `UI/MenuBarView.swift`) or another `ObservableObject`.
- Swift 5 language mode, macOS 14 deployment target.
- Everything TESS says is read aloud — keep spoken strings short and free of markdown.
- Match the existing look in `UI/Theme.swift` (cards, rows, option tiles) for any new settings.

## Adding a skill

1. Create a `Tool` in a file under `Sources/TESS/Tools/`:

   ```swift
   static let flipCoin = Tool(
       name: "flip_coin",
       description: "Flip a coin when the user can't decide."
   ) { _ in
       Bool.random() ? "Heads." : "Tails."
   }
   ```

   Use `Tool.rich` when the tool returns an image (for the AI to look at) or long text.
2. Register it in `ToolRegistry.standard`.
3. Add a friendly status line in `ToolRegistry.statusText(for:)` and a display name in the Usage page's `friendlyName`.
4. If it needs a new macOS permission, add the usage string to `Resources/Info.plist`, the entitlement to `Resources/TESS.entitlements` if relevant, and a row to `Permissions.swift` / the Permissions page.
5. Anything with side effects others can see (sending, posting, deleting) must get the user's spoken confirmation first — see how `draft_message` / `send_message` enforce this.

## Reporting bugs

Use the **Bug report** template. Include what you said, what TESS replied, your AI provider and model, and your macOS version. Please strip API keys and personal details from screenshots.
