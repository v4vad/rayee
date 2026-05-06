# Rayee UI Redesign Spec
_Date: 2026-05-06_

## Scope

Full visual redesign of the Rayee macOS recording panel (all states) and structural cleanup of the Settings window. Figma file: `bNiHS2i14QOseHRvYBZqQC` (page: "Recording Panel").

---

## Design Direction

Modern, dark, floating panel. Quality reference: Raycast / Superwhisper — not a clone, but the same tier of polish. No emoji anywhere. SF Symbols for all icons. SF Pro typography throughout.

---

## Design Tokens

| Token | Value | Usage |
|---|---|---|
| `panelBg` | `#1C1C1E` | Panel background |
| `headerBg` | `#242426` | Header band (slightly raised) |
| `separator` | `#FFFFFF` @ 8% | Horizontal dividers |
| `topHighlight` | `#FFFFFF` @ 6% | 1px top edge glass effect |
| `textPrimary` | `#FFFFFF` | Wordmark, body text, labels |
| `textSecondary` | `#FFFFFF` @ 45% | Hints, timestamps, secondary labels |
| `textTertiary` | `#FFFFFF` @ 25–35% | Shortcut badges, ghost buttons |
| `accentGreen` | `#30D158` | Ready state, success dot |
| `accentRed` | `#FF453A` | Recording state, stop button |
| `accentBlue` | `#0A84FF` | Transcribing progress, Done button |
| `surfaceLow` | `#FFFFFF` @ 7% | Button resting fill |
| `surfaceMid` | `#FFFFFF` @ 14% | Button active / pressed fill |

---

## Typography

Font: **SF Pro** (system font, all weights).

| Role | Size | Weight | Opacity |
|---|---|---|---|
| Wordmark (RAYEE) | 13px | Semibold | 100% |
| Body text | 14px | Regular | 82% |
| Status label | 13px | Regular | accentGreen / accentRed |
| Hint / timestamp | 12px | Regular | 45% |
| Format option label | 13px | Regular | 82% |
| Shortcut badge | 10px | Medium | 35% |
| Button label | 14px | Medium | 100% |

---

## Panel Structure (shared across all states)

Every panel frame shares this vertical stack:

```
_TopHighlight   1px   white 6%       — glass edge
Header          52px  #242426        — identity + right-side context
Divider         1px   white 8%
Content zone    variable             — state-specific
Divider         1px   white 8%
Footer / Actions 29–46px            — state-specific
```

Corner radius: 12px. Border: 0.75px white 9% (inside).

---

## States

### Idle — 400 × 100px

**Header:** Status dot (hidden) · RAYEE wordmark · "Option + Space to record" hint (right-aligned, 45% white)

**Footer:** "Ready" label in `accentGreen` (left) · Gear icon `gearshape` SF Symbol (right, opens Settings)

---

### Recording — 400 × 164px

**Header:** RAYEE wordmark · Timer e.g. "0:07" (right-aligned, 45% white)

**Content (80px):** 27-bar waveform visualization. Bars are 2.5px wide × variable height, white 90%, 2px corner radius. Heights follow a bell-curve envelope (4px → 44px → 4px), creating a symmetric active-speech shape. A large soft ellipse behind the bars (white 3.5% opacity, ~220×40px) simulates OLED glow bloom.

**Footer (29px):** "Recording" label in `accentRed` (left) · Stop button `stop.fill` SF Symbol (right, red)

---

### Transcribing — 400 × 108px

**Header:** RAYEE wordmark (no right element — server is busy)

**Content (54px):** "Transcribing..." label (white 82%) left-aligned · Animated progress bar right-aligned (84×3px, `accentBlue` fill over white 8% track, 1.5px corner radius)

No footer divider or actions.

---

### Result — 400 × 193px (collapsed)

**Header:** Green status dot (7px) · RAYEE wordmark · Timestamp "just now" (right, 45%)

**Content (92px):** Transcribed text body, 14px Regular, white 82%, 16px left/right padding, 16px top padding. Multi-line wraps naturally.

**Actions (46px):**
- `Button / Done` — blue filled pill (70×30px, 15px radius), "Done" Medium white
- `Button / Copy` — gray pill (70×30px, 15px radius), "Copy" Medium white 82%
- `Button / Format` — square icon button (30×30px, 7% fill), `wand.and.stars` SF Symbol (14px, white 70%)
- `Button / Discard` — ghost text "Discard" (white 35%), right-aligned

---

### Result — 400 × 366px (expanded — Format open)

Same header + content as collapsed. Format button shows active fill (14% white).

**Format Options zone (172px):** 5 rows × 32px each with 6px top padding.

Each row:
- Left group: SF Symbol icon (14×14px, white 50%) + label (13px Regular white 82%)
- Right: keyboard shortcut badge (pill, white 7% fill, 10px Medium white 35%)

| Row | SF Symbol | Label | Shortcut |
|---|---|---|---|
| Grammar | `checkmark.circle` | Grammar | ⌘1 |
| Bullets | `list.bullet` | Bullets | ⌘2 |
| Rephrase | `arrow.triangle.2.circlepath` | Rephrase | ⌘3 |
| Formal | `briefcase` | Formal | ⌘4 |
| Casual | `bubble.left` | Casual | ⌘5 |

Actions strip (identical to collapsed) follows below a divider.

---

## Settings Window

No Figma design needed — this is a structural/code fix only.

### Issues fixed

| Issue | Fix |
|---|---|
| Models tab refreshes on every appear | Switch `@StateObject` → `@ObservedObject` on `WhisperKitModelManager.shared`; guard refresh with `if models.isEmpty` inside `.task` (runs once per view lifetime, not on every `.onAppear`) |
| Duplicate hotkey monitor | `NSEvent.addLocalMonitorForEvents` was registered in both `SettingsView` and `HotkeyPickerView` — removed from `SettingsView` |
| NavigationSplitView sidebar layout | Replace with standard macOS `TabView { }.tabViewStyle(.automatic)` inside a `Settings { }` scene — gives the native toolbar-tab appearance (System Settings style) |
| Vocabulary tab inlined as computed property | Extracted to `VocabularySettingsTab.swift` (standalone view, `@ObservedObject var settings = SettingsManager.shared`) |
| `openWindow(id:)` called for settings | Replace with `@Environment(\.openSettings) private var openSettings` + `openSettings()` in both `SimpleMenuView` and `RecordingPanelController` |

### Tab order

General · Models · Transforms · Vocabulary · History · Uploads

---

## SF Symbols Reference

All icons use SF Symbols. Sizes in the panel use 14×14px containers at weight Regular unless noted.

| Location | Symbol name |
|---|---|
| Idle footer — settings | `gearshape` |
| Recording footer — stop | `stop.fill` |
| Result — format button | `wand.and.stars` |
| Format option — Grammar | `checkmark.circle` |
| Format option — Bullets | `list.bullet` |
| Format option — Rephrase | `arrow.triangle.2.circlepath` |
| Format option — Formal | `briefcase` |
| Format option — Casual | `bubble.left` |

**Figma workflow:** Layer names are annotated with `[SF Symbol]`. Use the [SF(FINDER) plugin](https://www.figma.com/community/plugin/1558579528488226560) to swap placeholder circles for the real glyphs.

---

## Depth & Polish Details

Three techniques applied to avoid a flat look on the dark panel:

1. **Top edge highlight** — 1px `_TopHighlight` layer at white 6% across the full width. Simulates glass catching light from above.
2. **Header lift** — header band is `#242426` vs body `#1C1C1E`. Two-step depth without a visible border.
3. **Waveform glow** — large soft ellipse (white 3.5%, ~blur) sits behind waveform bars. Simulates OLED bloom around active audio activity.

---

## Out of Scope

- Transformation preview view (`TransformationPreviewView`) — not redesigned in this pass
- Setup / onboarding flow — not yet designed
- Menu bar `SimpleMenuView` — structural fix only (openSettings), no visual redesign
- Animations and transition timing — to be specified in a follow-up
