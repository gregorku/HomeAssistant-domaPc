#!/usr/bin/env bash
# sourced by scripts/lib loaders
yaml_quote() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

yaml_double() {
    printf '"%s"' "$(yaml_quote "$1")"
}

env_urlencode() {
    local LC_ALL=C
    local s="$1" i c
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        case "${c}" in
            [a-zA-Z0-9.~_-]) printf '%s' "${c}" ;;
            *) printf '%%%02X' "'${c}" ;;
        esac
    done
}

deploy_recorder_url() {
    local user pass db
    user="$(env_urlencode "${RUNTIME_ENV[PG_USER]}")"
    pass="$(env_urlencode "${RUNTIME_ENV[PG_PASS]}")"
    db="$(env_urlencode "${RUNTIME_ENV[PG_DB]}")"
    printf 'postgresql://%s:%s@postgresql:5432/%s' "${user}" "${pass}" "${db}"
}

deploy_render_secrets() {
    local dest="${RUNTIME_ENV[HA_CONFIG_HOST_DIR]}/secrets.yaml"
    local tmp url
    HA_SECRETS_CHANGED=0
    url="$(deploy_recorder_url)"
    tmp="$(mktemp "${RUNTIME_ENV[HA_CONFIG_HOST_DIR]}/secrets.yaml.tmp.XXXXXX")"
    chmod 600 "${tmp}"
    if [[ -f "${dest}" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            case "${line}" in
                recorder_db_url:*|mqtt_user:*|mqtt_password:*) continue ;;
            esac
            printf '%s\n' "${line}" >> "${tmp}"
        done < "${dest}"
    fi
    {
        printf 'recorder_db_url: %s\n' "$(yaml_double "${url}")"
        printf 'mqtt_user: %s\n' "$(yaml_double "${RUNTIME_ENV[MQTT_USER]}")"
        printf 'mqtt_password: %s\n' "$(yaml_double "${RUNTIME_ENV[MQTT_PASSWORD]}")"
    } >> "${tmp}"
    if [[ -f "${dest}" ]] && cmp -s "${tmp}" "${dest}"; then
        rm -f "${tmp}"
        return 0
    fi
    if [[ -f "${dest}" ]]; then
        HA_SECRETS_CHANGED=1
    fi
    mv "${tmp}" "${dest}"
    chmod 600 "${dest}"
}

deploy_render_runtime() {
    print_section "Render runtime files"
    deploy_render_secrets
    ok "Runtime secrets rendered. No proxy configuration was written."
}
