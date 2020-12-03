#!/usr/bin/env bash

get_tmux_option() {
  local option="$1"
  local default_value="$2"
  local raw_value

  raw_value=$(tmux show-option -gqv "$option")

  echo "${raw_value:-$default_value}"
}

main() {
  local -a extra_args
  local fail
  local hkey
  local noshell
  local swd
  local verbose
  local vkey

  keep_cwd="$(get_tmux_option @ssh-split-keep-cwd)"
  fail="$(get_tmux_option @ssh-split-fail)"
  hkey="$(get_tmux_option @ssh-split-h-key)"
  stripcmd="$(get_tmux_option @ssh-split-strip-cmd)"
  noshell="$(get_tmux_option @ssh-split-no-shell)"
  verbose="$(get_tmux_option @ssh-split-verbose)"
  vkey="$(get_tmux_option @ssh-split-v-key)"

  case "$keep_cwd" in
    true|1|yes)
      # Double quote path since it may contain spaces.
      # Especially when the current dir gets deleted, tmux then
      # appends " (removed)"
      extra_args+=(-c "'#{pane_current_path}'")
      ;;
  esac

  case "$fail" in
    true|1|yes)
      extra_args+=(--fail)
      ;;
  esac

  case "$noshell" in
    true|1|yes)
      extra_args+=(--no-shell)
      ;;
  esac

  case "$stripcmd" in
    true|1|yes)
      extra_args+=(--strip-cmd)
      ;;
  esac

  case "$verbose" in
    true|1|yes)
      extra_args+=(--verbose)
      ;;
  esac

  current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  script_path="${current_dir}/scripts/tmux-ssh-split.sh"

  if [[ -n "$hkey" ]]
  then
    tmux unbind "$hkey"
    tmux bind-key "$hkey" run "${script_path} ${extra_args[*]} -h"
  fi

  if [[ -n "$vkey" ]]
  then
    tmux unbind "$vkey"
    tmux bind-key "$vkey" run "${script_path} ${extra_args[*]} -v"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main
fi

# vim: set ft=bash et ts=2 sw=2 :
