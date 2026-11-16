# Changelog

All notable changes to `boring-ui` are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

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
