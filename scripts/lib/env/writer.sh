#!/usr/bin/env bash
# sourced by scripts/lib loaders
env_install_private_file() {
    local tmp="$1" target="$2"
    chmod 600 "${tmp}"
    if [[ -f "${target}" ]]; then
        cp -a "${target}" "${target}.bak-$(date +%Y%m%d-%H%M%S)"
        chmod 600 "${target}.bak-"* 2>/dev/null || true
    fi
    mv "${tmp}" "${target}"
    chmod 600 "${target}"
}
