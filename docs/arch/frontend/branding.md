# Application branding

Domabas uses the selected Filed Paper symbol: one sheet above an archive tray.
The canonical vector source is
[`domabas-mark.svg`](../../../frontend/assets/branding/domabas-mark.svg).
Its two paths use flat rust `#AD4433`; app tiles use warm paper `#FFFDF7` on rust.

`task generate:icons` runs the Bun TypeScript exporter with pinned Sharp 0.35.4.
It produces the square app SVG, a transparent 256-pixel Flutter mark, the SVG
favicon, PNG sizes for Android/iOS/macOS/web/Linux, Android adaptive vector
resources, and a Windows ICO containing nine PNG frames from 16 to 256 pixels.
All outputs are checked in. Ordinary builds do not run the exporter.
`task generate:icons:check` verifies them without writing; `task check` and
GitHub CI include this check. Change the canonical SVG and regenerate; do not edit
derived platform artwork by hand.

The workspace's brand widget tints the transparent mark with the theme's
`onPrimary` color on its existing primary tile. This preserves both appearance
modes without a separate drawing or Flutter SVG dependency. Navigation and
document-type symbols keep their existing meanings.

iOS icons and the 180-pixel Apple touch icon are full opaque squares without an
alpha channel. macOS adds transparent outer spacing around a rounded tile.
Windows, ordinary web icons and legacy Android icons use rounded tiles. PWA
maskable exports use an opaque edge-to-edge background and a slightly smaller
foreground inside the central safe circle. Android adaptive exports have a
separate vector foreground and background, with a monochrome layer on API 33+.
The foreground uses a 108dp viewport equivalent with a roughly 49dp symbol.

Linux embeds its icon as a GLib resource and supplies it to the GTK window, so
the window icon does not depend on the current directory. This requires
`glib-compile-resources`, supplied by the GTK/GLib development toolchain.
Desktop environment launcher integration still belongs to distribution
packaging; Wayland does not use the GTK per-window icon hint.

The [tooling guide](../tooling.md#application-icon-generation) explains icon
generation and consistency checks.
