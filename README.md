# oconfig

Save Omarchy customizations into a local git repo. Live files stay under
`~/.config`. The store only keeps files that differ from packaged Omarchy
defaults (plus a few extras like `.gitconfig`). Machine-local paths such as
monitors and pointer feel are ignored.

This is a `bar-widget` plugin: the bar pill loads a details panel. It does
not declare a separate `panel` kind.

## How it differs from existing plugins

| Plugin | What it stores |
|---|---|
| [config-sync](https://github.com/gladimdim/omarchy-config-sync-plugin) | Copy whole Omarchy trees to a GitHub repo and apply on another machine |
| [omavault](https://github.com/mutahir/omavault) | Timestamped snapshot archives |
| [omarchy-rollback](https://github.com/TadejPolajnar/omarchy-rollback) | Local inotify history of `~/.config` |
| **oconfig** | Only files that differ from `/usr/share/omarchy/config`, in a local git store |

## Install

```sh
omarchy plugin add https://github.com/zhouzhuojie/oconfig.git --enable
```

From this checkout:

```sh
omarchy plugin add /home/$USER/Dev/oconfig --enable --yes
```

Then initialize the store (or press `i` in the panel):

```sh
~/.config/omarchy/plugins/io.github.zhouzhuojie.oconfig/bin/oconfig init
```

## Usage

Click the bar icon to open the panel. Escape closes it.

| Key | Action |
|---|---|
| `s` | Save customizations into the store and commit |
| `r` | Restore the store onto this machine |
| `c` | Refresh status |
| `i` | Initialize the store (first run) |
| Middle click | Refresh |

CLI (same binary the panel runs):

```sh
oconfig() { ~/.config/omarchy/plugins/io.github.zhouzhuojie.oconfig/bin/oconfig "$@"; }

oconfig init                    # git repo at ~/.local/share/oconfig/store
oconfig check                   # customizations not in the store yet
oconfig save                    # copy them in and commit
oconfig restore                 # copy the store back (backs up live files first)
oconfig status
oconfig diff
oconfig ignore add .config/hypr/monitors.lua
```

On a new Omarchy box: install the plugin, `oconfig init --repo /path/to/clone`
if you already have a store, then `oconfig restore`.

## Configure

```sh
omarchy bar move io.github.zhouzhuojie.oconfig --section right
```

Store path and ignore list:

- `~/.config/oconfig/config.json` — `{ "repo": "..." }`
- `~/.config/oconfig/ignore.txt` — copied from the plugin on first init

## Remove

```sh
omarchy plugin remove io.github.zhouzhuojie.oconfig
```

The git store under `~/.local/share/oconfig/store` is left in place.

## Develop

Follows [Develop a Plugin](https://plugins.omarchy.org/develop.html): one
`bar-widget` kind, nested `Panel.qml`, no second Quickshell process.

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml
tests/test-oconfig.sh
```
