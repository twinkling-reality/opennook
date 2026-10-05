# Sample themes

Theme files to start from. Each is a `NookTheme` as JSON, listing only what differs
from the standard theme.

| File | Backdrop | Also |
|---|---|---|
| `dusk.json` | Linear gradient, black at the notch to violet | Coral accent, large radius, violet chrome shadow |
| `aurora.json` | 3x3 mesh gradient, green and indigo | Mint accent, rounded type, green chrome shadow |
| `ember.json` | Radial gradient glowing from the bottom | Amber accent, serif type, warm chrome shadow |

Try one on any ShowcaseNook scene. It reloads each time you save the file:

```sh
swift run ShowcaseNook --scene agenda --theme Examples/Themes/aurora.json
```

In your own app, load one with `try NookTheme(contentsOf: url)`, or follow it while
you edit with `configuration.chromeThemeSource = .watching(fileAt: url)`. Every key
is described in the [Theming guide](https://opennook.dev/guides/theming/#theme-files).
