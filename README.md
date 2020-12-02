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

## Example config

```
set-option -g @ssh-split-keep-cwd "true"
set-option -g @ssh-split-fail "false"
set-option -g @ssh-split-no-shell "false"
set-option -g @ssh-split-strip-cmd "true"
set-option -g @ssh-split-verbose "true"
set-option -g @ssh-split-h-key "|"
set-option -g @ssh-split-v-key "S"

set -g @plugin 'pschmitt/tmux-ssh-split'
```

## Compatibility with other plugins

Some plugins may try to bind the same keys than `tmux-ssh-split`.

### Problem

[tmux-pain-control](https://github.com/tmux-plugins/tmux-pain-control) is one
of those.
With the example config above, both `tmux-ssh-split` and `tmux-pain-control`
would try to bind the `|` key. The plugin loaded last wins.

### Solution

To make `tmux-pain-control` not bind the `|` key you can set the following:

```
set -g @disabled_keys "|"
```
