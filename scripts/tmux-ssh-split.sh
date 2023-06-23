#!/usr/bin/env bash

usage() {
  echo "Usage: $(basename "$0") ARGS"
  echo
  echo "Arguments:"
  echo "  -v|-h       Vertical or horizontal split"
  echo "  --fail      Error out if there is no SSH session in the current pane"
  echo "  --verbose   Display a message when spawning a new SSH session/pane"
  echo "  --no-shell  Don't spawn a shell after the SSH command"
  echo "  -c DIR      Set start directory for pane"
}

get_current_pane_info() {
  tmux display -p '#{pane_id} #{pane_pid}'
}

get_current_pane_id() {
  get_current_pane_info | awk '{ print $1 }'
}

get_pane_pid_from_pane_id() {
  tmux list-panes -F "#{pane_id} #{pane_pid}" | awk "/^$1 / { print \$2}"
}

__is_ssh_option() {
  # This returns a shift index
  # 0: Don't shift (this is the hostname or part of the command)
  # 1: shift 1 (optionless flags)
  # 2: shift 2 (flags with mandatory options)
  case "$1" in
    autossh|ssh)
      echo "1"
      ;;
    # Optionless flags (can be combined - hence the "*"
    -4*|-6*|-A*|-a*|-C*|-f*|-G*|-g*|-K*|-k*|-M*|-N*|-n*|-q*|-s*|-T*|-t*|-v*|-V*|-X*|-x*|-Y*|-y*)
      echo "1"
      ;;
    # Flags with options
    -B|-b|-c|-D|-E|-e|-F|-I|-i|-J|-L|-l|-m|-O|-o|-p|-Q|-R|-S|-W|-w)
      echo "2"
      ;;
    # Unknown flags
    -*)
      echo "Unknown flag: $1" >&2
      return 9
      ;;
    # Command
    *)
      return 1
      ;;
  esac
}

strip_command() {
  # FIXME This won't work for commands like the followin:
  # ssh host.example.com -l root
  # It will remove the "-l root" part.

  # Re-set the args in case the whole command is passed through "$1"
  if [[ "$#" -eq 1 ]]
  then
    # shellcheck disable=2086
    set -- $1
  fi

  # Return immediately if not processing an SSH command
  if ! [[ "$1" =~ ^(auto)?ssh ]]
  then
    return 1
  fi

  local og_args=("$@")
  local res=()
  local shift_index
  local host_index=0

  while [[ -n "$*" ]]
  do
    shift_index=$(__is_ssh_option "$1")
    # shellcheck disable=2181
    # Stop processing args if we hit a command
    if [[ "$?" -ne 0 ]]
    then
      break
    fi

    # Advance host index (we didn't process that arg yet)
    host_index=$(( host_index + shift_index ))

    if [[ -n "$shift_index" ]]
    then
      shift "$shift_index"
    fi
  done

  if [[ -n "$1" ]]
  then
    # Shift host
    shift
  fi

  # Save remaining args
  local post_host_args=("$@")
  local post_index=0
  res=("${og_args[@]::${host_index}}")

  # Process args that follow the hostname
  while [[ -n "$*" ]]
  do
    shift_index=$(__is_ssh_option "$1")

    # shellcheck disable=2181
    # Stop processing args if we hit a command
    if [[ "$?" -ne 0 ]]
    then
      break
    fi

    if [[ -n "$shift_index" ]]
    then
      # Add SSH option (+ arg) to the end of the res array. This will end up
      # *before* the hostname in what's printed to stdout at the end.
      res+=("${post_host_args[@]:${post_index}:$(( post_index + shift_index ))}")
      post_index=$(( post_index + shift_index ))
      shift "$shift_index"
    fi
  done

  # Echo result back and append host
  if [[ -n "${res[*]}" ]]
  then
    echo "${res[*]} ${og_args[${host_index}]}"
  fi
}

extract_ssh_host() {
  # Re-set the args in case the whole command is passed through "$1"
  if [[ "$#" -eq 1 ]]
  then
    # shellcheck disable=2086
    set -- $1
  fi
  shift  # shift the commad (ssh)

  local shift_index

  while [[ -n "$*" ]]
  do
    shift_index=$(__is_ssh_option "$1")
    # shellcheck disable=2181
    if [[ "$?" -ne 0 ]]
    then
      break
    fi

    if [[ -n "$shift_index" ]]
    then
      shift "$shift_index"
    fi
  done

  if [[ -n "$1" ]]
  then
    echo "$1"
    return
  fi

  return 1
}

get_child_cmds() {
  local pid="$1"

  # macOS
  if [[ "$(uname -s)" == "Darwin" ]]
  then
    # Untested, contributed by @liuruibin
    # https://github.com/pschmitt/tmux-ssh-split/pull/6
    ps -o pid=,ppid=,command= | grep --color=never "${pid}" | \
      awk '{$1="";$2="";print $0}'
    return "$?"
  fi

  # Linux
  ps -o command= -g "${pid}"
}

# $1 is optional, disable 2120
# shellcheck disable=2120
get_ssh_command() {
  local child_cmd
  local pane_id
  local pane_pid

  pane_id="${1:-$(get_current_pane_id)}"
  pane_pid="$(get_pane_pid_from_pane_id "$pane_id")"

  if [[ -z "$pane_pid" ]]
  then
    echo "Could not determine pane PID" >&2
    return 3
  fi

  get_child_cmds "$pane_pid" | while read -r child_cmd
  do
    if [[ "$child_cmd" =~ ^(auto)?ssh ]]
    then
      # Filter out "ssh -W"
      if ! grep -qE "ssh.*\s+-W\s+" <<< "$child_cmd"
      then
        echo "$child_cmd"
        return
      fi
    fi
  done

  return 1
}

get_remote_cwd() {
  # PROBABLY WON'T EVER WORK
  # To get the current paths on the remote server one can run the following:
  # 1. In the SSH session, grab the TTY:
  #   $ echo ${SSH_TTY#/dev/}
  # 2. To get the CWD:
  #   $ readlink -f /proc/$(ps -o pid= -t $SSH_TTY_FROM_ABOVE | head -1)/cwd

  # Alternative:
  # for pid in $(pgrep -P "$(pgrep -a sshd | grep -- "${SSH_TTY##/dev/}" | awk '{ print $1; exit }')"); do readlink -f /proc/$pid/cwd; done

  echo "Not implemented yet!" >&2
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  SPLIT_ARGS=(-e "TMUX_SSH_SPLIT=1")

  while [[ -n "$*" ]]
  do
    case "$1" in
      help|h|--help)
        usage
        exit 0
        ;;
      -h|-v)
        SPLIT_ARGS+=("$1")
        shift
        ;;
      -c)
        if [[ -z "$2" ]]
        then
          echo "Missing start directory" >&2
          usage >&2
          exit 2
        fi
        # Only set start dir if it still exists
        if [[ -d "$2" ]]
        then
          SPLIT_ARGS+=(-c "$2")
        fi
        shift 2
        ;;
      --fail)
        FAIL=1
        shift
        ;;
      --no-shell|-n)
        NO_SHELL=1
        shift
        ;;
      --verbose|-V)
        VERBOSE=1
        shift
        ;;
      --strip-cmd|--strip|-s)
        STRIP_CMD=1
        shift
        ;;
      -*)
        usage >&2
        exit 2
        ;;
    esac
  done

  ssh_command="$(get_ssh_command)"
  if [[ -n "$STRIP_CMD" ]]
  then
    ssh_command="$(strip_command "$ssh_command")"
  fi

  if [[ -z "$ssh_command" ]]
  then
    if [[ -n "$FAIL" ]]
    then
      tmux display "Error: current pane seems to not be running SSH..."
      echo "Could not determine SSH command" >&2
    else
      tmux split "${SPLIT_ARGS[@]}"
    fi
    exit 0
  fi

  start_cmd="$ssh_command"

  if [[ -z "$NO_SHELL" ]]
  then
    default_shell="$(tmux show-option -gqv "default-shell")"

    if [[ -z "$default_shell" ]]
    then
      # Fall back to sh
      default_shell="$(command -v sh)"
    fi

    # Open default shell on exit (SSH timeout, Ctrl-C etc.)
    start_cmd="trap 'TMUX_SSH_SPLIT=1 ${default_shell}' EXIT INT; $start_cmd"
  fi

  if [[ -n "$VERBOSE" ]]
  then
    start_cmd="echo '🧙👉 Running \"$ssh_command\"'; $start_cmd"
  fi

  # Spawn a new shell after the ssh command to keep the pane alive
  tmux split "${SPLIT_ARGS[@]}" "$start_cmd"
fi

# vim: set ft=bash et ts=2 sw=2 :
