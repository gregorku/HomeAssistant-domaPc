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

post_deploy_check_mqtt() {
    print_section "MQTT"
    docker exec \
        -e MQTT_USER="${RUNTIME_ENV[MQTT_USER]}" \
        -e MQTT_PASSWORD="${RUNTIME_ENV[MQTT_PASSWORD]}" \
        "${MOSQUITTO_CONTAINER}" \
        sh -c 'exec mosquitto_pub -h 127.0.0.1 -u "$MQTT_USER" -P "$MQTT_PASSWORD" -t ha/health -m up' \
        >/dev/null \
        || fail "MQTT login failed."
    ok "MQTT accepts the application user."
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
