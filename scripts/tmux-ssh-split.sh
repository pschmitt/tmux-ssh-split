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
    autossh|ssh|mosh)
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

is_ssh_command() {
  grep -qE '^[^ ]*(ssh|autossh) ' <<< "$1"
}

is_mosh_command() {
  grep -qE '^[^ ]*(mosh|mosh-client) ' <<< "$1"
}

is_ssh_or_mosh_command() {
  # Filter out invalid commands
  if ! command -v -- "$(cut -d' ' -f1 <<< "$1")" &>/dev/null
  then
    return 1
  fi

  # Filter out git/sftp commands
  if ! grep -vqE "git-(upload|receive|send)-pack|sftp" <<< "$1"
  then
    return 1
  fi

  is_ssh_command "$1" || is_mosh_command "$1"
}

strip_command() {
  # FIXME This won't work for commands like the followin:
  # ssh host.example.com -l root
  # It will remove the "-l root" part.

  # Return immediately if not processing an SSH command
  if ! is_ssh_command "$*"
  then
    return 1
  fi

  # Re-set the args in case the whole command is passed through "$1"
  if [[ "$#" -eq 1 ]]
  then
    # shellcheck disable=2086
    set -- $1
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

inject_ssh_env() {
  local cmd="$1"
  if is_ssh_command "$cmd"
  then
    # shellcheck disable=SC2001
    sed 's#ssh#ssh -o SendEnv=TMUX_SSH_SPLIT#' <<< "$cmd"
    return
  fi

  if is_mosh_command "$cmd"
  then
    # shellcheck disable=SC2001
    sed "s#mosh#mosh --ssh='ssh -o SendEnv=TMUX_SSH_SPLIT'#" <<< "$cmd"
    return
  fi
  return 1
}

inject_remote_cwd() {
  local ssh_command="$1"
  local ssh_cwd

  if ! ssh_cwd="$(get_remote_path)" || [[ -z "$ssh_cwd" ]]
  then
    echo "Failed to extract remote cwd from PS1" >&2
    echo "$ssh_command"
    return 0
  fi

  local remote_command=(
    "cd \"${ssh_cwd}\" 2>/dev/null"
  )

  local parent_cwd="${ssh_cwd%/*}"
  if [[ -n "$parent_cwd" ]]
  then
    remote_command+=("||")
    remote_command+=("cd \"${parent_cwd}\"")
  fi

  remote_command+=(
    ";"
    "exec \${SHELL:-/usr/bin/env sh} -l"
  )

  if is_mosh_command "$ssh_command"
  then
    ssh_command="$ssh_command -- sh -c '${remote_command[*]}'"
  else
    ssh_command="$ssh_command -t '${remote_command[*]}'"
  fi

  echo "$ssh_command"
}

extract_ssh_host() {
  # Re-set the args in case the whole command is passed through "$1"
  if [[ "$#" -eq 1 ]]
  then
    # shellcheck disable=2086
    set -- $1
  fi
  shift  # shift the command (ssh)

  local shift_index

  while [[ -n "$*" ]]
  do
    if ! shift_index=$(__is_ssh_option "$1")
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

# FIXME This might not be the most reliable host extraction
extract_mosh_host() {
  sed -nr 's/.*mosh-client -# ([^\s+])\s+.*/\1/p' <<< "$1"
}

get_child_cmds() {
  local pid="$1"

  # macOS
  if [[ "$(uname -s)" == "Darwin" ]]
  then
    # Untested, contributed by @liuruibin
    # https://github.com/pschmitt/tmux-ssh-split/pull/6
    # shellcheck disable=SC2009
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

  local host
  # For debugging you can set the pane PID manually here
  # to list tmux pane pids run: $ tmux list-panes -F '#{pane_pid}'
  # pane_pid="1722114"
  get_child_cmds "$pane_pid" | while read -r child_cmd
  do
    if ! is_ssh_or_mosh_command "$child_cmd"
    then
      continue
    fi
    # Filter out "ssh -W"
    if grep -qE "ssh.*\s+-W\s+" <<< "$child_cmd"
    then
      continue
    fi
    # mosh is a special case, the child command will look like this:
    # mosh-client -# hostname | 192.168.69.42 60001
    if is_mosh_command "$child_cmd"
    then
      host="$(extract_mosh_host "$child_cmd")"

      if [[ -z "$host" ]]
      then
        echo "Could not extract hostname from mosh command: $child_cmd" >&2
        continue
      fi

      child_cmd="LC_ALL=${LC_ALL:-en_US.UTF-8} mosh $host"
    fi

    echo "$child_cmd"
    return
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

guess_remote_shell() {
  if [[ "$#" -eq 1 ]]
  then
    # shellcheck disable=2086
    set -- $1
  fi

  is_ssh_or_mosh_command "$@" && shift
  ssh "$@" 'echo $SHELL'
}

# Below requires vte shell integration aka osc7
get_pane_path_osc7() {
  # pane_path returns "file://myhost/home/pschmitt" where myhost is the
  # hostname and the rest the path
  local data
  data="$(tmux display -pF '#{pane_path}')"
  local local_host="${HOSTNAME:-$(hostname)}"

  local host path
  read -r host path <<< "$(sed -nr 's#file://([^/]*)(/.*)#\1 \2#p' <<< "$data")"

  # Only return the path if the host is not the local one
  # This is to avoid returning the local path when the remote shell does
  # not support OSC7
  if [[ "$host" == "$local_host" ]]
  then
    return 1
  fi

  echo "$path"
}

get_remote_path() {
  local remote_path
  remote_path="$(get_pane_path_osc7)"

  if [[ -n "$remote_path" ]]
  then
    echo "$remote_path"
    return 0
  fi

  # Fall back to ps1 extraction
  echo "Failed to determine remote path using OSC7, falling back to PS1 extraction" >&2
  extract_path_from_ps1
}

extract_path_from_ps1() {
  local line
  line=$(tmux capture-pane -p | sed '/^$/d' | tail -1)

  # Search for zsh hash dirs (eg: ~zsh/bin)
  local match
  if match=$(grep -m 1 -oP '~[^\s]+' <<< "$line")
  then
    # Remove trailing '$' or '#' (bash prompt char) and ']'
    # shellcheck disable=2001
    match=$(sed 's|[]$#/]*$||' <<< "${match}")

    # shellcheck disable=2088
    if [[ "$match" == '~' ]]
    then
      echo "Current dir seems to be '~', ignoring since it probably the default anyway" >&2
      return 0
    fi

    echo -n "$match"
    return 0
  fi

  # Search for paths
  if match=$(grep -m 1 -oP '/\K[^ ]*' <<< "$line")
  then
    # Add leading slash if missing
    [[ ! $match = /* ]] && match="/$match"
    # Remove trailing '$', '#' and ']'
    # Remove quotes (eg: ' or ")
    sed -e 's/[]$#]$//' -e "s#['\"]*##g" <<< "${match}"
    return
  fi

  echo "Failed to extract path from PS1" >&2
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  while [[ -n "$*" ]]
  do
    case "$1" in
      help|h|--help)
        usage
        exit 0
        ;;
      --debug|-D)
        DEBUG=1
        shift
        ;;
      -h|-v)
        SPLIT_ARGS+=("$1")
        shift
        ;;
      -w|--window)
        WINDOW=1
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
      --keep-remote-cwd)
        KEEP_REMOTE_CWD=1
        shift
        ;;
      --fail)
        FAIL=1
        shift
        ;;
      --no-shell|--noshell|-n)
        NO_SHELL=1
        shift
        ;;
      --no-env|--noenv)
        NO_ENV=1
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

  if [[ -n "$DEBUG" ]]
  then
    set -x

    # Write debug output to file if not running in a terminal
    if [[ ! -t 0 ]]
    then
      exec >> "${TMPDIR:-/tmp}/tmux-ssh-split.log"
      exec 2>&1
    fi
  fi

  if [[ -z "$NO_ENV" ]]
  then
    SPLIT_ARGS+=(-e "TMUX_SSH_SPLIT=1")
  fi

  SSH_COMMAND="$(get_ssh_command)"

  if [[ -z "$SSH_COMMAND" ]]
  then
    if [[ -n "$FAIL" ]]
    then
      tmux display "Error: current pane seems to not be running SSH..."
      echo "Could not determine SSH command" >&2
      exit 1
    fi

    if [[ -n "$WINDOW" ]]
    then
      # remove -h and -v from split args
      SPLIT_ARGS=("${SPLIT_ARGS[@]/-h}")
      SPLIT_ARGS=("${SPLIT_ARGS[@]/-v}")

      tmux new-window "${SPLIT_ARGS[@]}"
    else
      tmux split "${SPLIT_ARGS[@]}"
    fi

    exit 0
  fi

  if [[ -n "$STRIP_CMD" ]]
  then
    SSH_COMMAND_STRIPPED="$(strip_command "$SSH_COMMAND")"

    if [[ -z "$SSH_COMMAND_STRIPPED" ]]
    then
      echo "Could not strip command: $SSH_COMMAND" >&2
    else
      SSH_COMMAND="$SSH_COMMAND_STRIPPED"
    fi
  fi

  # Experimental
  if [[ -n "$KEEP_REMOTE_CWD" ]]
  then
    SSH_COMMAND="$(inject_remote_cwd "$SSH_COMMAND")"
  fi

  if [[ -z "$NO_ENV" ]]
  then
    # Inject -o SendEnv TMUX_SSH_SPLIT=1 into the SSH command
    SSH_COMMAND="$(inject_ssh_env "$SSH_COMMAND")"
  fi

  START_CMD="$SSH_COMMAND"

  if [[ -z "$NO_SHELL" ]]
  then
    DEFAULT_SHELL="$(tmux show-option -gqv "default-shell")"

    if [[ -z "$DEFAULT_SHELL" ]]
    then
      # Fall back to sh
      DEFAULT_SHELL="$(command -v sh)"
    fi

    # Open default shell on exit (SSH timeout, Ctrl-C etc.)
    START_CMD="trap '${DEFAULT_SHELL}' EXIT INT; ${START_CMD}"
  fi

  if [[ -n "$VERBOSE" ]]
  then
    # Escape single quotes in the command
    SSH_COMMAND_ESCAPED=${SSH_COMMAND//\'/\'\\\'\'}
    START_CMD="echo -e '🧙👉 Running \e[34;1m\$ ${SSH_COMMAND_ESCAPED}\e[0m'; ${START_CMD}"
  fi

  if [[ -n "$WINDOW" ]]
  then
    # remove -h and -v from split args
    SPLIT_ARGS=("${SPLIT_ARGS[@]/-h}")
    SPLIT_ARGS=("${SPLIT_ARGS[@]/-v}")

    tmux new-window "${SPLIT_ARGS[@]}" "$START_CMD"
  else
    tmux split "${SPLIT_ARGS[@]}" "$START_CMD"
  fi
fi

# vim: set ft=bash et ts=2 sw=2 :
