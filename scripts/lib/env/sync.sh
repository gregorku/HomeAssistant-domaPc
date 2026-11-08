#!/usr/bin/env bash
# sourced by scripts/lib loaders
env_sync_file() {
    local example="$1" target="$2"
    [[ -f "${example}" ]] || fail "Missing ${example}"
    declare -A CURRENT=()
    if [[ -f "${target}" ]]; then
        env_parse_file "${target}" CURRENT
    fi
    local tmp line key value policy existing
    tmp="$(mktemp "${target}.tmp.XXXXXX")"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# || "${line}" != *=* ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        key="${line%%=*}"
        value="${line#*=}"
        policy="${ENV_POLICY[${key}]:-user}"
        existing="${CURRENT[${key}]:-}"
        case "${policy}" in
            framework) ;;
            user)
                if [[ -n "${existing}" ]]; then
                    value="${existing}"
                fi
                ;;
            generated)
                if [[ -n "${existing}" ]] && ! env_is_placeholder "${existing}"; then
                    value="${existing}"
                else
                    value="$(env_generate_secret_for "${key}")"
                fi
                ;;
        esac
        printf '%s=%s\n' "${key}" "${value}" >> "${tmp}"
    done < "${example}"
    env_install_private_file "${tmp}" "${target}"
}
