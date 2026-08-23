# Wallpaper Rotate for Omarchy

An [Omarchy](https://omarchy.org/) shell plugin that rotates your wallpapers on
a schedule — from **your own folders** (recursively), not just theme bundles.

A small picture-frame icon sits in the bar:

- **Left-click** — popup panel: current wallpaper name, open its folder,
  switch now, and schedule controls (interval down to **1 minute**, order).
- **Right-click** — switch to the next wallpaper immediately.
- **Hover** — tooltip with the current wallpaper's name.

<img width="361" height="488" alt="image" src="https://github.com/user-attachments/assets/03940652-d939-4ac9-ad2e-90bd63eaeb74" />


## Features

- Scheduled rotation from any folder you point it at
  (default `~/Pictures/wallpapers/`, scanned recursively).
- Formats supported by Omarchy's background engine: `jpg`, `jpeg`, `png`,
  `gif`, `bmp`, `webp`. Videos are ignored automatically.
- Three orders: **Random** (never repeats the current one), **Shuffle**
  (plays every wallpaper once before repeating), **Sequential**.
- Theme-change aware: switching Omarchy themes restarts the rotation so the
  theme's own pick gets a moment to shine.
- Cheap while idle: a lightweight timer checks the schedule; processes only
  spawn when a change is due or the panel is open.
- Thumbnails reuse Omarchy's built-in image-selector cache — no duplicate cache.

## Install

```sh
omarchy plugin add https://github.com/Somnius/Omarchy-Wallpaper-Rotate.git --enable
```

Then place the widget in the bar:

```sh
omarchy bar plugin add lef.wallpaper-rotate --section right
```

### From a local clone (development)

```sh
git clone https://github.com/Somnius/Omarchy-Wallpaper-Rotate.git
ln -s "$PWD/Omarchy-Wallpaper-Rotate" ~/.config/omarchy/plugins/lef.wallpaper-rotate
omarchy-shell shell rescanPlugins
```

> **Dev loop caveat:** Quickshell's file watcher does not follow the symlink,
> so edits made in the clone do **not** hot-reload. After changing files run
> `omarchy restart shell` (or `omarchy-shell shell rescanPlugins`, then a shell
> restart if visuals are stale). Plugins cloned directly into
> `~/.config/omarchy/plugins/` hot-reload normally.

Validate at any time with:

```sh
omarchy plugin validate ~/.config/omarchy/plugins/lef.wallpaper-rotate
```

## Configuration

Config lives in `~/.config/omarchy/wallpaper-rotate/config.json` and hot-reloads.

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | boolean | `true` | Rotate automatically |
| `intervalMinutes` | integer | `5` | Minutes between changes (**minimum 1**, max 1440) |
| `mode` | string | `"random"` | `random`, `shuffle`, or `sequential` |
| `directory` | string | `"~/Pictures/wallpapers"` | Root folder to scan (`~` allowed) |

Interval and order can also be changed from the panel; everything else via the
config file.

## IPC & keybindings

```sh
omarchy-shell lef.wallpaper-rotate next    # switch now
omarchy-shell lef.wallpaper-rotate toggle  # open/close the panel
```

Hyprland binding example (`~/.config/hypr/bindings.lua`):

```lua
o.bind("SUPER + ALT + W", "Next wallpaper", "omarchy-shell lef.wallpaper-rotate next")
```

## Uninstall

```sh
omarchy plugin remove lef.wallpaper-rotate
```

(If installed via symlink, remove the symlink instead.)

## Credits

Heavy inspiration and proven patterns taken from
[dizziee.auto-wallpaper](https://github.com/JJDizz1L/dizziee.auto-wallpaper)
(MIT) — which rotates the *active theme's* wallpaper collection. This plugin
exists because that one doesn't scan arbitrary user folders like
`~/Pictures/wallpapers`; if you only want theme-background rotation, use
dizziee's excellent plugin instead. Service/widget wiring also follows the
first-party `omarchy.media` plugin structure.

## License

[MIT](LICENSE) — same as the plugin that inspired it.
