# KobeTools fork of Spaceman

Upstream: https://github.com/ruittenb/Spaceman (branch `main`). Built from source with no auto-update. Re-check every row after each upstream sync.

## Fork changes

| Change | Where |
|---|---|
| Sparkle is never started | Spaceman/View/StatusBar.swift (`startingUpdater: false`) |
| "Check for updates" menu item and About-tab button hidden | Spaceman/View/StatusBar.swift, Spaceman/View/PreferencesView.swift (`onCheckForUpdates: nil`) |
| Upstream update feed and signing key removed | Spaceman/Info.plist (no `SUFeedURL` / `SUPublicEDKey`) |
| "Fullscreen space names" setting (App name / Short / None); auto names aren't saved | Spaceman/Helpers/SpaceObserver.swift (`FullscreenNaming`), Spaceman/View/PreferencesView.swift |
| Icon text per display kind: the built-in screen and external monitors can each override the general style (Appearance → "Built-in display" / "External displays"; keys `iconTextBuiltIn`, `iconTextExternal`, -1 = same as the general setting) | Spaceman/Model/IconText.swift (`resolve`), Spaceman/Helpers/DisplayGeometryUtilities.swift (`isBuiltIn`), Spaceman/Helpers/IconCreator.swift (per-display widths), Spaceman/View/PreferencesView.swift, tests in EnumBehaviorTests |
| Source build script | scripts/build-install-local.sh |
| Space names survive macOS reshuffling spaces (2026-10-15): the "---" placeholder is never treated as a name (it used to win position matches and make the merge drop the real name, so named desktops went blank); a stored name goes to one space per update (no name on two desktops); a space with a new ID in normal use takes the orphaned name at its slot; names are re-read from disk on every update (a `defaults import` while running is no longer overwritten); every change is kept in ~/.spaceman/space-names/ (last 50) | Spaceman/Model/SpaceNameInfo.swift (`placeholderName`, `hasUserData`), Spaceman/Helpers/SpaceObserver.swift (`findEntryByPosition`, `resolveSpaceNameEntry`, claimed keys, merge), Spaceman/Utilities/SpaceNameStore.swift (`SpaceNameHistory`), tests in SpaceNameResolutionTests and SpaceObserverIntegrationTests |

## Notes

- Upstream ships `CLAUDE.md` and `.claude/skills/`; read them on every sync. Its "never build the app locally" rule is upstream's own workflow; here the app is built with scripts/build-install-local.sh.
- After an upstream sync, re-check the name-persistence row above against upstream's SpaceObserver changes: its CLAUDE.md "ManagedSpaceID Problem" section describes the matching this fork builds on.

## Syncing

Sync to upstream **release tags**, not the tip of `main`. From mactools run `scripts/audit-upstream.sh spaceman`, merge only after review, then check every row above.
