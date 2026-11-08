#!/usr/bin/env bash
# sourced by scripts/lib loaders
declare -gA RUNTIME_ENV

env_load_runtime() {
    [[ -f "${ENV_FILE}" ]] || fail "Runtime .env is missing. Run ./scripts/update-env.sh."
    env_parse_file "${ENV_FILE}" RUNTIME_ENV
    local key
    for key in "${!ENV_POLICY[@]}"; do
        [[ -v RUNTIME_ENV["${key}"] ]] || fail "Missing variable: ${key}"
        if [[ -z "${RUNTIME_ENV[${key}]}" ]]; then
            case "${key}" in
                BACKUP_EXTERNAL_DIR|RESTIC_REPOSITORY|RESTIC_PASSWORD)
                    ;;
                *) fail "Empty variable: ${key}" ;;
            esac
        fi
        if env_is_placeholder "${RUNTIME_ENV[${key}]}"; then
            fail "Placeholder is not usable: ${key}"
        fi
    done
    env_validate_runtime RUNTIME_ENV
}
