# TMUX SSH split

[![](./tmux-ssh-split.gif)](https://asciinema.org/a/335250)

This plugin builds upon the idea of [sshh](https://github.com/yudai/sshh/).
It's essentially a modern version of the same idea.

**TLDR**: This plugin allows doing seamless SSH splits. Ie if the current pane
contains an SSH session and you hit the magic key the pane will be split
and the newly spawned pane will host an SSH session to the host you were
currently on. If no SSH session was running: do a normal split.

## Installation

Using [TPM](https://github.com/tmux-plugins/tpm):

```
set -g @plugin 'pschmitt/tmux-ssh-split'
```

## Configuration

To have this plugin do anything you need to at least set one of
`ssh-split-h-key` or `ssh-split-v-key`.

They should contain the key that will be bound to respectively the h or v
split.

Other options include:

- `@ssh-split-keep-cwd`: Whether to set the start directory of the new pane to
the one from the current pane. This has essentially the same effect as
`tmux split -c "#{pane_current_path}"`.
- `@ssh-split-keep-remote-cwd`: Same as above, except for remote (ssh) splits.
Please be aware that the remote path detection relies on PS1 parsing, so this
won't work if your prompt does not contain the current path.
- `@ssh-split-fail`: Whether to not do anything if the current pane is *not*
running SSH. By default a normal split will be done.
- `@ssh-split-no-shell`: If set to `true` this will disable the spawning of a
shell session *after* the SSH session. This will make the pane exit when the
SSH session ends.
- `@ssh-split-strip-cmd`: If set to `true` the SSH command executed in the new
pane will be stripped of the remote command portion. Example: when splitting
a pane where `ssh HOST COMMAND` is running this will make tmux-ssh-split create
a new pane with a start command of `ssh HOST`. Default: `false`.
- `@ssh-split-verbose`: Display a message when spawning the SSH shell.
- `@ssh-split-debug`: Debug mode. Redirects the output of the script to `/tmp/tmux-ssh-split.log`

## Example config

```
set-option -g @ssh-split-keep-cwd "true"
set-option -g @ssh-split-keep-remote-cwd "true"
set-option -g @ssh-split-fail "false"
set-option -g @ssh-split-no-shell "false"
set-option -g @ssh-split-strip-cmd "true"
set-option -g @ssh-split-verbose "true"
set-option -g @ssh-split-debug "false"
set-option -g @ssh-split-h-key "|"
set-option -g @ssh-split-v-key "S"

set -g @plugin 'pschmitt/tmux-ssh-split'
```

## Compatibility with other plugins

Some plugin may try to bind the same keys than `tmux-ssh-split`.

### Problem

[tmux-pain-control](https://github.com/tmux-plugins/tmux-pain-control) is one
of those.
With the example config above, both `tmux-ssh-split` and `tmux-pain-control`
would try to bind the `|` key. The plugin loaded last wins.

### Solution

I've sent [a PR to fix this](https://github.com/tmux-plugins/tmux-pain-control/pull/33)
upstream. In the meantime you can
[use my fork](https://github.com/pschmitt/tmux-pain-control/).

To make the **forked** `tmux-pain-control` not bind the `|` key you can set
the following:

```
set -g @disabled_keys "|"
```

## Tips & Tricks

In case you want to be able to determine in a local, or remote split if the
command has been spawned via tmux-ssh-split you can check for the
`TMUX_SSH_SPLIT` env var. It should be set to `1` for all splits.

If `TMUX_SSH_SPLIT` is not set on remote split please verify that
`TMUX_SSH_SPLIT` is listed in the `AcceptEnv` property in your sshd config.

Example:

```
AcceptEnv LANG LC_* TMUX_SSH_SPLIT
```
