---
title: Luau Shell
description: Customize the workspace bar, its popouts and edge drawers with small Luau widgets.
sidebar:
  order: 8
---

:::note[Unreleased]
The Luau shell is available when building from `main`.
:::

The [workspace bar](/features/workspace-bar/), the [Hidden Bar](/features/hidden-bar/) drawer and System Stats are drawn by Luau widgets. OmniWM supplies the data — workspaces, windows, audio, media, calendar, weather, system stats — and each widget decides how it looks. Settings keeps driving the bar; widgets only change what is drawn.

## The shell folder

```
~/.config/omniwm/shell/
├── shell.toml          # chooses the profile, holds your settings for each one
├── omniwm.d.luau       # type definitions for your editor
├── widgets/            # your widgets, used before any profile's
├── default/            # managed by OmniWM
├── wayline/            # bundled styles, also managed by OmniWM
├── nocturne/
├── system/
├── celestial/
├── matrix/
├── sakura/
└── <profile>/          # your own profiles
```

`default/` holds the bundled widgets and themes, and OmniWM updates it with each release. If you edit a file there, the next update keeps your copy beside it as `<file>.edited-<date>`. To change a widget, use **Settings > Workspace Bar > Customize Widget** or `omniwmctl shell eject <widget>`: that opens its copy in the selected profile, copying an inherited widget there first. Its shared libraries stay with that profile. Bundled profile edits are backed up when an update replaces them; widgets in your own profiles are left alone.

A profile is any other folder in the shell folder. Choose it with `profile = "<name>"` in `shell.toml`, the **Profile** picker in Settings, or `omniwmctl shell profile <name>`. The **Theme** picker and `omniwmctl shell theme <name>` recolour whichever profile is active, and that profile keeps the choice. Anything a profile does not contain comes from `default/`.

The bundled styles are profiles that restyle the whole bar and its popouts, on the same data and commands as the default widgets. **wayline** has a 40 pt bar with coloured icon blocks, **nocturne** has 40 pt capsules and panels that hang from the bar, and **celestial** follows Caelestia: a 60 pt bar with shaped workspaces and a status pill, and a dashboard that drops from the top centre on hover with Dashboard, Media, Performance and Weather tabs. Celestial starts on the left; all styles support top, bottom, left and right placement, and their bar contents scale with the thickness setting. OmniWM updates them like `default/`. A folder you made under one of these names is left alone, and the style is not installed.

**matrix** is Rain Terminal: a dark green, monospace style with a continuous falling-code shader behind the full-width bar, compact numbered workspaces and matching square popouts. Select **matrix** in the profile picker or run `omniwmctl shell profile matrix`. Its palette stays dark in both system appearances. Widgets retain their ordinary controls, including media transport, volume, calendar, weather and system details.

**sakura** is Sakura Glass: warm ivory, rose accents, rounded cards and gently falling cherry-blossom petals. The shader stays inside the bar and matching popouts, leaving the desktop and app windows clear. Select **sakura** in the profile picker or run `omniwmctl shell profile sakura`. Its palette stays light in both system appearances, and its widgets keep the usual media, audio, calendar, weather and system controls.

**system** uses macOS system colours, SF typography and native glass popouts across all bundled widgets. Its 32 pt full-width top bar groups compact workspace buttons on the left, the active window in the centre, and status controls on the right. Control Center opens to an overview, with detailed audio, media, calendar, weather and system views. Choose **system** in the Profile picker or run `omniwmctl shell profile system`. The profile uses the `native` theme, follows light/dark appearance and the system accent, and supports all four bar edges. To show app icons inside its workspace buttons, run `omniwmctl shell set widgets.workspaces.compact false`.

System also includes **Focus Ribbon**. Turn on **Settings > Workspace Bar > Dynamic Island > Enable Island** to show its compact black island at the top of each display. Navigating Niri windows or switching workspaces expands the same island into a ribbon of that workspace’s window icons, in column order. Short ribbons stay centred; longer ribbons follow the focused window within the list’s edges. Each window has its own icon, including multiple windows from one app, with the focused window’s title beneath the ribbon or its app name when no title is available. The ribbon stays open while the pointer is inside and otherwise collapses 2.6 seconds after the last navigation or pointer exit; click the compact island to reopen it, click an icon to focus that window, or click outside to collapse. It does not take keyboard focus. The island hides in native fullscreen and works when the workspace bar is disabled.

## shell.toml

```toml
profile = "default"
profiles.default.theme = "nocturne"          # a bundled theme or themes/<name>.toml
profiles.default.leading = ["omniwm", "workspaces", "scratchpads"]
profiles.default.center = ["clock"]
profiles.default.trailing = ["volume", "system-stats"]

[weather]
city = "Toronto"                   # or latitude = 43.65, longitude = -79.38
units = "celsius"                  # or "fahrenheit"
refresh = 15                       # minutes, at least 5

[profiles.default.widgets.volume]
step = 5                           # any keys: the widget reads them as ctx.data.settings
interval = 2                       # seconds between timed updates for this widget

[profiles.default.drawer.controls]
edge = "right"                     # left, right, top or bottom
widgets = ["volume", "media", "calendar"]
hover = true                       # open when the pointer reaches the edge

[profiles.default.workspaceBar]
height = 40                        # also editable in Workspace Bar settings

[profiles.default.hiddenBar]
enabled = true                     # also rehideIntervalSeconds
```

Everything except `profile` and `[weather]` belongs to one profile, under `profiles.<name>`, so changing one profile never changes another. A profile folder's own `shell.toml` takes the same keys without the prefix, and your `profiles.<name>` settings win over it. The Settings controls and **Bar Widgets** edit the active profile. Both dotted keys and TOML tables are supported. Display-specific choices are saved in `profiles.<name>.monitorBarOverrides`; they override that profile’s general bar settings. Resetting a control restores the profile default without changing another profile.

`leading`, `center` and `trailing` are the bar's three groups, in order; widgets in a split bar's active island come from `leading` and `center`. With **Full Width** on, the bar spans the screen edge and the groups sit at its start, center and end; **Notch Mode** then picks where `center` goes on a notched display. An enabled full-width bar holds macOS menu-bar auto-hide on at every edge. Turning off the last full-width bar restores the previous macOS setting. At the top, the bar also stays above the native menu bar. The themed presets reserve their occupied space for tiled windows; **Reserve Space for Workspace Bar** controls this, and an automatically hidden workspace bar does not reserve space. **Settings > Workspace Bar > Bar Widgets** edits them for the active profile: drag widgets to reorder them, use + to add one to any group, and − or right-click to remove or move one. Right-click a widget on the bar to move it, take it off the bar or open these settings; when the widget uses right-click itself, Option + right-click opens the same menu. Your own widgets in `widgets/` are listed there to add.

**Bar Widgets** also offers `launcher`, `active-window`, `input-source`, `wifi`, `bluetooth`, `battery-details`, `world-clock`, `privacy` and `control-center`. With **Transparent Background** and **Show Item Backgrounds** both on, the default widgets draw their own capsules and palette popouts. Some read settings from `[widgets.<name>]`:

| Widget | Settings |
|---|---|
| `workspaces` | `indicator`: `"pills"`, `"underline"`, `"dots"`, `"numbers"` or `"minimal"` |
| `stats` | `variant`: `"meters"`, `"gauge"` or `"graph"` |
| `world-clock` | `zones`: a list of `{ label = "Tokyo", zone = "Asia/Tokyo" }`; `bar`: how many to show on the bar |
| `launcher` | `mode`: a command palette mode such as `"windows"`; `symbol`: an SF Symbol |
| `active-window` | `display`: `"icon_and_text"`, `"icon_only"` or `"text_only"`; `maxWidth` |
| `battery-details` | `percent`: `"beside"`, `"inside"` or `"none"` |
| `control-center` | `tab`: the tab it opens on |

`hiddenBarWidget` and `systemStatsWidget` name the widgets that draw the Hidden Bar drawer and the System Stats popout. The profile supplies defaults; GUI changes are saved as that profile’s overrides. Workspace Bar’s master enable switch, excluded apps and icon overrides stay global. **Custom Accent Color** and **Custom Text Color** work with every palette; resetting a color restores the palette’s value. Enabling **System Stats Button** also places the configured stats widget on the bar if it was removed.

Hidden Bar app menus use the `hidden-bar-menu` widget, which opens beneath the clicked icon while the icon strip stays visible. Its `ctx.data.hiddenBar.menu` contains the current menu's `title`, optional `backID`, and `rows` with `id`, `title`, `enabled`, `mark`, `shortcut`, `submenu`, and `separator`. The widget sends `hidden-bar-menu <id>` to enter a submenu, go back, or execute a command. IDs are valid only for the displayed page. OmniWM temporarily exposes the selected native status item while acquiring and using its menu, then conceals it again when the menu ends. Like other widgets, its appearance can be customized in the selected profile’s `widgets/hidden-bar-menu/init.luau`.

OmniWM bundles the themes catppuccin, celestial, dracula, everforest, gruvbox, kanagawa, matrix, monolith, nocturne, nord, rose-pine, sakura, tokyo-night and wayline, each with light and dark colours. A theme in `themes/<name>.toml` sets palette roles under `[light]` and `[dark]` (for example `accent = "#FF9500"`) and may set the bar's look under its own `[workspaceBar]`. `theme = "wallpaper"` makes the palette from the main display's wallpaper, Material 3 style, and `scheme` picks how: `tonalSpot` (the default), `content`, `vibrant`, `expressive`, `fidelity`, `fruitSalad`, `rainbow`, `neutral` or `monochrome`; Settings and `omniwmctl shell theme wallpaper <scheme>` set both. OmniWM writes it to `themes/wallpaper.toml` and makes it again when the wallpaper, the Space or the displays change. Besides the base roles, the palette has Material 3 style `highestSurface`, `accentContainer`, `secondaryAccent`, `secondaryContainer`, `tertiaryAccent` and `tertiaryContainer`, each container with a `…Foreground` for text on it; a theme that leaves them out gets readable ones made from its own accent and surfaces. `shell.toml`'s `[workspaceBar]` wins over the theme's. There, `barFill = "surface"` paints the bar with a palette role instead of its Settings background, and `barBorder = "border"` adds a 1 pt edge to that fill; add `/0.8` to a role for 80% opacity.

`omniwmctl query shell-widgets` shows each widget's state and error, and lists mistakes in `shell.toml` and theme files, such as unknown keys and wrong values.

## Persistent island

In **Settings > Workspace Bar > Dynamic Island**, choose **Use Lake Profile** if the selected profile has no island, then turn on **Enable Island**. Selecting Lake changes the shell profile for both the bar layout and island; it does not change either enable switch. **Customize Island Widgets…** opens the loaded island’s widget picker and layout controls. The island is disabled by default and can run with or without the Workspace Bar. The native settings file stores this as `[island] enabled = true`; placement belongs to the selected shell profile:

```toml
# In a profile folder's shell.toml:
[island]
root = "my-island"
displays = "notch"
width = 760
height = 300
fullscreen = "hide"
```

In the user shell file, use `[profiles.<profile>.island]` instead. An absent island table places no island. `root` defaults to `lake`; that widget must exist in a configured widgets folder. `displays` accepts `notch`, `main`, or `all`. `fullscreen` accepts `hide` (default) or `show`. Width and height are the fixed panel envelope in points, from 1 to 8192, clamped to each display. Change the Luau tree's size to expand or collapse its contents; the window does not resize with those transitions.

The root's `render(ctx)` receives `ctx.data.island`. It is `nil` in ordinary bar instances. It contains `display`, `size = {w, h}`, optional `notch = {x, w, h}`, `menuBar`, `scale`, `main`, `visible`, `fullscreen`, and `focused`. Coordinates start at the envelope's top left. `focused` reflects the island’s native keyboard focus lease. A focusable element can acquire it by clicking, and blur, a declared Escape key or an outside press releases it. A root can also appear in a bar lane, using a separate `ctx.state` for each placement and display.

`island.navigation` describes that display’s active workspace: `workspace` is its stable name, `name` its display label, `layout` is `niri` or `dwindle`, and optional `focused` is the selected managed window’s opaque ID. `windows` contains one entry per window with `id`, `bundle`, `name`, `title`, and `column` (one-based Niri column, or zero outside the Niri tree). Entries follow Niri column and row order, with floating windows after tiled windows. Titles use existing cached metadata and may be empty; use the app name as a fallback. Pass an ID to `omniwm.run("window focus " .. id)` to focus it. This data follows workspace and managed-selection changes without polling or per-frame Luau updates.

The island survives opening a popout or drawer and disabling the Workspace Bar. A hidden fullscreen island keeps its Luau instance and state, suspends rendering, and resumes with current data when shown. Its view-only data demand is suspended too. Component composition, timers and durable state are available through the public APIs below. Optional providers and configurable native motion are available below. Native text entry, file resources and desktop services are available through the public APIs below.

Transparent-window click-through still requires the live P1 validation on the target macOS system. OmniWM's own mouse handling uses cached visible/actionable rectangles, preserving gaps between capsules; these rectangles conservatively cover rounded corners and path holes.

## Writing a widget

A widget is a folder with an `init.luau`. `omniwmctl shell init <name>` creates a starter one:

```lua
interval = 60

function render(ctx)
    return ui.row{ gap = 6, onClick = ui.popout,
        ui.symbol{ name = "clock" },
        ui.text{ text = ctx.data.clock } }
end

function popout(ctx)
    return ui.text{ text = ctx.data.date, pad = 12 }
end
```

- `render(ctx)` draws the bar slot or configured island root; return `ui.box{ w = 0, h = 0 }` to draw nothing there.
- `popout(ctx)` draws the popout, opened by `onClick = ui.popout`, `shell toggle <widget>`, or a drawer.
- `interval` (seconds) sets how often timed data such as `seconds`, `cpu` and `network` updates this widget.
- `trigger(ctx, event)` runs for `omniwmctl shell trigger <widget> <name> [value]` and the host lifecycle events described below.
- `require("./helpers")` and `require("@self/helpers")` load other files of the widget. `require("../lib/panel")` loads `lib/panel.luau` shared by every widget, from the shell folder, else the profile, else `default/`.
- `ctx.state` keeps values between renders; `ctx.format` formats numbers, percentages and byte sizes for the user's locale. `ctx.format.date(seconds, template, zone)` formats a time from a date template such as `"jmm"` or `"EEEdMMM"`, following the user's 12- or 24-hour clock, and `ctx.format.offset(seconds, zone)` gives that zone's offset from UTC in seconds; `zone` is an identifier such as `"Asia/Tokyo"`, the local zone when omitted, and an unknown zone gives `nil`.
- `onClick`, `onRightClick` and `onScroll` take a command string or a function `(ctx, event)`; `event` has the button, modifier keys, scroll `dx` and `dy`, and a slider's `value`.
- `omniwm.run(command)` runs an [action](#actions), and `omniwm.log(...)` writes to the macOS log under the `shell` category.
- `spanIslands = true` shows the widget on both islands of a bar split around the notch, instead of only its group's island.

A widget only receives the data it reads, and OmniWM only gathers what some widget reads.

Use `ctx.select("media", "title")` when a view needs one field of an object. The view updates when that field changes, so playback-position updates can leave a title-only widget alone. Paths can contain strings and integer array indices, for example `ctx.select("bluetooth", "devices", 1, "battery")`; a missing path returns `nil`. Bar and popout dependencies are tracked separately. Reading the same object through `ctx.data.media`, or selecting a table rather than a scalar, subscribes to the whole object. Event handlers still receive current data and rerender after changing widget state.

### Data

| `ctx.data` | Contents |
|---|---|
| `clock`, `date`, `seconds` | Localized time and date, and the current time in seconds |
| `island` | Persistent island geometry and display state; `nil` for a bar instance |
| `bar`, `workspaces`, `workspace`, `app`, `title` | The bar's workspaces, windows, scratchpads and style; the focused app |
| `cpu`, `memory`, `gpu`, `disk`, `network`, `system` | System statistics and host details, including uptime |
| `networkHistory` | The last 30 seconds of download and upload speed, and the totals since the Mac started |
| `thermal` | CPU and GPU temperatures in °C |
| `battery`, `charging` | Battery level |
| `power` | Power source, minutes until empty or full, Low Power Mode, and battery health, cycles, temperature and watts |
| `inputSource` | The keyboard input source and the enabled ones, each with a short label |
| `privacy` | Whether any app is using a microphone or a camera |
| `wifi` | Wi-Fi power, signal, band, channel and security, and the network name once Location access is allowed |
| `bluetooth` | Bluetooth power and paired devices with their battery levels, once Bluetooth access is allowed |
| `volume`, `muted`, `outputs` | Output volume and the audio outputs |
| `audioApps` | Apps with audio and their own volume |
| `media` | What is playing, with artwork, shuffle and repeat |
| `lyrics` | Synced lyrics for what is playing, from [LRCLIB](https://lrclib.net); the title, artist and album are sent there only while a widget reads `lyrics` |
| `spectrum` | 60 bars of what the Mac is playing, from 50 Hz to 10 kHz, and its tempo, about four times a second; needs System Audio Recording, like per-app volume |
| `tempo` | Just the `spectrum` tempo in beats per minute, which changes far less often than the bars |
| `calendar` | Upcoming events and a month to draw |
| `reminders` | Access state, incomplete reminders, total count and read/action errors |
| `badges` | Dock badge labels keyed by lowercase bundle ID for apps with managed windows; available to bars, islands and popouts |
| `weather` | Current conditions with humidity, sunrise and sunset, 24 hours and 7 days |
| `user` | Your name and account picture |
| `appearance` | `"light"` or `"dark"` |
| `hiddenBar` | Hidden Bar items |
| `vars`, `settings` | Values from `omniwmctl shell set` and from `[widgets.<name>]` |

`omniwm.d.luau` in the shell folder lists every field with its type.

### Reminders data

`ctx.data.reminders` is a cached snapshot with `access`, `items`, `total`, `truncated` and optional `error`. Access is `"notDetermined"`, `"restricted"`, `"denied"`, `"writeOnly"` or `"full"`, independently of Calendar access. Reading this data does not request permission.

With full access, `items` contains at most 100 incomplete reminders. Each `Reminder` has `id`, `title`, `list`, `color`, optional `due` (Unix seconds), `allDay`, `priority` and `canComplete`. Items are ordered by due date, then priority and identifier; undated items come last, and priority `0` means unset. `total` counts all fetched incomplete reminders; `truncated` is true when the snapshot contains fewer. Custom views can display any of the supplied items.

Use `reminders authorize` to request access, `reminders settings` to open Reminders privacy settings, and `reminders complete <id>` to complete a selected item. Completion checks current access and whether its list is writable. These are commands, not callback-based service requests: read `ctx.data.reminders.error` for read or action failures. A successful authorization or completion clears the previous action error; a background refresh does not conceal it. Cached data updates on changes without a reminder polling timer.

### Native text fields

Give `ui.input` a stable `key` and explicit width and height in a bar, island, popout or drawer:

```luau
ui.input{
    key = "query", text = ctx.state.query or "", placeholder = "Search",
    w = 240, h = 28, maxLength = 256,
    onCommit = function(ctx, event) ctx.state.query = event.text end,
    onCancel = function(ctx) ctx.state.editing = false end,
}
```

AppKit owns selection, composition, clipboard and undo. While focused, the native editor keeps its text across renders. Once unfocused, it adopts the next declared `text`. `focus = true` requests focus when it changes to true; it does not repeatedly steal focus. `focus = false` releases it. `onFocus` receives `event.focused`.

Return commits a single-line field. With `multiline = true`, Return inserts a newline and Command + Return commits. Escape sends `onCancel` unless an IME is composing; it does not itself rewrite the value. Tab and Shift + Tab move among visible inputs. `maxLength` counts grapheme clusters, accepts 0–65,536 and defaults to 65,536. Composition can temporarily exceed the limit until committed.

`onChange` is optional. Pending changes for the same field are coalesced; commit, cancel and focus events keep their order. Omit `onChange` when only the final text matters, so typing needs no Luau callback. A shell focus session transfers between surfaces while retaining its previous-window return target.

Place editors in settled, untransformed regions. Their frames follow delivered layout and rectangular scroll clips. Arbitrary ancestor path masks, rotation, scale and animated layer geometry are not mirrored onto AppKit editors each frame. Surrounding shell content keeps its usual animations.

### Elements

`ui.row`, `ui.column`, `ui.stack` and `ui.box` lay out their children; `ui.text`, `ui.symbol` (SF Symbols), `ui.icon` (app or window icons), `ui.image`, `ui.progress`, `ui.slider`, `ui.path` and `ui.shader` draw. Common properties include `w`, `h`, `gap`, `pad`, `fill`, `material`, `radius`, `hover`, `help` (a tooltip), `onClick`, `onRightClick` and `onScroll`; `omniwm.d.luau` lists them all. A popout whose root has `material = "glass"` uses Liquid Glass, and `material = "clear"` draws the popout with no panel behind it. `ui.text` takes `font = "sans"` (Google Sans Flex), `"rubik"` or `"symbols"`, all bundled with OmniWM. With `"symbols"` the text is a [Material Symbols](https://fonts.google.com/icons) icon name, such as `ui.text{ font = "symbols", text = "dashboard", filled = true }`. A `ui.image` with a `radius` is clipped to its rounded corners. `ui.image{ image = "assets/cat.gif" }` shows an image file from the widget's folder or the shell or style folder; animated GIF, PNG, WebP and HEIC images play on their own, `playing = false` holds the current frame and `speed` scales the playback, for example with `ctx.data.spectrum.bpm`. A `ui.shader` without `w` or `h` fills the `ui.stack` it is in, without changing the stack's size. `bridge = true` on a popout's root stretches the popout up to the bar item that opened it, so a shader can join the two; clicks there still reach the bar, and in a `clear` popout only drawn or clickable elements catch the pointer. `attach = true` on a popout's root places it flush against the bar instead of a small gap away, for panels that hang from the bar. Clicks follow shapes: they pass through a shader's transparent pixels, land on a `ui.path` only inside its outline, and reach a masked stack only inside its mask.

### Shaders

`ui.shader{ source = "glow.metal", values = { 1, 0.5 }, fps = 30 }` draws a Metal fragment shader from the widget's folder or a `shaders/` folder. The file defines one function:

```metal
float4 shade(float2 uv, constant OmniShader& shader) {
    float edge = smoothstep(0.0, 0.2, uv.y) * shader.progress;
    return float4(shader.colors[omni_accent].rgb, edge);
}
```

`uv` runs from 0 to 1 across the shader, top left first. `shader` holds:

- `size` (points), `scale`, `time` (seconds, while `fps` is above 0), `values` (up to four numbers) and `colors` (the theme's roles, such as `omni_accent`);
- `progress`, which runs from 0 to 1 as a popout opens and back to 0 as it closes;
- `anchor`, the middle of the bar item that opened the popout, and `content`, the popout's content as x, y, width and height, both in points from the shader's top left;
- `audio`, with `audio = true` on the shader: the 60 `spectrum` bars from 0 to 1, updated 30 times a second without re-rendering the widget. Such a shader draws at 30 fps unless `fps` says otherwise.

With `fps` at 0, animations off or Low Power Mode, a shader draws once, with `progress` at its end value.

A profile can also draw a shader behind the entire workspace bar, underneath all three widget lanes:

```toml
[barShader]
source = "matrix-rain.metal"
fps = 30
values = [0.38, 1, 12, 1]
```

Put this table in the profile's `shell.toml`; in the user shell file, use `[profiles.matrix.barShader]`. The source is a `.metal` filename resolved through `shell/shaders/`, the selected profile's `shaders/`, then `default/shaders/`. `fps` accepts integers from 0 to 60, and `values` accepts up to four finite numbers. `enabled = false` disables the profile's bar shader. Matrix's four values are intensity, speed, character size in points, and bar glow (0–1). Sakura's are petal opacity, speed, petal size in points, and time offset; its popouts set these in `sakura/lib/style.luau`. The background follows bar opacity and yields to transparent or solid-black bar settings. It never intercepts clicks, and it pauses while hidden, locked or displays are asleep. Oversized bars keep their full logical bounds while lowering shader resolution to fit the existing 4096-pixel limit; widget text remains at display resolution. Failed shaders leave the ordinary bar fill visible and report their error in the shell log.

`open` and `close` on a popout's root set how many seconds `progress` takes to run from 0 to 1 and back, for example `ui.stack{ open = 0.8, close = 0.4, ... }`. They are exact: they ignore the animation speed setting, still play with animations off, and keep the shader drawing while they run whatever its `fps`. Drawers use the `open` and `close` of each widget they show; without them a drawer's shaders follow its slide.

Any element in a popout or drawer can take `enter`, the state it starts from as the popout opens: `opacity`, `scale` (around its centre), `dx` and `dy` (points), plus `from` and `to`, the part of the opening it moves in (0 to 1, by default all of it), and `curve`. Closing plays it backwards. Give rows different `from` values to bring them in one after another:

```lua
ui.text{ text = "Hello", enter = { opacity = 0, dy = -8, from = 0.5, to = 0.9, curve = "back" } }
```

A `curve` is `linear`, `easeIn`, `easeOut`, `easeInOut`, `back` (overshoots), one of Material 3's `standard`, `standardAccel`, `standardDecel`, `emphasized`, `emphasizedAccel` and `emphasizedDecel`, one of the expressive `fastSpatial`, `spatial`, `slowSpatial` (these overshoot), `fastEffects`, `effects` and `slowEffects`, or your own cubic Bézier as 4 numbers, or 6 numbers per segment ending each at `x, y`. `animate` takes the same names, with their Material durations (`spatial` is 0.5 s), or `{ duration = 0.3, curve = ... }`. When the root of a popout or drawer has `animate`, the panel morphs to its new size instead of jumping, for example between dashboard tabs. `enter = { dy = -400, curve = "spatial", stretch = 0.1 }` also squashes the element along its slide while it moves fast and springs it back, as Caelestia's panels do; `stretch` is how strongly (Caelestia uses 0.03 to 0.25). `rotate` turns an element by degrees around its centre; a text turned by 90 also takes the turned space in its row or column, for vertical titles on side bars. `loop = { rotate = { 0, 360, 20 }, dx = { -10, 10, 6 }, dy = ..., paused = not playing }` repeats each motion from `from` to `to` every `seconds`, without re-rendering the widget. `trail = true` on an element with `animate` moves its leading edge on time and its trailing edge 1.5 times slower, so a moving indicator stretches and catches up.

`mask = true` turns a shader into the shape of the stack it sits in. The shader is not drawn; everything else in that stack (its material, fill, border and children) shows only where the shader's alpha is. That gives blurred material in any shape. Use one mask per stack, and for a shaped popout put the shaped material in a stack inside a `clear` root, because the popout's own panel background stays a rounded rectangle:

```lua
function popout(ctx)
    return ui.stack{ material = "clear", open = 0.6,
        ui.stack{ material = "regular",
            ui.shader{ source = "blob.metal", mask = true, fps = 60 },
            ui.column{ pad = 24, ui.text{ text = "Shaped glass" } } } }
end
```

Until a mask shader draws its first frame its stack stays hidden; if it fails to compile, the stack shows unmasked.

### Editable effects library

Add **Effects Lab** from **Bar Widgets** to try the bundled motion, light and mask presets. The gallery is opt-in and works with every profile. Its **Glass / Frosted** button changes the panel material; the light and mask previews also use a blurred material behind their content. **Hide / Show** plays element transitions, **Move** retargets the trailing indicator, **Freeze / Animate** selects a static or animated shader, and the mask slider scrubs the reveal. Stretch also plays when the panel opens. Freeze draws the shader at time zero; it does not hold its last animated frame.

The editable files are installed under `~/.config/omniwm/shell/default/`:

- `lib/effects.luau` contains the recipes and defaults.
- `shaders/effects-*.metal` contains the visual effects and reveal masks.
- `widgets/effects-lab/init.luau` is the complete gallery example.

From a widget's `init.luau`, load the library with `require("../lib/effects")`. User `shell/lib/` and `shell/shaders/` files override the selected profile, which overrides `default/`. Use `omniwmctl shell eject lib/effects.luau` to create a persistent library override. To customize a shader, copy it into `shell/shaders/` with the same filename. To customize the gallery, use `omniwmctl shell eject effects-lab`.

`effects.motion(name, props)` returns element properties. Preset tables are copied, caller properties win, and your supplied properties are not modified. Nested properties such as `animate`, `appear` and `exit` replace the preset's corresponding table as a whole.

| Motion | Behavior |
| --- | --- |
| `fade` | Short ease-out opacity transition |
| `slide` | Spring movement and fade on insertion/removal |
| `pop` | Scale from half size, settle with a small bounce, shrink on removal |
| `spring` | Softer, more pronounced spring |
| `stretch` | Spatial entrance with native stretch; insertion/removal slides |
| `indicator` | Spring retargeting with a trailing edge |

```lua
local effects = require("../lib/effects")

function render(ctx)
    return ui.box(effects.motion("pop", {
        key = "status", pad = 8, radius = 10, fill = "surface",
        pressScale = 0.95,
        ui.text{ text = "Ready" },
    }))
end
```

Keep the same key when moving or resizing an element. `appear` and `exit` run when an element is inserted or removed; changing its key requests a new identity. Ordinary motion runs in Core Animation, without a Luau update for every frame.

`effects.shader(name, props)` and `effects.mask(name, props)` return `ui.shader` elements. Properties such as `w`, `h`, `key`, `fps` and `values` override their defaults. Omit size to fill the parent stack. Supply all four `values` when overriding them:

| Helper / name | Four values, in order | Default fps |
| --- | --- | --- |
| `shader("aurora")` | strength `0.7`, speed `1`, unused `0`, unused `0` | 30 |
| `shader("sheen")` | strength `0.3`, pattern frequency `1`, unused `0`, unused `0` | 0 |
| `shader("glow")` | corner radius `16`, inward reach `18`, strength `0.65`, falloff power `2` | 0 |
| `shader("ring")` | corner radius `16`, stroke width `2`, angle in degrees `45`, opacity `1` | 0 |
| `shader("rotating-border")` | corner radius `16`, stroke width `3`, degrees per second `90`, opacity `1` | 30 |
| `shader("pixelate")` | maximum block size `48`, unused `0`, unused `0`, progress `-1` | 0 |
| `shader("genie")` | horizontal anchor `0.5`, top anchor `0` (bottom; `1` for top), unused `0`, progress `-1` | 0 |
| `mask("burn")` | noise size `26`, feather `0.015`, edge overlay `0`, progress `-1` | 0 |
| `mask("smoke")` | cloud size `60`, softness `0.14`, haze overlay `0`, progress `-1` | 0 |
| `mask("circle")` | origin x `0.5`, origin y `0.5`, feather `1`, progress `-1` | 0 |
| `mask("wipe")` | direction x `1`, direction y `0`, feather `1`, progress `-1` | 0 |
| `mask("dissolve")` | cell size `8`, softness `1`, seed `0`, progress `-1` | 0 |

Lengths are in points, circle origins are fractions of the element size, and strength/opacity/softness range from 0 to 1. A wipe direction of `0, 1` reveals downward; `-1, 0` reveals from the right. Reveal presets use `shader.progress` when the fourth value is `-1`, an explicit 0–1 reveal otherwise, or `-2` with `fps = 30` for a three-second repeating preview. Dissolve is deterministic for the same size, seed and progress. All masks fully hide at 0 and fully reveal at 1.

The **Light** tab includes a rotating gradient border. **Masks** includes burn and smoke; their paired `effects.shader("burn")` / `effects.shader("smoke")` presets use the same parameters with the third value set to `1` to draw the ember edge or haze over the masked content. The **Texture** tab demonstrates actual image pixelation and genie deformation. **Play preview** animates on the native shader clock; moving the progress slider returns to manual scrubbing.

The **Blur** tab adjusts the existing native backdrop with `blurRadius = 0…64` points and `saturation = 0…3`; omitted values retain the material's radius and saturation `1.8`. Zero radius removes blur, and saturation `1` is neutral. Use `fill` for tint and opacity. These properties apply to layer materials such as `regular`; they do not change root `glass` or `popover` system materials. The Lab uses a clear panel and an image behind the controlled material so you can compare the full range.

```lua
ui.stack{ material = "regular", blurRadius = 28, saturation = 1.2,
    fill = "surface/0.15", radius = 16, w = 320, h = 180,
    ui.text{ text = "Adjustable native blur" },
}
```

A texture shader accepts `texture = omniwm.asset("@self/card.png")` or a contained image path using the same lookup as `ui.image`. It samples the first image frame, stretched into the shader bounds. The image uploads once when its decoded identity changes; normal shader frames only sample that texture. Missing images render transparently. This operates on the supplied image, not a live subtree or another application's window. Keep live blur/glass on the surrounding stack.

```lua
local effects = require("../lib/effects")
local card = omniwm.asset("@self/card.png")

function popout(ctx)
    return ui.stack{ w = 360, h = 180, material = "glass", open = 0.65, close = 0.35,
        effects.shader("genie", { texture = card }),
    }
end
```

Custom texture shaders declare `#define OMNI_TEXTURE` and use `float4 shade(float2 uv, constant OmniShader& shader, texture2d<float> image)`. `omni_sample(image, uv)` returns straight RGBA with safe premultiplied filtering; return that color directly. Coordinates outside 0–1 are transparent; edge texels stay opaque when enlarged. Existing two-argument shaders keep their usual signature. `omni_progress(shader)` implements the reveal convention above, and `omni_noise(point)` provides smooth deterministic value noise. The editable sample texture is `widgets/effects-lab/sample.png`.

This example combines a circular reveal, blurred material, aurora and real text. Explicit root `open`/`close` timing drives the mask while its `fps = 0` leaves it idle after the transition. As with other explicit shader timing, it still plays with ordinary animations disabled.

```lua
local effects = require("../lib/effects")

function render(ctx)
    return ui.box{ popout = true, pad = 6, ui.text{ text = "Reveal" } }
end

function popout(ctx)
    return ui.stack{ material = "clear", open = 0.55, close = 0.25,
        ui.stack{ w = 320, h = 180, radius = 16, material = "regular", center = true,
            effects.mask("circle"),
            effects.shader("aurora"),
            ui.text{ text = "A softer arrival", size = 20, weight = "semibold" },
        },
    }
end
```

For native Liquid Glass, set the popout root to `material = "glass"` and add a ring or sheen:

```lua
local effects = require("../lib/effects")

function render(ctx)
    return ui.box{ popout = true, pad = 6, ui.text{ text = "Glass" } }
end

function popout(ctx)
    return ui.stack{ w = 320, h = 180, radius = 16, material = "glass", center = true,
        effects.shader("ring", { values = { 16, 2, 45, 0.8 } }),
        ui.text{ text = "Glass with a little color", size = 18 },
    }
end
```

The library draws procedural color and alpha. Aurora and sheen are decorative adaptations; they do not refract the desktop. Masks shape their parent, including its material and children, but do not distort the children's pixels. The native Liquid Glass panel remains rectangular with rounded corners; use a `clear` root and a masked inner material for shaped panels. Existing shader visibility, Low Power Mode and GPU-budget controls apply. No screen capture, extra animation loop or provider is needed.

### Paths

`ui.path` draws a vector shape from SVG path data, without writing a shader: `d` takes the commands `M L H V C S Q T A Z` (lowercase for relative), `fill`, `border` and `borderWidth` colour it, and `evenOdd = true` switches the fill rule. With `viewBox = { x, y, width, height }` the path is stretched to the element's size, so `viewBox = { 0, 0, 24, 24 }` with `w` and `h` draws a 24-point icon at any size; without `w` and `h` it takes the viewBox size, or fills the `ui.stack` it is in. A path with `mask = true` shapes its stack like a mask shader. When `d` changes and the path has `animate`, it morphs to the new shape, and `enter = { d = "..." }` morphs from that shape as the popout opens; both shapes need the same commands for a smooth morph.

```lua
ui.stack{ material = "thin", w = 120, h = 120,
    ui.path{ viewBox = { 0, 0, 24, 24 }, mask = true,
        d = "M12 2 L15 9 L22 9 L16.5 13.5 L18.5 21 L12 16.5 L5.5 21 L7.5 13.5 L2 9 L9 9 Z",
        enter = { d = "M12 12 L12 12 L12 12 L12 12 L12 12 L12 12 L12 12 L12 12 L12 12 L12 12 Z" } } }
```

OmniWM ships `liquid.metal`, which grows a drop from the bar item into the popout:

```lua
function popout(ctx)
    return ui.stack{ material = "clear", bridge = true,
        ui.shader{ source = "liquid.metal", fps = 60 },
        ui.column{ pad = 16, gap = 4,
            ui.text{ text = ctx.data.clock, style = "bold" },
            ui.text{ text = ctx.data.date },
        },
    }
end
```

### Native input and intent

Press feedback is native: add `pressScale`, `pressOpacity`, `pressFill` and `pressAnimate` to an element. It starts on mouse-down and restores on release or cancellation, without calling Luau. `pressAnimate` uses the same presets, duration or custom curve as `animate`. A transparent `pressFill = 0` explicitly overrides the base fill. Add `onPress(ctx, event)` only when behavior needs the `down`, `up` and `cancel` boundaries.

`onHover(ctx, event)` receives `began` after `hoverDelay` seconds and `ended` after `hoverGrace` seconds. Leaving before dwell cancels entry; returning during grace cancels exit. Both delays default to zero and accept 0–60 seconds. Pointer movement does not call Luau.

```lua
function render(ctx)
    return ui.box{
        w = 240, h = if ctx.state.peek then 80 else 32,
        fill = "#000000", radius = 16, animate = "spring",
        hoverDelay = 0.16, hoverGrace = 0.12,
        onHover = function(next, event) next.state.peek = event.phase == "began" end,
        pressScale = 0.97, pressOpacity = 0.85, pressAnimate = "ease",
        onClick = function(next) next.state.expanded = not next.state.expanded end,
        ui.text{ text = "My island", color = "#ffffff" },
    }
end
```

The five new handlers—`onPress`, `onHover`, `onGesture`, `onKey` and `onOutsidePress`—accept callback functions only. Existing `onClick`, `onRightClick` and `onScroll` retain their command-string form. Pointer events expose element-local `x` and `y` in points, with the origin at the top left; press events also include `button` and `clicks`.

#### Captured gestures

A `gesture` declaration opts into native pointer or trackpad recognition:

```lua
gesture = {
    axis = "y", source = "both", threshold = 6,
    lockDistance = 2, dominance = 1.3,
    commit = { distance = 40, velocity = 300, direction = "up" },
},
onGesture = function(ctx, event)
    if event.phase == "ended" and event.committed then ctx.state.expanded = false end
end,
```

Axes are `x`, `y`, `free` and `auto` (default); sources are `pointer` (default), `scroll` and `both`. Recognition defaults to a 4-point threshold, 1-point axis-lock distance and a 1.25 dominance ratio. The innermost element accepting the locked axis claims the gesture, cancels its click, and keeps capture outside its bounds until the gesture ends or is cancelled. Existing sliders and window-item dragging retain their native ownership.

Events use `began`, `ended` and `cancelled`. Set `gestureEvents = "all"` to also receive coalesced `changed` events; `dx/dy` are cumulative translation in points and `vx/vy` are velocity in points per second. By default, continuous changes stay native. `committed` is true at the end when an enabled distance **or** velocity threshold passes in the declared direction. Zero disables a criterion, and no enabled criteria means no commit. Directions are `any` (default), `left`, `right`, `up` and `down`.

`onScroll` preserves physical scroll phase and `event.momentum` (`none`, `began`, `changed` or `ended`). `scrollMomentum = "consume"` is the default; use `"deliver"` to receive momentum. Phase-less wheel events are delivered through `onScroll`; they do not synthesize an end using an idle timer. Gesture-driven visual tracking is separate from these logical gesture events.

#### Declared keyboard input and outside presses

An expanded island can use `focusable = true`, `keys = {"left", "right", "escape"}` and `onKey(ctx, event)`. Declared keys are consumed synchronously by the focused native element; Luau receives `key`, optional `characters`, `event["repeat"]` and the existing modifier flags. Key names are lowercase; declarations normalize ASCII case and remove duplicates. There are at most 64 names, each 1–32 bytes. Standard names include `escape`, `return`, `left`, `right`, `up`, `down`, `space` and `tab`. Undeclared keys retain the existing native fallback. Set `focusRing = false` on a focusable presentation container to hide its native focus outline while keeping keyboard handling and focus ownership. Rings stay enabled by default; a child control that takes focus keeps its own ring.

`onOutsidePress(ctx, event)` works on elements in an island tree. Declare it on the visible capsule or expanded container rather than the fixed panel envelope. The handler receives the mouse button and local coordinates of an outside press; the original click continues to its destination. Native monitoring exists only while a visible island needs outside handling or owns keyboard focus. Escape releases the island’s keyboard focus when declared.

Root widgets with `trigger(ctx, event)` receive `{name = "reloaded", source = "host"}` when a display instance is first created, and `{name = "displayChanged", source = "host"}` when its display identity or geometry changes. Visibility and focus remain data facts; they do not trigger this hook. The bundled profile preserves its presentation state while hidden. User-triggered events retain their existing name/value form without `source`. Component `init`, `options` and `deinit` remain package-level hooks.

A custom island root can keep the native **Customize Island Widgets…** entry point by implementing `trigger(ctx, event)` and opening its own controls when `ctx.data.island` is present and `event.name == "settings"`. Ignore unrelated trigger names. The native button becomes available after the root loads and declares a trigger handler; the profile owns what its settings controls contain. Keep integrations in component service modules so replacing those controls or the island layout does not replace their data and actions.

### Actions

`onClick`, `onRightClick` and `omniwm.run` take any `omniwmctl command` (for example `"switch-workspace 2"`) and these shell commands:

| Command | Effect |
|---|---|
| `volume up [percent]`, `volume down [percent]`, `volume set <0-100>`, `volume mute` | Output volume |
| `volume output <id>` | Switch the output |
| `volume app <bundle> set <0-100>`, `volume app <bundle> mute`, `volume app <bundle> reset` | One app's volume |
| `volume permission` | Open the System Audio Recording privacy settings |
| `media play`, `media pause`, `media toggle`, `media next`, `media previous`, `media seek <seconds>`, `media shuffle`, `media repeat`, `media open` | Playback; shuffle turns shuffle on or off and repeat steps through off, one and all, as `media.shuffle` and `media.repeatMode` show; when no widget reads `media`, play, pause and track changes send the media keys |
| `session lock`, `session sleep`, `session logout`, `session restart`, `session shutdown` | Lock the screen, sleep, or ask macOS to log out, restart or shut down; macOS shows its usual confirmation for the last three, and asks once for permission to control loginwindow |
| `calendar authorize`, `calendar settings`, `calendar open [event]`, `calendar month next\|previous\|today` | Calendar; `settings` opens the Calendars privacy settings |
| `reminders authorize`, `reminders settings`, `reminders complete <id>` | Request Reminders access, open its privacy settings, or complete a selected writable reminder; failures appear in `ctx.data.reminders.error` |
| `battery settings` | Open the Battery settings |
| `input-source select <id>`, `input-source settings` | Switch the keyboard input source; open the Keyboard settings |
| `wifi authorize`, `wifi settings` | Ask for Location access, or open its privacy settings once asked; open the Wi-Fi settings |
| `bluetooth authorize`, `bluetooth settings` | Ask for Bluetooth access, or open its privacy settings once asked; open the Bluetooth settings |
| `shell toggle <name>` | Open or close a drawer or a widget's popout |
| `shell menu` | Open the OmniWM menu at the widget |
| `hidden-bar activate <id>` | Click a Hidden Bar item |
| `window <action> <id>` | Any [`omniwmctl window`](/reference/cli/actions/) action on a window |

## Drawers

A `[drawer.<id>]` stacks the popouts of its widgets in one panel on a screen edge, like a control center. Open it with `shell toggle <id>`, from a click, with **Settings > Hotkeys > Toggle \<id\>**, or by moving the pointer to that edge when `hover = true`. Only one drawer or popout is open at a time. `width = 900` limits the hover to that stretch of the edge's middle, and `reach = 10` lets the pointer open it from up to 10 points away from the edge. `close = "leave"` closes it as soon as the pointer leaves it; opened by a click or hotkey, it stays until the pointer has been inside and left. `chrome = false` drops the panel's own background, padding and slide, so the widget draws the whole panel flush against the edge, beside the bar, with room to overshoot.

## Permissions

| Feature | Permission |
|---|---|
| Per-app volume | System Audio Recording, asked the first time an app is turned down |
| Calendar | Calendar full access, asked from the calendar widget |
| Reminders | Reminders full access, requested only by `reminders authorize`; independent of Calendar access |
| Wi-Fi network name | Location, asked from the Wi-Fi widget; signal, band and security need none |
| Bluetooth | Bluetooth, asked from the Bluetooth widget |
| Audio spectrum | System Audio Recording, like per-app volume |
| Log out, restart and shut down | Automation of loginwindow, asked the first time |
| Wallpaper theme | None; with Screen Recording already allowed, live and dynamic wallpapers are read as shown |

Now Playing needs no permission.

## Composable island profiles

The bundled `lake` profile draws its island in editable Luau. Its bar lanes remain independently configurable: custom bar widgets and an island can run together. The native **Island** switch controls whether the island is present; selecting a profile does not turn it on. The profile uses a short hover dwell to show a preview, a click to expand, native button press feedback, an upward pointer/trackpad gesture to collapse, and outside press or Escape to dismiss. The primary capsule accepts keyboard focus on click in compact, preview and expanded modes. While focused, Left and Right cycle enabled components in configured order; Escape dismisses the expanded content and releases focus. Collapsing with a click or gesture may leave the compact capsule focused until Escape, blur or an outside press.

These choices live in `widgets/lake/init.luau` and `lib/lake/intent.luau`, `policy.luau`, `slots.luau` and `motion.luau`. Replace them independently of `lib/lake/services/` to retain integrations. The profile requests gesture boundaries only; its UI does not run Luau for every pointer move. Native capture and automated tests do not establish perceived motion quality: hover dwell, press feel, trackpad direction and focus restoration still need a live check on the target display.

Configure instances in the selected profile's `shell.toml`, or override the entire list under `[[profiles.lake.island.components]]` in your top-level `shell.toml`:

```toml
[[island.components]]
id = "london"
widget = "world-clock"
zone = "Europe/London"
label = "London"

[[island.components]]
id = "tokyo"
widget = "world-clock"
zone = "Asia/Tokyo"
label = "Tokyo"
```

Each `id` has its own validated options and shared `instance.state`; `ctx.state` is separate for each display and placement. Disabling an instance runs its `deinit` hook. Editing options calls `options(instance, previous)` without restarting the root. Up to 64 configured instances share the root's VM.

Install components in `shell/widgets/<name>/` with two files. `component.toml` describes the component without running code:

```toml
title = "My clock"
icon = "clock"
views = ["compact", "expanded"]

[options.zone]
type = "string"
default = "UTC"
maxLength = 128
```

`component.luau` returns views and optional `init`, `options`, `deinit` and `activity` functions:

```lua
return {
    views = {
        compact = function(ctx)
            return ui.text{ text = ctx.format.date(ctx.data.seconds, "jmm", ctx.instance.options.zone) or "—" }
        end,
        expanded = function(ctx)
            return ui.text{ text = ctx.instance.options.zone, size = 24 }
        end,
    },
    activity = function(ctx)
        return { priority = 1, label = ctx.instance.options.zone }
    end,
}
```

The root uses `ctx.data.components` to discover configured instances, `omniwm.components.activity(id)` to read their activity, and `ui.component{ id = "tokyo", view = "expanded", w = 240, props = { density = "compact" } }` to compose a view. Views can have any name. The root chooses placement, navigation and promotion policy; native code does not assign meanings to those names.

### Customize the lake profile

Expand the island and press the sliders button, or right-click its main capsule. **Components** lets you add installed packages, enable or disable instances, remove them, and edit their declared options. Drag an instance's grip to reorder it; after focusing a row, Up and Down also move it. **Show** opens that instance. Boolean, number, choice, text and string-list options are editable here. Text fields use Command + Return to save and Escape to cancel. Lists preserve empty values and newlines, offer Add/Remove, and show twelve entries per page. A Saving notice remains until the configuration write completes; admission, schema and disk errors stay visible.

Region choices are lake's own policy: **Automatic** participates in the normal main/side selection; **Main** prefers the main capsule; **Side** occupies the smaller capsule; **Expanded only** is available after expansion. A manually selected component can become the main expanded view. These meanings are implemented in `lib/lake/policy.luau`, and can be replaced along with the rest of the profile. Bar widgets remain independently configurable.

**Appearance**, **Interaction** and **Motion** expose expanded width, corner radius, solid background and selected-tab colors, hover preview timing, click/right-click/swipe targets, swipe direction/input/distance and expansion spring parameters. Colors use `#RRGGBB` or `#RRGGBBAA`. Action targets are `toggle`, `expand`, `collapse`, `settings`, `next`, `previous`, `none`, or `component:<enabled instance ID>`; a component target promotes and expands that instance. Unavailable component targets do nothing. The sliders button still opens settings even when the right-click target changes. These are profile controls; each component retains its own declared options and editable views. These change the layer-rendered contents; the persistent island window retains its configured envelope. The fixed envelope clamps a requested content width that cannot fit. Root settings and their validation schema live in `widgets/lake/settings.toml`, while current values are saved in the selected profile's user configuration. The settings view is itself editable Luau in `lib/lake/settings.luau`.

### Catalog and configuration actions

`ctx.data.catalog` is an immutable array of installed component metadata. Each entry has `widget`, `title`, `icon`, `views`, `options`, `source`, `overrides` and an optional `error`. `source` identifies the effective folder; `overrides` lists lower-precedence copies. Broken packages remain visible with a diagnostic and cannot be added. Reading the catalog does not execute component source. Catalog and root-schema snapshots are bounded to 4 MiB each; excessive metadata produces a visible configuration error. Every `ctx.data.components` entry includes its effective `options`, even when that instance is disabled.

Root handlers can use these asynchronous public actions:

```lua
omniwm.components.add("world-clock", { zone = "Asia/Tokyo" }, function(result)
    if not result.ok then omniwm.log(result.error) end
end)
omniwm.components.move("tokyo", 1)
omniwm.components.enable("tokyo", true)
omniwm.components.set("tokyo", "seconds", false)
omniwm.components.remove("tokyo")
omniwm.config.set("hoverPreview", true)
```

`add` assigns a stable new instance ID and returns it as `result.id` on success. Move indexes are one-based final positions. Each call returns a service handle, or `nil, error` if admission fails. The optional callback receives `{ok, id?, revision?, error?}`; persistence failure is reported as an error. Configuration actions share the normal bounded async ledger. The host also bounds queued and pending file writes to 256 operations independently of callback cancellation; excess work receives an overload error before changing configuration. Cancellation retires callback delivery; an accepted change already applied in memory still completes its file write.

All values must satisfy the package's declared option schema. `id`, `widget`, `enabled`, `provider` and capability names are reserved option keys. Configuration actions cannot grant provider access or widen capabilities; enabling an already configured instance preserves its existing grants. Existing grants are preserved when reordering or changing ordinary options. File writes run off the render executor, preserve unrelated current user configuration, and do not reload the root VM. The first component-list write copies the complete effective list into `[profiles.<profile>.island]` because profile arrays replace lower layers.

`omniwm.config.set` writes only the calling root's declared settings. A root exposes its editable schema through `widgets/<root>/settings.toml`:

```toml
[options.hoverPreview]
type = "boolean"
title = "Hover preview"
default = true

[options.width]
type = "number"
title = "Expanded width"
default = 520
min = 380
max = 640
step = 20
```

The option types and validation rules are the same as component options. The host publishes effective values in `ctx.data.settings` and schema metadata in `ctx.data.settingsSchema`; they update together on configuration or source changes. A missing root schema means there are no declared root settings to write. A replacement profile can render these controls however it chooses while retaining the same component integrations and configuration APIs. Native Settings still provides the Island toggle, profile selection and shell folder access if a custom root cannot render.

A component view receives `ctx.view.name`, explicit parent size offers `ctx.view.w/h`, and value-only `ctx.view.props` (acyclic, depth at most 64, encoded size at most 64 KiB). Invalid props and ordinary component errors fail that component boundary.

Views and activities are retained independently. Each runs only when its selected data, owner state or offered size/props change, with its own 8 ms execution budget. An activity result is compared by value before invalidating its readers. A failed view keeps its last accepted output; a failed activity keeps its last accepted value. The package yields between units, and native code assembles their cached trees. Components still share the VM's 32 MiB memory limit and the configuration/load budget.

`ui.component` declares a mount; it does not execute the component inside the root's call. Read updated component error/status metadata on later root updates. Repeated mounts of the same instance and view on one surface must offer equal size and props. Use separate configured instance IDs when they need different inputs or state. Passing a fresh equal props table reuses the view; changing a reused table's values invalidates it.

Unchanged views keep their handlers while other components publish. Each unit retains four changed handler revisions, and removal or reload invalidates that unit's old handlers. Hidden islands retain their views without rendering; activity dependencies continue updating in the background. Static packages receive no feed wakeup for data they do not use.

Option schemas support `boolean`, `number` (`min`, `max`, `step`), `string` (`maxLength`), `choice` (`choices`) and `strings`. Identity, provider and capability fields are reserved. Native provider execution is not enabled merely by installing a component.

### Editable Lake components

The `lake` profile includes media, calendar, weather, battery, devices, microphone/camera indicators, Dock badges, reminders, world clocks, timers, quick notes, a file shelf, image conversion and CI status. Add and configure them in the island's settings. Custom bar widgets can run alongside any island layout.

The root widget owns navigation, regions, hover, expansion and alerts. Override `widgets/lake/init.luau` and `lib/lake/attention.luau`, `policy.luau`, `motion.luau` or `slots.luau` to change those behaviors. The stock profile offers solid and translucent appearances, deduplicates stable alert IDs per component and temporarily selects a matching file component during a drag. An alert scheduling error appears in settings.

Integrations live in `lib/lake/services/`. Keep a component's lifecycle and service calls when replacing its views, or extend its stock definition as described below. Custom views can combine those integrations with their own data, actions, providers, shaders and animations.

- Media offers compact, peek and expanded views. Scrubbing sends a seek on release.
- Timers persist an absolute deadline. Each configured instance has its own timer and saved state. A visible running countdown reads the seconds feed; completion and save failures expose Retry. Timers cannot fire while OmniWM is stopped.
- Calendar alerts use the configured lead time. Battery and device alerts follow data changes.
- Reminders asks for access only through an explicit action. Its data includes up to 100 incomplete reminders, the total count and read/action errors. The stock view shows the first four and lets the user complete writable reminders.
- Badges shows raw Dock badge labels for apps with managed windows, even when the Workspace Bar is disabled. It supplies no notification contents or reply API.
- Quick note uses native multiline text input, explicit save and clipboard copy. Each configured instance has its own saved note.
- Shelf and converter views reuse the file services described below. Conversion also requires a hand-edited `provider = true` on the configured instance; adding the component in settings does not grant permission to run its provider.
- CI status requires a repository in its options. Its polling and request failures are handled by the component's service module.

Unavailable data and denied permissions have explicit UI states. Notification replies, call control and camera capture are outside these integrations; microphone/camera indicators report activity only.

### Replacing views while retaining integrations

`lake` separates integrations in `lib/lake/services/` from component views. A custom component can reuse the media service, or extend the stock definition:

```lua
local lake = require("../lib/lake")
local stock = require("@component/media")

return lake.extend(stock, {
    views = {
        compact = function(ctx)
            return ui.text{ text = ctx.select("media", "title") or "Nothing playing" }
        end,
    },
})
```

Declare `uses = ["media"]` in the custom manifest so the stock definition loads even when no instance directly selects it. Components resolve the root profile's library overrides, including top-level `shell/lib/` files. The source limit is explicit: 64 files for ordinary widgets and 512 for roots, including libraries and components; exceeding it reports a load error.

Editing a component reloads that definition and its declared `uses` dependents, cancels their services, flushes their stores and resets their runtime state. Other component instances and root state remain intact. Editing the root or a shared library replaces the root VM. A root that directly retains a component export through `require("@component/name")` also needs a full reload when that export changes; composing it through `ui.component` allows component-scoped reload.

Use `omniwmctl shell eject <widget>` to copy a managed profile's widget or component into the persistent top-level override folder. `omniwmctl shell eject lib/lake/policy.luau` copies a library override. Bundled profile updates then leave these overrides in place.

### Component images and shaders

Capture package-local assets with `omniwm.asset("@self/icon.png")` or `omniwm.asset("@self/bars.metal")`, then pass the result to `ui.image.image` or `ui.shader.source`. References retain their originating package even when a custom component inherits the stock view. Identical filenames in different packages do not collide, and paths cannot escape the source package. Qualified image decoding and shader preparation run off the main thread; asset changes replace affected bindings. Plain strings retain ordinary widget folder lookup.

### Timers, JSON and durable state

`omniwm.after(seconds, callback)` schedules one callback, with a minimum delay of 0.01 seconds. It returns a handle with `handle:cancel()`, or `nil, error` when the request cannot be accepted. There are at most 32 outstanding async reservations per owner and 256 per root package. A completed request keeps its reservation until delivery; the reservation is released before its callback runs. Disabling or reloading an owner cancels its requests and rejects late completions.

```lua
local handle, err = omniwm.after(1, function()
    omniwm.log("one second later")
end)
if not handle then omniwm.log(err) end
```

`json.encode(value)` and `json.decode(text)` return a result or `nil, error`. They accept finite numbers, strings, booleans, arrays and string-keyed objects, with depth at most 64 and encoded/input size at most 4 MiB. Use `json.null` for a JSON null inside an array or object; decoded empty arrays retain their identity.

### HTTP and an all-Luau CI component

`omniwm.http(request, callback)` starts an asynchronous HTTP(S) request. It returns a cancellable service handle, or `nil, error` when admission fails. At most six HTTP requests are outstanding per package, within the shared 32-per-owner and 256-per-package service limits. A result waiting for delivery still occupies its native reservation. There are no automatic retries.

```lua
local request, err = omniwm.http({
    url = "https://api.github.com/repos/OmniNull/OmniWM/actions/runs?per_page=5",
    headers = { Accept = "application/vnd.github+json" },
    response = "json",
    maxBytes = 262144,
    timeout = 30,
}, function(result)
    if result.ok then
        instance.state.runs = result.json.workflow_runs
    else
        instance.state.error = result.error
    end
end)
if not request then instance.state.error = err end
```

The method defaults to GET, the response to `"text"`, the response limit to 1 MiB and the total deadline to 30 seconds. Choose `"json"` for a parsed immutable value or `"bytes"` for a binary Luau string. Request bodies are binary strings or ready Resources; Resource bodies require the files capability and are prepared off the UI thread. Bodies and response limits are capped at 4 MiB; deadlines must be positive and at most 120 seconds. Request header text and encoded response headers each have a separate 64 KiB bound. The HTTP session has no disk cache, cookies or stored credentials.

Callbacks receive `{ok, status, headers, text?, json?, bytes?, error?}`. Response header names are lowercase. `ok` is true only for a successfully decoded 2xx response. Non-2xx responses use `error="http_status"` and retain a successfully decoded body. Transport and JSON errors have no replacement body. Status is zero if no HTTP status was received. Keep prior valid component data when a request fails. Cancellation, instance removal and package close prevent late callback delivery.

A component declares exact network hosts in its manifest:

```toml
capabilities = { network = ["api.github.com"] }
```

Explicit user configuration may add component hosts. Declarations do not grant wildcard or subdomain access, and each redirect is checked. Root/bar scripts retain unrestricted HTTP(S) access. These rules constrain API use within the shared VM; they are not a process sandbox. Provider and other capability grants cannot be widened by the Luau configuration API.

The installed **CI status** component is optional and is not enabled by default. Add it through lake's component catalog or configure an instance with `widget="ci-status"`, `options.repo="owner/name"` and an integer `options.interval` between 15 and 3600 seconds (default 60). It uses public repository workflows without credentials. It keeps the last five valid runs across restarts, polls with one request or timer at a time and displays **Retry polling** if timer admission fails. A failed HTTP admission waits for the next ordinary poll; Retry resumes only when the user selects it. Replacing the component views leaves its HTTP, polling, storage and activity behavior available to custom layouts.

A newly observed failed workflow offers a stable four-second `activity.alert` marker keyed by run and attempt. The lake profile temporarily selects that alert, then returns according to its editable attention policy. The component also exposes its status in compact and expanded views.

### Optional component providers

A component can use a separate program for integrations that the Luau APIs do not cover. One process belongs to each enabled, explicitly opted-in component instance, regardless of how many displays render it. The process exchanges JSON Lines over stdin/stdout; rendering and animations stay in OmniShell.

Declare the executable and capability in `component.toml`:

```toml
capabilities = { provider = true }

[provider]
command = ["provider.pl"]
```

The first argument must name an executable inside the component folder. Give scripts an executable bit and a valid shebang. Arguments are passed directly, without a shell. In your own `shell.toml`, set `provider = true` on the matching configured instance; a bundled profile or the Luau settings UI cannot grant execution. Disabling the instance stops its process. Providers are native programs with your account's access, not sandboxed Luau; macOS privacy authorization is not guaranteed to transfer from OmniWM.

The program receives `OMNIWM_PROVIDER_PROTOCOL=1`, `OMNIWM_WIDGET`, `OMNIWM_WIDGET_DIR`, `OMNIWM_INSTANCE` and JSON `OMNIWM_PROVIDER_OPTIONS`. Changing options replaces the process after actual exit and pipe cleanup. Shutdown closes stdin, sends SIGTERM and, if it still has not exited after two seconds, sends SIGKILL. A crashed process is not restarted automatically; explicitly disable and re-enable its provider to start it again.

```lua
return {
    receive = function(instance, event)
        if event.name == "completed" then
            instance.state.message = event.value
        end
    end,
    views = {
        compact = function(ctx)
            local provider = ctx.instance.provider
            return ui.text{ text = provider.state.summary or provider.status }
        end,
    },
}
```

`instance.provider` is immutable and contains `status`, `state`, optional `error` and optional `exitCode`. Status is `stopped`, `starting`, `running`, `exited` or `failed`. State is shared across that instance's displays; `receive(instance, event)` runs once per event, with `{kind="event", name, value}`. It has the same instance-owned service and command access as lifecycle callbacks.

Send an ordered action from a component callback:

```lua
local handle, err = omniwm.provider.send("refresh", { source = "manual" }, nil, function(result)
    instance.state.message = result.ok and result.value or result.error
end)
if not handle then instance.state.message = err end
```

The callback is optional. The returned service handle supports `:cancel()`. Admission errors are synchronous; accepted requests keep the existing service reservation until result delivery or cancellation. Roots cannot send provider actions. Results arrive at their position among provider events, after the latest state for that process has been installed. Cancellation suppresses the callback and unsent work; it cannot undo an action already received by a native program.

Protocol frames are JSON arrays, with one newline per frame:

```json
["state", "summary", "Ready"]
["event", "completed", {"count": 3}]
["action", "r42", "refresh", {"source": "manual"}]
["result", "r42", true, {"count": 3}]
["result", "r43", false, "Service unavailable"]
```

Only OmniShell sends `action`; providers send the other frames. Echo the request ID string exactly. Topic/event/action names begin with an ASCII letter and contain at most 64 ASCII letters, digits, underscores, periods or hyphens. A frame is at most 64 KiB including its newline. State keeps only the latest raw value for each of at most 64 topics, with a combined 1 MiB bound; `null` deletes a topic. State consumption is paced before JSON decoding. Invalid topic JSON preserves its prior valid value and reports a provider error.

Events and results remain ordered. The package admits at most 256 queued events; overflow fails that provider while preserving already accepted replies. Results use reserved capacity, so event traffic cannot displace them. Outgoing unwritten actions share a 1 MiB limit and use nonblocking pipes. Stderr is drained with bounded diagnostics. None of these paths waits on the UI thread or advances animations.

The optional **Converter** component is installed but unconfigured. Add it through the catalog, then explicitly enable its provider in your own configuration to convert dropped images. Its provider uses macOS image tools; returned outputs are ordinary Resources.

`omniwm.store.get(key)` reads an immutable snapshot from the current owner's durable store. `omniwm.store.set(key, value)` returns `true` or `nil, error`; passing `nil` deletes the key. The full snapshot is limited to 256 KiB. Stores are separate for each profile, root package and configured instance ID, and load before component `init`. They live outside the configuration folder. `ctx.state` and `instance.state` are not saved automatically.

Writes coalesce on a separate utility queue, at least one second apart during normal operation, and flush on teardown, reload and quit. `omniwm.store.status` exposes `state` (`ready`, `pending` or `failed`), `revision`, `committedRevision` and an optional `error`. A failed commit retains the in-memory snapshot and reports the failure; it does not start an automatic retry loop.

Async callbacks and coroutines retain their component identity. A coroutine whose owner or captured display no longer exists fails safely when resumed. Callbacks can log and issue commands without a display instance; commands without a captured display use the main screen. Incoming completions use one bounded queue and batches of at most 16, with affected trees rendered once after each batch.

### Files and desktop services

A component declares `capabilities = { files = true, clipboard = true }` for these APIs. File and clipboard permission are separate; copying a Resource needs both. User configuration can grant capabilities, but a widget cannot grant them to itself through the configuration API. Root scripts retain their existing unrestricted API policy. Native macOS privacy rules still apply.

Accept drops on an element with a real handler:

```lua
ui.box {
    key = "shelf", w = 400, h = 180,
    accepts = { "file", "url", "text", "image" },
    onDrop = function(ctx, event)
        ctx.instance.state.items = event.items
    end,
    onDropHover = function(ctx, event)
        ctx.state.over = event.phase == "entered"
    end,
}
```

`event.items` contains host-issued Resource userdata. A Resource exposes immutable `id`, `name`, `kind`, `uti`, `state`, optional `size` and `error`. States are `pending`, `ready` and `failed`. Promised files can reach the handler while pending; their state changes invalidate only views that read them. The batch admits at most 32 items atomically. Each owner has at most 512 live Resource handles. A handle belongs to its configured instance and cannot be manufactured from an ID or passed to another owner's services. Removing or reloading the owner releases its live handles.

Use `ui.image{ image = resource, thumbnail = 128, w = 48, h = 48 }` for a thumbnail. `thumbnail` is a pixel request between 1 and 2048, default 128. Thumbnails prepare off the UI thread and use a shared 64 MiB image cache. A failed or pending image does not block the widget's other content.

Declare `dragItems = {resource}` with 1–32 unique ready Resources to drag their contents out. `onDragOut(ctx, event)` receives actual `began` and `ended`, with operation `copy` or `none`. File backing remains retained until the native drag session ends, even when its panel closes. Preparation never starts a drag after the mouse button has been released. A drag declaration cannot share a node with a mask, native input, slider, logical gesture, or window-manager drag/drop/target. Put competing controls on separate or nested nodes.

`ctx.data.island.drag` supplies `{active, types}` for profile policy. Monitoring is enabled only while a visible island tree declares drop acceptance. Your Luau root decides whether to expand and which component to show; OmniWM does not select a shelf or impose a visual mode. A collapsed profile must keep a drop declaration in its tree to request this discovery.

Desktop calls return a cancellable handle or `nil, error`. Optional callbacks receive `{ok, error?}`; picker and clipboard-read callbacks also receive `items`:

```lua
omniwm.pick({files = true, multiple = true}, function(result)
    if result.ok then instance.state.items = result.items end
end)
omniwm.open(resource)
omniwm.reveal(resource)
omniwm.quicklook({resource}, 1)
omniwm.share({resource}, "item-actions")
omniwm.share({resource}, "item-actions", "airdrop")
omniwm.clipboard.copy("A note")
omniwm.clipboard.read(function(result)
    if result.ok then instance.state.items = result.items end
end)
```

Quick Look requires ready file-backed Resources. Sharing also accepts URL and text Resources. The share anchor is the key of a currently published element belonging to the calling component/view; use an inner keyed element rather than the component's replaced root key. It is revalidated after file preparation. Picker, Quick Look and sharing need a live source surface. They use the existing shell focus lease and restore focus only while that restoration remains appropriate. Selecting an external sharing service avoids taking focus back from it. Generic sharing opens a native Share menu, followed by the system picker from the user's selection.

`omniwm.open` also accepts a non-file URL. Arbitrary file-path strings are not Resource authority. Clipboard text arguments are limited to 1 MiB. Copying a Resource materializes up to 16 MiB of text, URL or file/image content by value under its UTI; it does not copy a temporary file URL. Use drag-out or reveal for Finder file workflows. Reading supports file URLs, URLs, text, PNG and TIFF, subject to macOS clipboard access. Empty clipboard reads succeed with an empty list.

Persist Resource references alongside your own state:

```lua
local token, err = omniwm.resources.persist(resource, function(result)
    if not result.ok then instance.state.error = result.error end
end)
if token then
    local saved, saveError = omniwm.store.set("saved-item", token)
    if not saved then instance.state.error = saveError end
else
    instance.state.error = err
end
```

Persistence returns a host token at admission. Check `resource.persistence.state` (`pending`, `durable`, `failed`) or its callback before claiming it is saved. Pending promised Resources may be submitted for persistence; they finish only after the underlying data resolves. `omniwm.resources.restore(token)` returns a pending Resource or `nil, error`; only tokens previously issued to that owner can restore. The host orders resource persistence before the final owner-store flush. Token and store failure remain explicit. There is no arbitrary file operations API, and deleting a shelf row does not delete the original file.

The bundled **Shelf** component keeps up to 32 items, shows four rows per page, and supports drop, paste, file picking, label editing, thumbnails, preview, sharing and drag-out. **Image converter** uses the same shelf for its outputs and offers PNG, JPEG and TIFF conversion after explicit provider opt-in. Their logic lives in `lib/lake/services/shelf.luau` and `lib/lake/services/convert.luau`; their views can be replaced independently. Removing a row removes its saved reference. Live Resources remain owned until the component retires; durable tokens remain subject to the namespace limit.

### Provider file attachments

Send up to 32 Resources through the optional file envelope:

```lua
local request, err = omniwm.provider.send("convert", {format = "png"},
    {files = {resource}}, function(result)
        if result.ok then instance.state.outputs = result.files
        else instance.state.error = result.error end
    end)
```

A file-enabled component still requires explicit user `provider = true`. Inputs wait for readiness on a utility queue; a failed promise returns an error, and cancellation prevents unsent work. Data-only actions keep the four-field envelope. File actions add a fifth object:

```json
["action", "r42", "convert", {"format":"png"}, {"files":[{"name":"Input.jpg","path":"/host-resolved/Input.jpg"}],"outputDirectory":"/host-created/action"}]
["result", "r42", true, {"count":1}, {"files":[{"name":"Output.png","path":"Output.png"}]}]
```

The paths are available only to the explicitly enabled native program. Write outputs under that action's `outputDirectory` and return relative paths. The host validates the entire output list, rejects traversal/symlink escapes and missing files, and imports Resources before delivering the result. Late or cancelled results cannot publish resources to a replacement owner. Input pins and action directories remain until the process has actually finished using them; cancellation suppresses callbacks but cannot undo native side effects. Original input files are never deleted. Persist output Resources if they should survive owner reload or application restart.

### Springs, element transitions and native dragging

Use `animate = { response = 0.31, bounce = 0.22 }` to choose a spring. `response` accepts 0.05–2.5 seconds; `bounce` accepts 0–0.95 and defaults to zero. Do not combine spring fields with `duration` or `curve`. The same form works for `pressAnimate` and element transitions. Interrupted scalar springs carry their velocity into the next target, bounded to a normalized magnitude of 20. Frame springs use independent position and size axes.

`appear` and `exit` describe an element's insertion and removal relative to its normal paint. Opacity and scale multiply the painted values; `dx` and `dy` are point offsets. Omitted fields are identity values. Omitted transition `animate` uses the element's motion, or a short fade when it has none; `animate = "none"` is instant. An exiting subtree keeps its last contents until native completion. Reintroducing its key under the same parent cancels the outgoing copy. These properties are separate from `enter`, which stages popout/drawer opening.

```lua
ui.box {
    key = "activity", w = 220, h = 64,
    animate = { response = 0.31, bounce = 0.22 },
    appear = { opacity = 0, scale = 0.88 },
    exit = { opacity = 0, scale = 0.88, animate = { response = 0.24, bounce = 0 } },
    gesture = {
        axis = "y", source = "both",
        commit = { distance = 50, velocity = 300, direction = "up" },
        track = {
            dy = { 0, -40, rubber = 0.4 },
            scale = { 1, 0.94 },
            opacity = { 1, 0.8 },
        },
    },
    onGesture = function(ctx, event)
        if event.phase == "ended" and event.committed then
            ctx.state.expanded = false
        end
    end,
}
```

Tracking needs a positive `commit.distance`, which defines full progress. `track` supports `dx`, `dy`, `scale` and `opacity`; each range has two endpoints and optional `rubber` from zero to one. Rubber affects overshoot beyond the endpoints. The native renderer applies these offsets without rendering Luau on each pointer sample. `onGesture` is optional: without it, release settles immediately. With it, committed release holds until that handler finishes, then settles alongside its new layout or returns to rest if the handler makes no visual change, fails, or is rejected. There is no timeout-based success path.

Apply tracking and `appear`/`exit` to a visible container around a mask; they are rejected directly on `mask = true` nodes. Reduce Motion keeps direct finger tracking and makes settlement instant. Animation speed applies to spring response and duration curves.

The editable `lake` profile keeps transition recipes in `lib/lake/motion.luau`. Its optional `lib/lake/digits.luau` prototype builds rolling numbers from ordinary clipped digit strips; it does not require a native text-animation API. Keep the default crossfade or replace that library to choose your own rollover behavior.
