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

strip_command() {
  # Re-set the args in case the whole command is passed through "$1"
  if [[ "$#" -eq 1 ]]
  then
    # shellcheck disable=2086
    set -- $1
  fi

  local ssh_host
  ssh_host=$(extract_ssh_host "$@")

  sed -nr "s/(.*${ssh_host}).*/\1/p" <<< "$*"
}

extract_ssh_host() {
  # Re-set the args in case the whole command is passed through "$1"
  if [[ "$#" -eq 1 ]]
  then
    # shellcheck disable=2086
    set -- $1
  fi
  shift  # shift the commad (ssh)

  while [[ -n "$*" ]]
  do
    case "$1" in
      # Optionless flags (can be combined - hence the "*"
      -4*|-6*|-A*|-a*|-C*|-f*|-G*|-g*|-K*|-k*|-M*|-N*|-n*|-q*|-s*|-T*|-t*|-v*|-V*|-X*|-x*|-Y*|-y*)
        shift
        ;;
      # Flags with options
      -B|-b|-c|-D|-E|-e|-F|-I|-i|-J|-L|-l|-m|-O|-o|-p|-Q|-R|-S|-W|-w)
        shift 2
        ;;
      # Unknown flags
      -*)
        echo "Unknown flag: $1" >&2
        shift
        return 9
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ -n "$1" ]]
  then
    echo "$1"
    return
  fi

  return 1
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

  ps -o command= -g "${pane_pid}" | while read -r child_cmd
  do
    if [[ "$child_cmd" =~ ^(auto)?ssh ]]
    then
      # Filter out "ssh -W"
      if ! grep -qE "ssh\s+-W" <<< "$child_cmd"
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
  SPLIT_ARGS=()

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
    start_cmd="trap ${default_shell} EXIT INT; $start_cmd"
  fi

  if [[ -n "$VERBOSE" ]]
  then
    start_cmd="echo '🧙👉 Running \"$ssh_command\"'; $start_cmd"
  fi

  # Spawn a new shell after the ssh command to keep the pane alive
  tmux split "${SPLIT_ARGS[@]}" "$start_cmd"
fi

# vim: set ft=bash et ts=2 sw=2 :
