# Bundled fonts

Domabas uses **Barlow Condensed Bold** for display text and headings, and
**DM Sans Regular and SemiBold** for body text, navigation and other controls.
The unmodified TrueType files are bundled locally under the `BarlowCondensed`
and `DMSans` families in [pubspec.yaml](../../pubspec.yaml). The
[application theme](../../lib/ui/app_theme.dart) selects these families; opening
a screen does not download a font.

Both families use the SIL Open Font License 1.1. Their notices are bundled and
registered in Flutter's license registry by [main.dart](../../lib/main.dart).
The [supplemental inventory](../../../third_party/licenses/supplemental.json)
retains each version, source record and license notice.

## Barlow Condensed

Version: **1.408 (Google Fonts v13)**. Retained records:
[source and hash](../licenses/barlow-source.txt),
[license](../licenses/barlow-ofl.txt).

- File: `BarlowCondensed-Bold.ttf`, weight 700.
- Source: [Google Fonts download](https://fonts.gstatic.com/s/barlowcondensed/v13/HTxwL3I-JCGChYJ8VI-L6OO_au7B46r2_3E.ttf).
- SHA-256: `7dde307fa887fc65ff5830cfada77a7decc5dae8d3c816c9d39ba3f1af1c4ed7`.

## DM Sans

Version: **4.004 (Google Fonts v17)**. Retained records:
[sources and hashes](../licenses/dmsans-source.txt),
[license](../licenses/dmsans-ofl.txt).

- File: `DMSans-Regular.ttf`, weight 400.
  Source: [Google Fonts download](https://fonts.gstatic.com/s/dmsans/v17/rP2tp2ywxg089UriI5-g4vlH9VoD8CmcqZG40F9JadbnoEwAopxhTg.ttf).
  SHA-256: `b0ae3e89a7d3ef2b1838bb4b1ceb0b17cc3435af061eee809d76aa623ff116e9`.
- File: `DMSans-SemiBold.ttf`, weight 600.
  Source: [Google Fonts download](https://fonts.gstatic.com/s/dmsans/v17/rP2tp2ywxg089UriI5-g4vlH9VoD8CmcqZG40F9JadbnoEwAfJthTg.ttf).
  SHA-256: `b79a2ea7a38f33fd96a282fadb9ce97626bb0724a44d21075859f0e50239993a`.

## Retained Lora file

`Lora-Variable.ttf` remains in this directory but is not declared in
`pubspec.yaml` or used by the current theme. Its source is
[Google Fonts Lora](https://github.com/google/fonts/tree/186331d77cc99caaa9c3b52391fd2b519c9e1ee8/ofl/lora)
at revision `186331d77cc99caaa9c3b52391fd2b519c9e1ee8`. Its SHA-256 is
`822a6621ccbe8d97d20ac88c1c41f5615c9c2c202eaa75f272cd452aac6475a7`.
The [retained license](../licenses/lora-ofl.txt) is SIL Open Font License 1.1.
