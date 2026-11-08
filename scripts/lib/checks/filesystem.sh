#!/usr/bin/env bash
# sourced by scripts/lib loaders
require_mountpoint() {
    local path="$1"
    [[ -d "${path}" ]] || fail "${path} does not exist. This project does not create the Incus disk."
    findmnt -T "${path}" >/dev/null 2>&1 || fail "${path} is not a mount. Refusing to store data on the container root filesystem."
    local target
    target="$(findmnt -T "${path}" -n -o TARGET)"
    [[ "${target}" == "${path}" ]] || fail "${path} is not the mountpoint (findmnt reports ${target})."
}
