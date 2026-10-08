# README screenshots

These images must come from the current app, not the previously exported promo
assets. The Usage panel switched from rings to provider rows in October 2026;
reusing an older promo export hid that change.

From the repository root, with Xcode, XcodeGen and Python's Pillow installed:

```sh
python3 script/render-readme-assets.py
```

The command checks out the current committed source in a temporary worktree,
injects a screenshot exporter into its test target, and renders the actual
`NotchRootView` with sample data and isolated settings. It crops transparent
margins, rebuilds the banner from the new Shelf image, and records the source
commit and image hashes in `capture.json`. It does not commit or publish.

Review all eight screenshots and the banner before publishing. Check Usage
against `DesvanUsageView`, Agents against `DesvanAgentsView`, and the resting
sides against `DesvanEarItemView`. The sample quotas, enabled sections, Drawer
icons and panel width can differ from someone's personal configuration.

| Asset | Design scenario |
| --- | --- |
| `shelf.png` | `openShelf` |
| `ask.png` | `openAssistant` |
| `usage.png` | `openUsage` |
| `agents.png` | `openAgents` |
| `calendar.png` | `openCalendar` |
| `drawer.png` | `openDrawer` |
| `idle.png` | `idleWithEars` |
| `idle-agents.png` | `idleWithAgentWaiting` |

To format a set that was just rendered from the same commit without rebuilding:

```sh
python3 script/render-readme-assets.py --format-only /path/to/raw-scenarios
```
