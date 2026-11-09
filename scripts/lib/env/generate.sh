#!/usr/bin/env bash
# sourced by scripts/lib loaders
env_generate_secret() {
    local bytes="$1" value
    require_command openssl
    value="$(openssl rand -base64 "${bytes}" | tr -d '\n')"
    [[ -n "${value}" ]] || fail "openssl returned an empty secret."
    printf '%s\n' "${value}"
}

env_generate_secret_for() {
    case "$1" in
        PG_SUPER_PASS|PG_PASS|MQTT_PASSWORD|MQTT_HA_PASSWORD|ESPHOME_PASSWORD) env_generate_secret 36 ;;
        *) fail "No secret generator for $1." ;;
    esac
}
