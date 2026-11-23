# Changelog

All notable changes to `boring-ui` are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Added
- **Keyboard Navigation (`src/events.br`, `src/controls.br`)**:
  - Added `Up` / `Down` / `Home` / `End` item navigation inside the topmost presented `Popover` in `events.br` (`keyPress`).
  - Scoped `Picker`, `Menu`, and `ContextMenu` popovers with `FocusScope(trap = true)` and `DefaultFocus` (selected option for `Picker`, first non-separator item for `Menu` / `ContextMenu`) so `Tab` / `ShiftTab` wraps and `Enter` / `Space` / `Escape` work cleanly.
  - Wrapped `Desktop` open windows in `FocusSection` and marked the topmost open window's close button (`"✕"`) as `ButtonRole.Cancel` so `Escape` closes the active window.
  - Added `tests/keyboard_nav_test.br` verifying `Picker`, `Menu`, `ContextMenu`, and `Desktop` keyboard navigation under both `boring run` and `boring build` (and verified `popover_test.br` + `desktop_test.br` pass).
- **Data Visualization & Hierarchy Components (`src/controls.br`)**:
  - `Skeleton(width = 120.0, height = 16.0, radius = 4.0, circle = false, lines = 1)`: loading placeholder (rectangle, circular avatar, or stacked text lines).
  - `BarChart(values, labels = [], width = 240.0, height = 120.0, barColor = "#3478f6", barSpacing = 6.0)`: vertical bar chart rendered on `Canvas` with optional x-axis labels.
  - `Sparkline(values, width = 100.0, height = 28.0, color = "#3478f6", dotSize = 4.0)`: compact inline trend plot normalized between min and max values.
  - `StatCard(title, value, delta = "", positive = true, subtitle = "")`: KPI summary `Card` with optional delta `Badge`, subtitle, and trailing child slot.
  - `TreeItem` & `TreeView(items, selectedId = "", onSelect, indent = 16.0)`: collapsible hierarchical tree list in depth-first order with `▸`/`▾` expand/collapse toggles and item selection.
  - Added `tests/data_viz_test.br` verifying `Skeleton`, `BarChart`, `Sparkline`, `StatCard`, and `TreeView` under both `boring run` and `boring build`.
- **Layout & Navigation Components (`src/controls.br`)**:
  - Added `Drawer(isOpen, side = "left", width = 280.0, onClose, content)`: slide-in overlay panel with backdrop click-to-close support (`"left"` or `"right"`).
  - Added `Toolbar(title, subtitle = "", leading, trailing)`: compact horizontal header/action bar with leading slot, title/subtitle, and trailing actions.
  - Added `EmptyState(icon = "", title, message = "", actionLabel = "", onAction)`: centered placeholder view with optional icon, title, description, and action button.
  - Added `Wizard(steps, currentStep, onStep, onFinish, content)`: multi-step progress header (`1`, `2`, ...) with Back / Next / Finish navigation controls and content body.
  - Added `tests/layout_nav_test.br` verifying `Drawer`, `Toolbar`, `EmptyState`, and `Wizard` under both `boring run` and `boring build`.
- **Form Input Components (`src/controls.br`)**:
  - `NumberInput(value, min = 0.0, max = 100.0, step = 1.0, onChange)`: numeric `TextField` with `-`/`+` step buttons and range clamping.
  - `ComboBox(options, onSelect, label = "Select", placeholder = "Type to filter…")`: filterable `TextField` paired with a `Popover` dropdown of matching options.
  - `TagInput(tags, onChange, label = "Add tag", placeholder = "New tag…")`: removable `"tag ✕"` chip list with `TextField` + `"Add"` button.
  - `Rating(value, max = 5, onChange, readOnly = false)`: interactive or read-only star rating selector (`★` / `☆`).
  - Added `tests/form_inputs_test.br` (verified under `boring run` and `boring build`).
- **Navigation & Layout Extras (`src/controls.br`)**:
  - `Breadcrumb(items, onSelect, separator = "›")`: clickable breadcrumb trail with bold current item.
  - `Pagination(page, totalPages, onChange)`: 1-based page navigator with `"‹ Prev"`, `"Next ›"`, and direct page buttons (or compact counter when `totalPages > 7`).
  - `ChipGroup(options, selected, onToggle, spacing = 6.0)`: toggleable filter chip row.
  - `SplitPane(width, initialRatio = 0.4, minRatio = 0.15, maxRatio = 0.85)`: interactive two-pane split container with a draggable `"⋮"` divider.
  - Added `tests/nav_extra_test.br` (verified under `boring run` and `boring build`).
- **Notification, Accordion & Data Table Components (`src/controls.br`)**:
  - `Banner(title, message = "", kind = "info", onDismiss = nil)`: inline semantic notification strip (`"info"`, `"success"`, `"warning"`, `"danger"`) with optional dismiss button.
  - `Toast(bind isPresented, message, kind = "info")`: animated bottom overlay notification built on `Layer`, `Shadow`, `Banner`, and `Transition(.Fade)`.
  - `Accordion(titles, allowAllClosed = true)`: mutually exclusive collapsible sections with fade transitions.
  - `Table(headers, rows, selected = -1, onSelect = nil, columnWeights = [])`: multi-column data table with bold headers, separator, proportional column weights, and single-row selection.
  - Added `tests/components_test.br` (verified under `boring run` and `boring build`).
- **Additional Composite Controls (`src/controls.br`) & `todo_window` Demo**:
  - `Badge(text, color, radius)`: compact rounded pill badge.
  - `Card(color, radius, padding)`: elevated surface container with shadow and inner padding.
  - `RadioGroup(selected, options, onSelect, axis = .Vertical)`: mutually exclusive radio option group (`◉` / `○`) in vertical or horizontal layout.
  - `SearchField(bind value, label, placeholder, onSubmit)`: `TextField` with an inline `"✕"` clear button when non-empty.
  - Updated `examples/todo_window/window_app.br` to showcase `TimePicker`, `ColorPicker(editableHex = true)`, `Menu` separators, and hollow `Rectangle` shapes in `Canvas`, with `tests/extra_controls_test.br`.
- **Desktop Multi-Windowing & Menu Separators (`src/controls.br`)**:
  - `Desktop`: in-place window minimize/restore (`"−"`), maximize/restore (`"□"`), interactive width resizing via the right-edge handle (`"⋮"`), and desktop boundary clamping on drag.
  - `Menu` & `ContextMenu`: items equal to `"-"`, `"---"`, or `""` render a horizontal `Separator` line instead of a button while preserving item indices.
- **Control & Shape Enhancements (`src/controls.br`)**:
  - `Grid`: proportional integer column weights (`columnWeights = [1, 2, ...]`) and fixed pixel column widths (`widths = [80.0, 140.0, ...]`).
  - `ColorPicker`: optional editable hex `TextField` (`editableHex = true`), `colorHexAlpha(r, g, b, a)` (`#rrggbbaa`), and `parseColorHex(hex)` parser.
  - `DatePicker` & `TimePicker`: exact date range bounds (`minMonth`/`minDay` .. `maxMonth`/`maxDay`) disabling out-of-range days and months, plus a 24-hour `TimePicker(hour, minute, onChange, minuteStep = 1)` control.
  - Hollow stroke shapes: `Rectangle`, `Circle`, and `Capsule` with `color = ""` and non-empty `stroke` emit a hollow `Border` (`StrokeRect`).
- **Enhanced Navigation (`src/controls.br`, `src/events.br`)**:
  - `NavigationStack` keyboard & gesture pop: pressing `Escape` pops the top page when deeper than the root (after dismissing any open `Popover` or `Sheet` first), and swiping right (`OnSwipe(direction = "right")`) pops one level.
  - `NavigationStack` push/pop slide animations: automatic direction-aware horizontal slide transitions (`Transition(.Slide)` under `AnimationScope`).
  - `NavigationSplitView`: adaptive master-detail container rendering a two-column sidebar + detail layout in `Regular` width (`!isCompact(info)`) and collapsing to a `NavigationStack` in `Compact` width (`isCompact(info)`).
- **Reusable Native Window Host (`src/window.br`, `text/src/window.br`)**:
  - `ui.window` (`src/window.br`): unified headless-testable window driver (`Motion`, `BusyCells`, `stepWindow`, `noteAccessibilityRequest`, `shouldPollSystem`, `applySystem`, `loadImagesFrom`, `graphemeAtByte`, `caretAt`, `trackCaret`) encapsulating HiDPI coordinate scaling, pointer/touch/wheel/keyboard/IME event routing, clipboard synchronization, accessibility actions, animation frame pacing, and on-demand redraw scheduling.
  - `text.window` (`text/src/window.br`): `windowTheme`, `windowGlyphCache`, `firstFrame`, and `encodeFrame` helpers wiring `swash` font loading, `EngineMeasurer`, and `GlyphCache` display-list encoding.
  - Refactored `examples/todo_window/main.br` to use `ui.window` and `text.window` (reducing `main.br` from 360 lines to ~125 lines) and added `tests/window_host_test.br`.

## [0.1.0] — 2026-11-16

Initial open-source release of **boring-ui**, a declarative, reactive GUI toolkit for the [Boring](https://github.com/mlanoe/boring) programming language inspired by SwiftUI.

### Added

#### Headless Reactive Core (`src/core.br`)
- **Declarative View Lowering & Reconciliation**:
  - `Desc` tree representation of views (`describe(View)`) supporting eager lowering of native primitives and lazy expansion of composite views.
  - Reconciler (`Runtime.apply`) updating mounted view trees with minimal diffing and structural preorder mounting order.
  - Generational node identity (`Mounted`, `Handle`) with non-recycled generations to prevent stale handle aliasing.
  - Stable static sites (`Sited`) ensuring collision-free identity encoding across conditionals and keyed loops.
  - `StateBox` typed state retention for composite views, surviving parent rebuilds, branch switches, and keyed reordering.
  - Invalidation tracking (`dirty`) and transactional event updates (`beginEvent` / `endEvent`) deduplicating layout and render passes.
  - Update loop guard limiting cascading re-evaluations to 64 passes with detailed loop diagnostics.
  - Structured failure propagation catching errors during callback delivery, task execution, and animation frames.
  - Scoped dependency injection through `Environment` (`Provide`, `EnvMissing`) and reactive bindings (`Binding`, `bind`).
  - Identity-scoped asynchronous task lifecycle with cancellation on unmount.

#### Layout Negotiation Engine (`src/layout.br`)
- Two-pass size negotiation: parent proposals (`minWidth`, `idealWidth`, `maxWidth`) and child size reports (`Placed`).
- Complete set of primitive layout containers:
  - `Row` and `Column` flex-style arrangements with spacing, alignment, and flex factor distribution.
  - `Layer` (z-stack / overlay layout) with 9-point alignment anchors.
  - `Frame` for explicit min/ideal/max constraints.
  - `Padding` for uniform or edge-specific insets.
  - `Fill` expanding along specified axes to match parent proposal.
  - `Fraction` taking a proportional share (0.0 to 1.0) of parent proposals.
  - `Scroll` viewport clipping with scroll offset and programmatic glide.
  - `Spacer` and `Divider` / `Separator`.
- Layout memoization and cache reuse for unchanged subtrees.

#### Display Lists & Scene Graph (`src/scene.br`, `render/`)
- Display list abstraction (`Command` in `render/src/command.br`):
  - `DrawRect`, `StrokeRect`, `DrawText`, `DrawLine`, `DrawImage`, `DrawShadow`.
  - Scoped state modifiers: `PushClip`/`PopClip`, `PushOpacity`/`PopOpacity`, transforms.
- Spatial hit-testing (`hitTest`) resolving pointer interactions against placed scene trees and clip rects.
- Reference software CPU rasterizer (`render/src/cpu.br`).
- High-performance 2-level tiled kernel rasterizer (`render/src/kernel.br`) targeting CPU SIMD and GPU WGPU/Metal execution.

#### Event Dispatch & Interaction (`src/events.br`)
- 3-phase keyboard event routing: `Capture` (top-down), `Target`, and `Bubble` (bottom-up), with independent stop-propagation and prevent-default flags.
- Comprehensive keyboard focus management:
  - Focus tree, tab order traversal, and directional navigation (`FocusSection`).
  - Non-modal focus scopes (`FocusScope`, `focusOrder`, `focusable`).
  - Automatic focus ring rendering with customizable theme styles.
- Pointer event routing for mouse and touch (`pointerDown`, `pointerMove`, `pointerUp`, `pointerCancel`).
- Frame-rate independent physics-based momentum scrolling.
- Gesture recognizers:
  - `OnTap` with multi-tap detection and spatial tolerance.
  - `OnLongPress` with configurable press durations.
  - `OnSwipe` with directional detection and thresholding.
  - `OnPan` with continuous delta tracking.
- Drag and drop subsystem (`Draggable`, `DropTarget`).
- Text editing interactions:
  - Multi-level undo/redo history for text inputs.
  - Full IME (Input Method Editor) inline composition and candidate display.
  - Unicode grapheme-aware caret positioning, selections, and word navigation.

#### Widget & Component Library
- **Typography & Input**:
  - `Text` with styling, truncation, line limits, and alignment.
  - `TextField` with placeholder, secure text entry, custom formatting, and view-returning decoration styles.
- **Controls**:
  - `Button`, `Toggle`, `Slider`, `Stepper`.
  - Built-in control styles: `Underlined` text fields, `Switch` toggles, rounded button skins.
  - View-returning control styles allowing custom visual subtrees based on hover, focus, and pressed states.
- **Collections & Lists**:
  - `List` with viewport virtualization and row recycling.
  - `MultiList` with single, multiple, and range selection (Shift-click, Cmd-click, SelectAll).
- **Navigation & Overlays**:
  - `NavigationStack`, `NavigationLink`, `NavigationBack`.
  - `Sheet` modal sheets and dialogs.
  - `Popover` with automatic screen-edge flipping and anchor pointing.
  - `Tooltip` with configurable hover delays.
  - `Menu` and `ContextMenu` (right-click contextual menus).
  - `Alert` and `ConfirmationDialog`.
- **Pickers**:
  - `DatePicker` with monthly calendar grid navigation.
  - `ColorPicker` with presets and custom RGB/hex selection.
  - Segmented `Picker` and `Tabs`.
- **Forms & Layouts**:
  - `Form`, `Section`, `LabeledContent`.
  - `Grid` with equal-width column alignment.
- **Windowing & Desktop**:
  - `Desktop` container providing an in-surface multi-window desktop environment with movable, cascaded windows and taskbar/dock minimization.

#### Styling, Theming & Appearance (`src/theme.br`)
- Dynamic theme resolution through the environment hierarchy.
- Built-in platform themes matching native operating systems:
  - macOS theme (`macTheme`).
  - Windows Fluent theme (`fluentTheme`).
  - GNOME Adwaita theme (`adwaitaTheme`).
- Operating system dark/light mode detection and dynamic switching.
- System accent color extraction and automatic contrast adaptation.
- Extensible `ControlStyle` trait system supporting per-control or subtree styling (`Styled`).

#### Text Shaping & Glyph Rasterization (`text/`)
- `boring-ui-text` package integrating Swash font loading and shaping.
- Glyph rasterization and dynamic texture atlas caching.
- Bi-directional text layout and Unicode script fallback.

#### Mobile & Adaptive Layout (`src/mobile.br`)
- `ScreenInfo` descriptors modeling device screen dimensions, notch / safe area insets, and software keyboard metrics.
- Responsive containers: `SafeArea`, `Adaptive` (compact vs. regular layouts), `MinTarget` (minimum touch target enforcement).
- Soft keyboard tracking following focused text fields.
- iOS Simulator demo runner (`examples/todo_window/ios_sim.sh`).

#### Quality & Architecture Hardening
- Comprehensive test suite with 90+ test suites covering layout, reconciliation, rendering, events, and controls.
- Architecture audit report (`docs/AUDIT.md`) tracking and resolving edge cases.
