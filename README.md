# oconfig

Backup the Omarchy configs you actually changed, and restore them on a new
machine. Live files stay in `~/.config`. A local git repo stores only the
diff from packaged Omarchy defaults — not browser profiles, not plugins,
not your monitors.

## This machine

```sh
omarchy plugin add https://github.com/zhouzhuojie/oconfig.git --enable
~/.config/omarchy/plugins/io.github.zhouzhuojie.oconfig/bin/oconfig init
~/.config/omarchy/plugins/io.github.zhouzhuojie.oconfig/bin/oconfig save
```

That is the whole backup. `save` copies customized files into
`~/.local/share/oconfig/store` and commits.

Optional remote so another machine can pull the same store. Set it in the
widget settings (Git remote URL) or:

```sh
…/bin/oconfig remote git@github.com:YOU/omarchy-config.git
…/bin/oconfig push
```

`init --remote URL` clones that repo if the local store does not exist yet.
The bar panel: `i` init, `s` save, `p` push, `u` pull. Escape closes.

## New machine

Omarchy should already be installed. Then:

```sh
omarchy plugin add https://github.com/zhouzhuojie/oconfig.git --enable
~/.config/omarchy/plugins/io.github.zhouzhuojie.oconfig/bin/oconfig init \
  --remote git@github.com:YOU/omarchy-config.git
~/.config/omarchy/plugins/io.github.zhouzhuojie.oconfig/bin/oconfig restore
```

Or paste the same remote into the widget settings, press `i` then `u` then `r`.

`restore` copies the store onto `~/.config`. Existing files that differ are
backed up as `*.bak.oconfig.<timestamp>` first. Monitors and pointer feel
are not in the store, so the new box keeps its own display layout.

If the bar did not pick up `shell.json`, run `omarchy restart shell`.

## What is saved

Only paths Omarchy ships under `/usr/share/omarchy/config`, and only when
the live file differs from that packaged default:

Hyprland (`bindings.lua`, `hyprland.lua`, …), `omarchy/shell.json`,
terminals (kitty, alacritty, foot, ghostty), btop, tmux, starship, herdr,
and the rest of that tree.

Not saved (on purpose):

- `~/.config` as a whole (browsers, Signal, caches — often ~1GB)
- Chromium/Brave profiles
- Plugin source under `omarchy/plugins/` (those have their own git remotes)
- Themes, hooks, GPU flags
- `hypr/monitors.lua`, `input.lua`, `looknfeel.lua` (this machine’s hardware)

Edit `~/.config/oconfig/ignore.txt` to keep more files local.

## Panel

| Key | Action |
|---|---|
| `s` | Save customizations and commit |
| `p` | Push to the git remote |
| `u` | Pull (fast-forward) from the remote |
| `r` | Restore the store onto this machine |
| `c` | Refresh status |
| `i` | Initialize the store |
| Esc | Close |
| Middle click | Refresh |

```sh
omarchy bar move io.github.zhouzhuojie.oconfig --section right
```

## More commands

```sh
oconfig() {
  ~/.config/omarchy/plugins/io.github.zhouzhuojie.oconfig/bin/oconfig "$@"
}

oconfig check
oconfig remote git@github.com:YOU/omarchy-config.git
oconfig push
oconfig pull
oconfig save --push
oconfig diff
oconfig status
oconfig ignore add .config/hypr/foo.lua
```

The widget **Git remote URL** setting is optional and is the same value as
`oconfig remote`. Empty means local-only.

## Tests

```sh
python3 -m unittest tests.test_oconfig -v
# or
tests/test-oconfig.sh
```

Dependencies already on Omarchy: `git`, `python3`, `find`, `cmp`. No extra
packages. The plugin does not start a second shell process, does not use
sudo, and does not overwrite configs until you run `save` or `restore`.

## Remove

```sh
omarchy plugin remove io.github.zhouzhuojie.oconfig
```

The git store under `~/.local/share/oconfig/store` is left in place.

## License

MIT. See [LICENSE](LICENSE).
