# Crystal MPD

A desktop [MPD](https://www.musicpd.org/) client written in [Crystal](https://crystal-lang.org/) using the [UIng](https://github.com/kojix2/uing) (libui-ng) GUI library.

## Screenshots

_(coming soon)_

## Features

- Playback controls: play/pause, previous, next
- Shuffle and repeat toggle buttons
- Seek slider with elapsed / total time display
- Album cover art fetched from MPD (`readpicture` / `albumart`)
- Integrated playlist with Artist, Title, Duration columns
- Currently playing track highlighted and auto-scrolled into view
- Window title updates to reflect the current track
- Settings window for MPD host / port configuration
- About dialog with MPD server stats (version, artists, albums, songs, uptime)

## Requirements

- Crystal >= 1.19.1
- [libui-ng](https://github.com/libui-ng/libui-ng) shared library installed
- GTK3 (required by libui-ng on Linux)
- A running MPD server

## Installation

```sh
git clone https://github.com/mamantoha/mpd-ui
cd mpd-ui
shards install
crystal build src/mpd_ui.cr --release -o mpd-ui
./mpd-ui
```

## Dependencies

| Shard | Purpose |
|---|---|
| [kojix2/uing](https://github.com/kojix2/uing) | libui-ng bindings — native desktop GUI |
| [mamantoha/crystal_mpd](https://github.com/mamantoha/crystal_mpd) | MPD protocol client |
| [stumpycr/stumpy_png](https://github.com/stumpycr/stumpy_png) | Pure-Crystal PNG decoding for cover art |
| [stumpycr/stumpy_jpeg](https://github.com/stumpycr/stumpy_jpeg) | Pure-Crystal JPEG decoding for cover art |

## Platform support

| Platform | Status |
|---|---|
| Linux (GTK3) | ✅ Tested |
| macOS | ❓ Untested |
| Windows | ❓ Untested |

## Custom components

### `ToggleButton` (`src/mpd_ui/toggle_button.cr`)

UIng does not provide a toggle button widget. `ToggleButton` is a custom widget built on top of `UIng::Area` (a libui-ng raw drawing surface).

- Renders a filled rectangle with a centered emoji/text label using the `UIng::Area::Draw` API (paths, brushes, text layouts)
- Active state shown as a blue highlight; hover tracked for a subtle gray tint
- Minimum size enforced via `uiControlHandle` + `gtk_widget_set_size_request` because `uiNewArea` has no natural GTK size hint
- Font loaded once via `UIng::FontDescriptor` (`uiLoadControlFont`) and cached as an instance variable to avoid per-frame allocation and Pango errors
- `AttributedString` and `TextLayout` created and freed deterministically each draw using the `open { }` block API to prevent libui leak warnings at shutdown

### `PlaylistView` (`src/mpd_ui/playlist_view.cr`)

A `UIng::Table`-backed playlist widget embedded directly in the main window.

- Custom `UIng::Table::Model::Handler` backed by a mutable `Array(Song)` that is updated in-place (`clear` + `concat`) so the model handler closure always sees the live array — replacing the array reference caused a `uiTableModel_get_value: stamp` assertion crash
- Per-row background color column (type `Color`) highlights the active track with a blue tint
- Auto-scrolls to the playing row using raw GTK calls: `uiControlHandle` → `gtk_bin_get_child` (GtkScrolledWindow → GtkTreeView) → `gtk_tree_view_scroll_to_cell`
- Proper cleanup on window close: `table.destroy` before `model.free`, matching libui-ng's required teardown order

## Architecture notes

- **Dual MPD clients**: a regular `MPD::Client` for commands and a second client with `with_callbacks: true` running in a background `Thread` for push events (song change, state, elapsed, random, repeat, playlist)
- **UI thread safety**: all UI mutations from the callback thread go through `UIng.queue_main { }`
- **Cover art**: fetched in a third `Thread` using a dedicated MPD connection; decoded in pure Crystal (no subprocess) via `StumpyJPEG`/`StumpyPNG` to avoid `Process.run` deadlock inside threads (Crystal's `waitpid` signal handler is occupied by `UIng.main`)
- **Stale result guard**: `@current_file` is compared before applying a fetched cover image to discard results that arrived after the track changed

## License

MIT
