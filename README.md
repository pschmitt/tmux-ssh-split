# TMUX SSH split

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

- verbose: Display a message when spawning the SSH shell
- fail: Whether to not do anything if the current pane is *not* running SSH.
By default a normal split will be done.
- no_shell: If set to `true` this will disable the spawning of a shell session
- *after* the SSH session. This will make the pane exit when the SSH session
- ends.

## Example config

```
set-option -g @ssh_split_fail "false"
set-option -g @ssh_split_no_shell "false"
set-option -g @ssh_split_verbose "true"
set-option -g @ssh_split_h_key "|"
set-option -g @ssh_split_v_key "S"

set -g @plugin 'pschmitt/tmux-ssh-split'
```
