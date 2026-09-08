# RunwayLeft

macOS menu bar app (SwiftUI `MenuBarExtra`, macOS 13+) showing Claude Code and OpenAI Codex quotas, token usage, and provider status. Features and data sources are in `README.md`; this file holds what the code does not say.

## Commands

```bash
swift test                                   # no network, ~10s
SNAPSHOT_DIR=/tmp/snaps swift test --filter ViewRenderTests   # also writes PNGs of every tab
README_SHOTS_DIR=assets swift test --filter ViewRenderTests/testReadmeScreenshots   # regenerates README images from sample data
./build_app.sh                               # ad-hoc signed bundle at build/RunwayLeft.app
```

Install loop used in this repo: quit the running copy, `ditto` the bundle over `/Applications/RunwayLeft.app`, `open` it, confirm with `pgrep -f "RunwayLeft.app/Contents/MacOS/RunwayLeft"`.

Screen capture is not available to agents here. The offscreen render test is the visual check: run it with `SNAPSHOT_DIR` set and Read the PNGs.

## Layout

- `Models/` are plain values plus pure aggregators (`ModelUsageAggregator`, `CombinedDailyPoint`). Pure functions take `now:` and `calendar:` so tests use fixed dates.
- `Services/` read local files and CLIs (`ClaudeDataReader`, `CodexDataReader`), poll status pages (`VendorStatusService`), compose the menu bar (`MenuBarComposer`, `BrandAssets`), and hold all state (`UsageManager`, the single `ObservableObject`).
- `Views/` are SwiftUI. `MainPopoverView` owns the one `ScrollView` and injects `manager`; tab views are content-only. `DesignSystem.swift` holds tokens, cards, the type scale, and the resize grip.

## Conventions

- **Type scale.** Every font goes through `.appFont(role, weight:, design:)`; `.monospacedDigit()` marks numbers. The `textScale` environment and `TextSize.popoverWidth` scale together, so labels wrap instead of shrinking.
- **Color means one thing.** Brand colors (`claudePrimary`, `codexPrimary`) mark card borders and provider pills only. `StatusLevel.color` marks health only. Links use `MacTheme.accentBlue`. An orange link once read as an Anthropic outage.
- **Wording.** User-facing text says *provider*. Type names (`VendorStatus`) stay as they are.
- **Settings persistence.** In `UsageManager.init`, assign `_prop = Published(initialValue:)`. Assigning the wrapped property runs `didSet`, which writes defaults and starts a status fetch mid-init. Add new keys to `Keys.persisted` so the legacy migration carries them. `UsageManager` reads settings through the `SettingsStore` protocol; tests pass `InMemorySettingsStore`, never `UserDefaults(suiteName:)`, because cfprefsd leaves an empty plist per suite in `~/Library/Preferences` even after `removePersistentDomain`.
- **Leave no trace.** Tests and scripts write only under the repo and `FileManager.default.temporaryDirectory`, and remove what they create. Before calling a task done, check for stragglers: `~/Library/Preferences/dev.runwayleft.*` beyond the app's own domain, `~/Library/Application Support/` folders from old app names, `$TMPDIR/<bundle id>` and the matching `~/Library/Caches/claude-cli-nodejs/` entry the Claude CLI creates for it, `/tmp` preview and snapshot directories, and stale `lsregister` entries for bundles that no longer exist.
- **Testable seams.** Logic that decides what to show lives in an enum with no AppKit (`MenuBarComposer.segments`, `VendorStatusService.parse`, `ModelUsageAggregator.entries`). `CodexDataReader.readDatabase(into:)` is the SQLite seam; `CodexDatabaseTests` builds a throwaway `threads` table.
- **Network.** The two Statuspage `summary.json` feeds, and the user's own LiteLLM proxy when configured (`/key/info`, `/user/daily/activity` paged). Both throttled to every five minutes, on their own paths so the local refresh never waits on them, and switchable off in Settings. Tests inject a `VendorStatusService` subclass that answers offline and never construct a `LiteLLMDataReader.Config`, so nothing dials out. Info.plist allows arbitrary loads because a self-hosted proxy is usually plain HTTP.
- **Secrets.** The LiteLLM key lives in a 0600 file under `~/Library/Application Support/RunwayLeft/` via `CredentialStore`, not in defaults. The Keychain would prompt on every rebuild of an ad-hoc signed app.
- **Three sources, one chart.** `combinedDailyPoints` is derived in `recomputeCombinedPoints()` from Claude, Codex, and LiteLLM data; call it from every completion that changes one of them.
- **Refresh cadence.** The timer re-reads local files every interval; the expensive live checks (`claude -p /usage` costs ~2 s CPU, `codex app-server` a process spawn) and the status pages run at most every five minutes and keep their last snapshot. Only `refreshData(force: true)` from the Refresh button bypasses that. Today's Claude tokens come from `TranscriptScanner`, which reads only bytes appended since the previous pass; its cache is touched from the refresh queue alone.
- **Popover height.** `fit` mode sizes to measured content, `custom` to the persisted value; both clamp to the screen. Content height must depend only on width, or the frame feedback loops.
- **Release.** Bump `CFBundleShortVersionString` and `CFBundleVersion` in `build_app.sh`.

## Gotchas

- `build_app.sh` calls `/usr/bin/xattr`; a pyenv shim on PATH lacks `-r`.
- The OpenAI logo PNG is white on transparent. `BrandAssets` marks it `isTemplate` and the menu bar renderer tints it, so it survives light mode.
- The icon is code: `scripts/generate_icon.swift` draws it with CoreGraphics. `swift scripts/generate_icon.swift export dial assets` writes `AppIcon.icns` (bundle icon, copied by `build_app.sh`), `appicon.png` (header and Settings mark), and the 64 px `menubar_glyph.png` / `menubar_glyph_warning.png` that `BrandAssets` sizes to 16 pt. `preview <dir>` renders every variant on dark and light strips for comparison. Edit the script, re-export, rebuild; never hand-edit the PNGs.
- `ViewRenderTests` hosts the popover in an offscreen `NSHostingView` with an opaque backdrop inside the SwiftUI tree; without it, text and translucent fills capture as jagged or opaque.
- The bundle ID changed from `dev.aiusagetracker.app` to `dev.runwayleft.app`; `UsageManager.migrateLegacyDefaultsIfNeeded` copies settings once. A login item registered under the old ID is orphaned. The visible name has changed since (EagleRunway, then back to RunwayLeft) while the ID stayed `dev.runwayleft.app` on purpose: changing it again would reset the menu bar position, settings, and login item.
- `MenuBarExtra` has no right-click hook and its button treats a right click like a left one. `StatusItemMenuController` therefore runs a local event monitor that swallows right- and Control-clicks on the status bar button (found through the event's own window, no private API) and pops an `NSMenu` built from the pure `MenuBarContextMenu.items`. "Open Overview" and "Settings…" open the popover by setting `UsageManager.isPopoverPresented`, which is bound to the scene through the one dependency, [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess). SwiftUI has no public API to open a `.window` `MenuBarExtra`; the library provides it. Its own key-window observers keep the flag in sync when a click opens or closes the popover, so the menu action does a single assignment. The `.menuBarExtraAccess` modifier must sit before `.menuBarExtraStyle`. Do not add anything that writes the flag from window visibility, or that intercepts the status item click to close the popover: both were tried and both desynchronize the library's button state from the real window, after which the flag reads closed while the window is open and clicking stops toggling. A known cost of opening programmatically: AppKit does not treat it as the status item's own presentation, so the first click afterwards dismisses and immediately reopens the popover, and it takes a second click to close. Plain click toggling, the normal path, is unaffected. While the popover is open, AppKit consumes clicks on the button before any local event monitor sees them, so that click cannot be intercepted. Keep `MenuBarExtra`; a hand-rolled `NSStatusItem` would get a new identity and land in the overflow zone again.
- A new bundle ID also makes macOS treat the status item as new and insert it at the far left of the menu bar. On a full menu bar that is the collapsed overflow zone behind the "«" chevron, so the app looks like it never started. Cmd-drag the item to the right once; there is no defaults key to set for it.
- The first refresh after launch (and after midnight) parses every transcript under `~/.claude/projects` modified today, tens of MB on a busy day, so expect one CPU spike then. Later passes read only appended bytes. `RUNWAY_REAL_TRANSCRIPTS=1 swift test --filter TranscriptScannerTests` compares the scanner with the old whole-file parser over the real directory and prints timings.
- Codex reports two rate-limit windows, `primary` (5 hours) and `secondary` (7 days). Route them by duration (`windowDurationMins` live, `window_minutes` in session logs); position is only the fallback when the duration is missing. Real session logs have carried the weekly window alone under `primary` with `secondary: null`. Any window the app-server did not report is filled from the newest session-log line that has it (`fillRateLimitsFromSessionLogs`, live values kept); a logged window whose `resets_at` has passed is dropped rather than shown with a past reset date.
