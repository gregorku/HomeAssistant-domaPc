#!/usr/bin/env bash
# sourced by scripts/lib loaders
check_environment() {
    require_root
    require_command git
    require_command rsync
    ok "Environment OK."
}
