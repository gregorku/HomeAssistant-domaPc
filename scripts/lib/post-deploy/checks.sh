#!/usr/bin/env bash
# sourced by scripts/lib loaders
post_deploy_check_database() {
    print_section "PostgreSQL"
    docker exec \
        -e PGPASSWORD="${RUNTIME_ENV[PG_PASS]}" \
        -e PGAPP_USER="${RUNTIME_ENV[PG_USER]}" \
        -e PGAPP_DB="${RUNTIME_ENV[PG_DB]}" \
        "${POSTGRESQL_CONTAINER}" \
        sh -c 'exec psql -v ON_ERROR_STOP=1 -q -h "$(hostname)" -U "$PGAPP_USER" -d "$PGAPP_DB" -c "SELECT 1"' \
        >/dev/null \
        || fail "Application role could not log in."
    ok "PostgreSQL accepts the application role."
}

post_deploy_mqtt_login() {
    local user="$1" password="$2" label="$3"
    # The password is stdin of docker exec. The shell does not export it.
    # mosquitto_pub reads it from a mode 0600 options file, not from argv.
    docker exec -i \
        -e MQTT_USER="${user}" \
        "${MOSQUITTO_CONTAINER}" \
        sh -c 'set -eu
umask 077
IFS= read -r MQTT_PASSWORD || exit 1
options=$(mktemp)
cleanup() {
    rm -f "$options"
}
trap cleanup EXIT
trap '"'"'exit 129'"'"' HUP
trap '"'"'exit 130'"'"' INT
trap '"'"'exit 143'"'"' TERM
chmod 600 "$options"
{
    printf "%s\n" "-h 127.0.0.1"
    printf "%s\n" "-p 1883"
    printf "%s\n" "-u ${MQTT_USER}"
    printf "%s\n" "-P ${MQTT_PASSWORD}"
    printf "%s\n" "-t ha/health"
    printf "%s\n" "-m up"
} > "$options"
mosquitto_pub -o "$options"' \
        <<< "${password}" \
        >/dev/null \
        || fail "${label} MQTT login failed."
}

post_deploy_mqtt_account_present() {
    local user="$1" label="$2"
    docker exec \
        -e MQTT_USER="${user}" \
        "${MOSQUITTO_CONTAINER}" \
        sh -c 'grep -q "^${MQTT_USER}:" /mosquitto/config/auth/passwd' \
        >/dev/null \
        || fail "${label} is missing from the Mosquitto password file."
}

post_deploy_check_ha_mqtt_secrets() {
    local secrets="${RUNTIME_ENV[HA_CONFIG_HOST_DIR]}/secrets.yaml"
    local secrets_body line user_line pass_line found_user=0 found_pass=0
    [[ -f "${secrets}" ]] || fail "Home Assistant secrets.yaml is missing."
    [[ "$(stat -c '%a' "${secrets}")" == 600 ]] || fail "Home Assistant secrets.yaml is not mode 600."
    user_line="mqtt_ha_user: $(yaml_double "${RUNTIME_ENV[MQTT_HA_USER]}")"
    pass_line="mqtt_ha_password: $(yaml_double "${RUNTIME_ENV[MQTT_HA_PASSWORD]}")"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" == "${user_line}" ]] && found_user=1
        [[ "${line}" == "${pass_line}" ]] && found_pass=1
    done < "${secrets}"
    [[ "${found_user}" == 1 ]] || fail "Home Assistant secrets do not contain the Home Assistant MQTT user."
    [[ "${found_pass}" == 1 ]] || fail "Home Assistant secrets do not contain the Home Assistant MQTT password."
    secrets_body="$(<"${secrets}")"
    [[ "${secrets_body}" != *"${RUNTIME_ENV[MQTT_PASSWORD]}"* ]] || fail "Home Assistant secrets contain the Zigbee2MQTT password."
}

post_deploy_check_mqtt() {
    print_section "MQTT"
    local running
    running="$(docker inspect -f '{{.State.Running}}' "${MOSQUITTO_CONTAINER}" 2>/dev/null || true)"
    [[ "${running}" == true ]] || fail "Mosquitto is not running."
    ok "Mosquitto is running."
    post_deploy_mqtt_account_present "${RUNTIME_ENV[MQTT_USER]}" "Zigbee2MQTT account"
    post_deploy_mqtt_account_present "${RUNTIME_ENV[MQTT_HA_USER]}" "Home Assistant account"
    post_deploy_mqtt_login "${RUNTIME_ENV[MQTT_USER]}" "${RUNTIME_ENV[MQTT_PASSWORD]}" "Zigbee2MQTT"
    post_deploy_mqtt_login "${RUNTIME_ENV[MQTT_HA_USER]}" "${RUNTIME_ENV[MQTT_HA_PASSWORD]}" "Home Assistant"
    ok "MQTT accepts the Zigbee2MQTT account."
    ok "MQTT accepts the Home Assistant account."
    post_deploy_check_ha_mqtt_secrets
    ok "Home Assistant MQTT credentials are available for the UI integration."
}

post_deploy_check_homeassistant() {
    print_section "Home Assistant"
    local i
    for ((i = 1; i <= 18; i++)); do
        if docker exec "${HA_CONTAINER}" \
            python -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8123/", timeout=20)' \
            >/dev/null 2>&1; then
            ok "Home Assistant answered on port 8123."
            return 0
        fi
        if (( i < 18 )); then
            sleep 10
        fi
    done
    fail "Home Assistant did not answer on port 8123."
}

post_deploy_check_zigbee2mqtt() {
    print_section "Zigbee2MQTT"
    docker exec -i \
        -e EXPECTED_USER="${RUNTIME_ENV[MQTT_USER]}" \
        -e OTHER_USER="${RUNTIME_ENV[MQTT_HA_USER]}" \
        "${ZIGBEE2MQTT_CONTAINER}" \
        sh -c 'IFS= read -r EXPECTED_PASSWORD; [ "$ZIGBEE2MQTT_CONFIG_MQTT_USER" = "$EXPECTED_USER" ] && [ "$ZIGBEE2MQTT_CONFIG_MQTT_USER" != "$OTHER_USER" ] && [ "$ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD" = "$EXPECTED_PASSWORD" ]' \
        <<< "${RUNTIME_ENV[MQTT_PASSWORD]}" \
        >/dev/null \
        || fail "Zigbee2MQTT is not using its own MQTT account."
    ok "Zigbee2MQTT is using its own MQTT account."
    local i
    for ((i = 1; i <= 12; i++)); do
        if docker exec "${ZIGBEE2MQTT_CONTAINER}" \
            wget -q -O /dev/null "http://127.0.0.1:8080/" \
            >/dev/null 2>&1; then
            ok "Zigbee2MQTT answered on port 8080."
            return 0
        fi
        if (( i < 12 )); then
            sleep 5
        fi
    done
    fail "Zigbee2MQTT did not answer on port 8080."
}

post_deploy_check_esphome() {
    print_section "ESPHome"
    local i
    for ((i = 1; i <= 12; i++)); do
        if docker exec "${ESPHOME_CONTAINER}" \
            python3 -c 'import urllib.request
try:
    urllib.request.urlopen("http://127.0.0.1:6052/", timeout=10)
except Exception as exc:
    code = getattr(exc, "code", 0)
    if code in (200, 401, 403):
        raise SystemExit(0)
    raise SystemExit(1)' \
            >/dev/null 2>&1; then
            ok "ESPHome dashboard answered on port 6052."
            return 0
        fi
        if (( i < 12 )); then
            sleep 5
        fi
    done
    fail "ESPHome dashboard did not answer on port 6052."
}

post_deploy_check_wmbusmeters() {
    print_section "WMBusmeters"
    local running
    running="$(docker inspect -f '{{.State.Running}}' "${WMBUSMETERS_CONTAINER}" 2>/dev/null || true)"
    [[ "${running}" == true ]] || fail "WMBusmeters is not running."
    ok "WMBusmeters is running."
}

post_deploy_homeassistant_version() {
    local raw
    raw="$(docker exec "${HA_CONTAINER}" python -m homeassistant --version 2>/dev/null || true)"
    raw="${raw//[[:space:]]/}"
    if [[ "${raw}" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

post_deploy_record_version() {
    print_section "Installed version"
    local wanted="$1" reported
    reported="$(post_deploy_homeassistant_version)" \
        || fail "Home Assistant version could not be read. Installed-version was not written."
    [[ "${reported}" == "${wanted}" ]] || fail "Home Assistant reports ${reported}, not ${wanted}. Installed-version was not written."
    mkdir -p "${HA_STATE_DIR}"
    printf '%s\n' "${wanted}" > "${INSTALLED_VERSION_FILE}.tmp"
    mv "${INSTALLED_VERSION_FILE}.tmp" "${INSTALLED_VERSION_FILE}"
    ok "Recorded ${wanted}."
}
