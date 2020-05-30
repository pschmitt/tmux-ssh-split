# TMUX SSH split

![](./tmux-ssh-split.gif)

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
`ssh_split_h_key` or `ssh_split_v_key`.

They should contain the key that will be bound to respectively the h or v
split.

Other options include:

- `@ssh_split_keep_cwd`: Whether to set the start directory of the new pane to
the one from the current pane. (Essentially the same as what
`tmux split -c "#{pane_current_path}"` does)
- `@ssh_split_fail`: Whether to not do anything if the current pane is *not* 
running SSH. By default a normal split will be done.
- `@ssh_split_no_shell`: If set to `true` this will disable the spawning of a
shell session *after* the SSH session. This will make the pane exit when the 
SSH session ends.
- `@ssh_split_verbose`: Display a message when spawning the SSH shell

## Example config

```
set-option -g @ssh_split_keep_cwd "true"
set-option -g @ssh_split_fail "false"
set-option -g @ssh_split_no_shell "false"
set-option -g @ssh_split_verbose "true"
set-option -g @ssh_split_h_key "|"
set-option -g @ssh_split_v_key "S"

set -g @plugin 'pschmitt/tmux-ssh-split'
```
