# google-calendar.nvim

A Neovim plugin that brings Google Calendar into your editor. It renders a month view, a day agenda, and an event detail card in floating windows, and lets you create, update, delete, and manage Google Meet links without leaving Neovim.

Calendar operations are delegated to [`gws`](https://github.com/googleworkspace/cli); the plugin does not call the Google Calendar API directly.

## Features

- Month view with previous/next month navigation, today jump, and a highlighted selected day
- Day agenda with colored dots, start times, and event titles
- Events from multiple configured calendars, merged into one month view
- Google Calendar-style event detail card with attendees, organizer, description, and Meet URL
- Create, update, and delete events
- Multi-window event composer modeled after Google Calendar's create dialog
- Guest invitations by email address
- Add a Google Meet URL when creating an event, and copy it from the detail view
- In-memory month cache for fast month navigation
- Configurable window sizes, keymaps, and highlight groups

## Requirements

- Neovim 0.10 or later
- `gws` 0.22.5 or later, installed and authenticated
- A Google account with the Google Calendar API enabled

```bash
gws auth login
```

If `gws` is missing or authentication fails, the plugin reports an error and does not open the calendar.

## Installation

### lazy.nvim

```lua
{
  'skanehira/google-calendar.nvim',
  config = function()
    require('google-calendar').setup()
  end,
}
```

### Manual installation

```lua
vim.opt.runtimepath:append('/path/to/google-calendar.nvim')
require('google-calendar').setup()
```

`setup()` is optional. The plugin works with its defaults if you do not call it.

## Commands

| Command | Description |
| --- | --- |
| `:GoogleCalendar` | Open the current month. If the month view is already open, focus it and reuse the cache. |
| `:GoogleCalendar 2026-11` | Open the specified month. |
| `:GoogleCalendar 2026-13` | Report an invalid month and do not open the month view. |

Use `r` or `R` in the month view to refetch the displayed month.

## Default keymaps

| Screen | Key | Action |
| --- | --- | --- |
| Month | `h` / `l` | Select the previous / next day |
| Month | `k` / `j` | Select the previous / next week |
| Month | `H` / `L` | Go to the previous / next month |
| Month | `t` | Jump to today |
| Month | `<CR>` | Open the day agenda for the selected day |
| Month | `a` | Create an event on the selected day |
| Month | `r` / `R` | Refetch the displayed month |
| Month | `?` | Open help |
| Month | `q` / `<Esc>` | Close the month view |
| Agenda | `j` / `k` | Select an event |
| Agenda | `<CR>` | Open the selected event |
| Agenda | `d` | Delete the selected event |
| Agenda | `?` | Open help |
| Agenda | `q` / `<Esc>` | Return to the month view |
| Detail | `e` | Open the update form |
| Detail | `d` | Open the delete confirmation |
| Detail | `y` | Copy the Meet URL |
| Detail | `g` | Expand or collapse the guest list |
| Detail | `?` | Open help |
| Detail | `q` / `<Esc>` | Return to the agenda |
| Confirm | `y` | Delete the event |
| Confirm | `n` / `q` / `<Esc>` | Close the confirmation without deleting |
| Form | `<Tab>` / `<S-Tab>` | Move to the next / previous composer row |
| Form | `<CR>` | Open the editor for the selected row, or toggle Meet |
| Form | `<Space>` | Toggle all-day or Meet |
| Form | `:w` | Save |
| Form | `<Esc>` / `q` | Cancel. `<Esc>` leaves insert mode first; `q` works in normal mode only. |
| Form | `?` | Open help |
| Form editor | `<CR>` | Edit the selected date/time field |
| Form editor | `:w` | Apply the editor value and close it |
| Form editor | `<Esc>` / `q` | Close the editor without applying |
| Help | `q` / `<Esc>` | Close help |

All keys can be changed through `setup()`. See `:help google-calendar-keymaps` for details.

## Configuration

```lua
require('google-calendar').setup({
  -- Optional override. Prefer the config file below so calendar IDs stay
  -- out of your dotfiles.
  calendars = { 'primary' },

  -- First day of the week: 'sunday' or 'monday'.
  week_start = 'sunday',

  -- Maximum number of events shown in a month cell (1-10).
  max_events_per_cell = 3,

  -- Month view size as a ratio of the usable area (excluding the border).
  -- 1.0 fills the available space.
  width = 0.7,
  height = 0.7,

  -- Agenda and detail sizes as ratios of the usable area.
  agenda = { width = 0.5, height = 0.7 },
  detail = { width = 0.5, height = 0.5 },

  -- Date format.
  date_format = '%Y-%m-%d %H:%M',

  -- Path or name of the gws executable.
  gws_cmd = 'gws',

  -- Notification function (replaceable for tests).
  notify = vim.notify,

  -- Clipboard writer (replaceable for tests).
  clipboard = function(url)
    vim.fn.setreg('+', url)
  end,

  -- Per-screen keymap overrides. Use false to disable a key.
  keymaps = {
    month = {
      prev_day = 'h',
      next_day = 'l',
      prev_week = 'k',
      next_week = 'j',
      prev_month = 'H',
      next_month = 'L',
      today = 't',
      agenda = '<CR>',
      create = 'a',
      refresh = 'r',
      help = '?',
      close = 'q',
      esc_close = '<Esc>',
    },
    agenda = { next = 'j', prev = 'k', open = '<CR>', help = '?', close = 'q', esc_close = '<Esc>' },
    detail = {
      edit = 'e',
      delete = 'd',
      copy_meet = 'y',
      toggle_guests = 'g',
      help = '?',
      close = 'q',
      esc_close = '<Esc>',
    },
    form = {
      next_field = '<Tab>',
      prev_field = '<S-Tab>',
      edit = '<CR>',
      toggle = '<Space>',
      save = ':w',
      cancel = '<Esc>',
      close = 'q',
      help = '?',
    },
    confirm = { yes = 'y', no = 'n', close = 'q', esc_close = '<Esc>' },
    help = { close = 'q', esc_close = '<Esc>' },
  },

  -- Highlight overrides.
  highlights = {},
})
```

### Calendar configuration file

To keep calendar IDs out of your dotfiles, put them in:

```text
stdpath('data')/google-calendar.nvim/config.json
```

For a default Neovim setup this is `~/.local/share/nvim/google-calendar.nvim/config.json`. This directory is normally outside a Neovim dotfiles repository.

```json
{
  "calendars": [
    "primary",
    "work@example.com"
  ]
}
```

- If the file does not exist, `primary` is used.
- If the file is invalid, the plugin warns and falls back to `primary`.
- `GOOGLE_CALENDAR_CONFIG` can point to a different file.
- `setup({ config_file = '/path/to/config.json' })` also overrides the path.
- `setup({ calendars = { ... } })` still takes precedence over the file when explicitly provided.

### Window sizes

`width` and `height` are ratios of the usable area, excluding the float border. The month view distributes leftover height across the event rows of each week and keeps the same size while loading and after data arrives. The agenda defaults to a tall `0.5 x 0.7` window; the detail window defaults to `0.5 x 0.5`.

### Keymap overrides

Keymaps are deep-merged with the defaults. Setting a key to `false` disables it. Unknown screens or actions produce a warning and are ignored.

```lua
require('google-calendar').setup({
  keymaps = {
    form = { save = '<A-s>' },
    month = { close = false },
  },
})
```

### Highlights

The default highlight groups are:

| Group | Purpose |
| --- | --- |
| `GoogleCalendarHeader` | Month title and weekday header |
| `GoogleCalendarToday` | Today's date |
| `GoogleCalendarSelected` | Selected day and cell |
| `GoogleCalendarSunday` | Sunday dates |
| `GoogleCalendarSaturday` | Saturday dates |
| `GoogleCalendarOtherMonth` | Dates from adjacent months |
| `GoogleCalendarEvent` | Event title text (no background) |
| `GoogleCalendarEventTime` | Event time |
| `GoogleCalendarEventColor1` ... `GoogleCalendarEventColor11` | Agenda dot colors mapped from `colorId` |
| `GoogleCalendarDetailTitle` | Detail title |
| `GoogleCalendarDetailIcon` | Detail section icons |
| `GoogleCalendarDetailMuted` | Detail secondary text |
| `GoogleCalendarDetailMeet` | Meet URL in the detail view |
| `GoogleCalendarDetailAccepted` | Accepted guests |
| `GoogleCalendarDetailPending` | Pending or tentative guests |
| `GoogleCalendarDetailDeclined` | Declined guests |
| `GoogleCalendarFormTitle` | Composer title |
| `GoogleCalendarFormMuted` | Composer placeholder and secondary text |
| `GoogleCalendarFormIcon` | Composer section icons |
| `GoogleCalendarFormButton` | Composer buttons such as Save |
| `GoogleCalendarFormSeparator` | Composer title separator |
| `GoogleCalendarBorder` | Float border and month grid separators |
| `GoogleCalendarError` | Form errors |

Override any group with `setup({ highlights = { ... } })`. Set a group to `false` to disable it.

## Behavior notes

- Events from every calendar in `calendars` are fetched and merged into the month view. The first calendar is used for new events; updates and deletes use the event's own calendar ID.
- The selected day is shown with the `GoogleCalendarSelected` background across the whole cell and in the month window title.
- Month grid separators use the same `GoogleCalendarBorder` highlight for both horizontal and vertical lines.
- Month data is cached in memory. The cache is cleared when the month window closes, when you press `r` or `R`, and after creating, updating, or deleting an event.
- Agenda rows use a colored `●` or `○` dot, the start time, and the title. Events with `status == 'tentative'` or `transparency == 'transparent'` use the hollow `○` dot. All-day events use the all-day label.
- The detail view uses a Google Calendar-style card. Guests are collapsed by default when there are more than five attendees; press `g` to expand or collapse them. The cursor stays in place when toggling.
- Event descriptions wrap to the window width and are never truncated.
- `y` copies the Meet URL to the `+` register. If the event has no Meet URL, the plugin reports that instead.

### Event composer

The create and update form uses a Google Calendar-style composer with separate editor windows:

- The main composer shows the title, date/time, guests, Google Meet, location, description, and calendar.
- `<CR>` on the title, date/time, guests, location, or description row opens a dedicated editor window.
- The description editor uses the same size as the main composer so multiline descriptions have room to breathe.
- Icons are padded to two display cells, so each row's description text starts in the same column.
- `<CR>` or `<Space>` on the Google Meet row toggles Meet.
- `<Space>` on the date/time row toggles between a timed event and an all-day event.
- The guests row opens a dedicated guest editor. Enter one email address per line; duplicates are removed and invalid addresses are reported.
- Save from the main composer with `:w`. Editor windows apply with `:w` and close with `<Esc>`.

## Help

The plugin ships with Vim help:

```vim
:help google-calendar
```

Useful tags:

- `:help google-calendar-commands`
- `:help google-calendar-keymaps`
- `:help google-calendar-config`
- `:help google-calendar-highlights`
- `:help google-calendar-behavior`
- `:help google-calendar-troubleshooting`

If you add the plugin to `runtimepath` manually, run `:helptags doc` once to generate the help tags.

## Scope

The MVP targets a month view over the calendars configured in `calendars`. Week view, keyword search, tasks, and out-of-office events are out of scope.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, tests, linting, formatting, and type checking.
