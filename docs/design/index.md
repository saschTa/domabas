# Design guide

Domabas uses the Glacier interface in light and dark modes. Navigation and
toolbars use translucent surfaces with teal accents. Document pages and image
previews retain their original colors. The [Glacier guide](../arch/frontend/glacier.md)
defines the palette, typography and shared controls.

## Current design references

| Topic | Reference |
| --- | --- |
| Colors, theme behavior and saved appearance | [Appearance and client preferences](../arch/frontend/appearance.md) |
| Shared controls, responsive layouts and job status | [UI components](../arch/frontend/components.md) |
| Phone and tablet navigation | [Mobile navigation](../arch/frontend/mobile-navigation.md) |
| Document cards, search and viewer | [Document workspace](../arch/frontend/documents.md) |
| App mark and platform icons | [Application branding](../arch/frontend/branding.md) |
| Capture the real interface using fictional data | [Screenshot guide](../screenshots/index.md) |

The Filed Paper mark shows a sheet above an archive tray. Its editable source is
[domabas-mark.svg](../../frontend/assets/branding/domabas-mark.svg); the square
[app icon](../../frontend/assets/branding/domabas-app.svg) and platform exports
come from it through `task generate:icons`.

Review the current application with `task dev` and follow the
[development guide](../development/index.md) for setup. Check wide and narrow
layouts, both appearance modes, keyboard focus and enlarged text when changing
shared components.
