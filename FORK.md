# KobeTools fork of Spaceman

Upstream: https://github.com/ruittenb/Spaceman (branch `main`). Built from source with no auto-update. Re-check every row after each upstream sync.

## Fork changes

| Change | Where |
|---|---|
| Sparkle is never started | Spaceman/View/StatusBar.swift (`startingUpdater: false`) |
| "Check for updates" menu item and About-tab button hidden | Spaceman/View/StatusBar.swift, Spaceman/View/PreferencesView.swift (`onCheckForUpdates: nil`) |
| Upstream update feed and signing key removed | Spaceman/Info.plist (no `SUFeedURL` / `SUPublicEDKey`) |
| "Fullscreen space names" setting (App name / Short / None); auto names aren't saved | Spaceman/Helpers/SpaceObserver.swift (`FullscreenNaming`), Spaceman/View/PreferencesView.swift |
| Source build script | scripts/build-install-local.sh |

## Notes

- Upstream ships `CLAUDE.md` and `.claude/skills/`; read them on every sync.

## Syncing

Sync to upstream **release tags**, not the tip of `main`. From mactools run `scripts/audit-upstream.sh spaceman`, merge only after review, then check every row above.
