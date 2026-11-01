# Agent guidance

`tmux-ssh-split` is a tmux plugin for arranging SSH sessions in panes.

## Development

- Keep plugin behavior, sample configuration, and `README.md` aligned.
- Validate changed scripts with their declared interpreter and exercise the plugin in a disposable tmux server.
- Do not open or split panes in a user's live tmux session while validating changes.
- Load the `shell` skill before changing shell scripts.

## CI

- Before changing GitHub Actions, inspect the current guidance in `pschmitt/ci-workflows`. Use `@main` in every `uses:` reference to a shared workflow or action.
