#!/usr/bin/env bash

require_root() {
    [[ "${EUID}" -eq 0 ]] || fail "This script must be run as root inside the Incus container."
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}
