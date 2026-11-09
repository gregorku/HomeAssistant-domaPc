#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

fail_static() { printf 'static check failed: %s\n' "$1" >&2; exit 1; }

static_checks() {
    local script
    while IFS= read -r script; do
        bash -n "${script}" || fail_static "bash -n ${script}"
    done < <(find "${REPO_ROOT}/scripts" -name '*.sh' -type f)

    local required=(
        scripts/init.sh
        scripts/update-env.sh
        scripts/check-env.sh
        scripts/deploy.sh
        scripts/post-deploy.sh
        scripts/upgrade.sh
        scripts/backup.sh
        scripts/restore.sh
        scripts/reload.sh
        scripts/test.sh
        scripts/config.sh
        scripts/lib/logging.sh
        scripts/lib/common.sh
        scripts/lib/env/load.sh
        scripts/lib/deploy/load.sh
        scripts/lib/checks/load.sh
        scripts/lib/init/load.sh
        scripts/lib/post-deploy/checks.sh
        scripts/lib/backup/archive.sh
        scripts/migrate-postgres.sh
        compose.yml
        compose/30-homeassistant.yml
        compose/40-postgresql.yml
        compose/50-mosquitto.yml
        compose/60-zigbee2mqtt.yml
        compose/70-esphome.yml
        compose/80-wmbusmeters.yml
        .env.example
        .gitignore
    )
    local path
    for path in "${required[@]}"; do
        [[ -f "${REPO_ROOT}/${path}" ]] || fail_static "missing ${path}"
    done

    if grep -R -n -E 'traefik|crowdsec|metabase|authentik|acme|letsencrypt|serveftp\.net' \
        "${REPO_ROOT}/compose" "${REPO_ROOT}/configs" "${REPO_ROOT}/.env.example"; then
        fail_static "a VPS-only or old-domain name is in the application stack"
    fi
    if grep -R -n --exclude test.sh -E 'image:.*traefik|image:.*crowdsec|ha-proxy|TRAEFIK_|CROWDSEC_' \
        "${REPO_ROOT}/scripts" "${REPO_ROOT}/compose"; then
        fail_static "a removed proxy service is still installed by a script"
    fi
    if grep -R -nE '5432:' "${REPO_ROOT}/compose"; then
        fail_static "PostgreSQL publishes a host port"
    fi
    grep -q 'readonly HA_DOMAIN="homeassistant.serveftp.org"' "${REPO_ROOT}/scripts/config.sh" \
        || fail_static "HA_DOMAIN is not homeassistant.serveftp.org"
    grep -q '^HA_DOMAIN=homeassistant.serveftp.org$' "${REPO_ROOT}/.env.example" \
        || fail_static "HA_DOMAIN in .env.example is not homeassistant.serveftp.org"
    grep -q 'external_url: https://homeassistant.serveftp.org' "${REPO_ROOT}/configs/homeassistant/configuration.yaml" \
        || fail_static "Home Assistant external_url is not homeassistant.serveftp.org"
    grep -q -- '- "8123:8123"' "${REPO_ROOT}/compose/30-homeassistant.yml" \
        || fail_static "Home Assistant port 8123 is not published on the container"
    grep -q -- '- "8080:8080"' "${REPO_ROOT}/compose/60-zigbee2mqtt.yml" \
        || fail_static "Zigbee2MQTT port 8080 is not published on the container"
    grep -q -- '- "1883:1883"' "${REPO_ROOT}/compose/50-mosquitto.yml" \
        || fail_static "Mosquitto port 1883 is not published for LAN devices"
    grep -q 'network_mode: host' "${REPO_ROOT}/compose/70-esphome.yml" \
        || fail_static "ESPHome is not on the container host network"
    grep -q '/dev/ttyUSB0:/dev/ttyUSB0' "${REPO_ROOT}/compose/70-esphome.yml" \
        && grep -q '/dev/ttyUSB3:/dev/ttyUSB3' "${REPO_ROOT}/compose/70-esphome.yml" \
        || fail_static "ESPHome is missing one of the four USB serial ports"
    grep -q 'usb-SMLIGHT_SMLIGHT_SLZB-07Mg24_' "${REPO_ROOT}/compose/60-zigbee2mqtt.yml" \
        || fail_static "the SMLIGHT SLZB-07Mg24 device is missing"
    grep -q 'wmbus/lilygo/telegram' "${REPO_ROOT}/configs/wmbusmeters/mqtt_subscribe.sh" \
        || fail_static "WMBusmeters no longer reads the LilyGO telegram topic"
    grep -q 'Apator04799531' "${REPO_ROOT}/configs/wmbusmeters/entrypoint.sh" \
        && grep -q 'Apator04806798' "${REPO_ROOT}/configs/wmbusmeters/entrypoint.sh" \
        || fail_static "the original Apator meters are missing"
    if grep -R -n -E '10\.110\.100\.100|8452' \
        "${REPO_ROOT}/compose" "${REPO_ROOT}/configs" "${REPO_ROOT}/scripts" \
        "${REPO_ROOT}/docs" "${REPO_ROOT}/README.md" "${REPO_ROOT}/.env.example" \
        --exclude infrastructure-netcup.diff --exclude test.sh; then
        fail_static "an old host address or Zigbee port 8452 is still present"
    fi
    grep -q 'privileged: true' "${REPO_ROOT}/compose/70-esphome.yml" \
        && fail_static "ESPHome is still privileged"
    grep -q 'internal_url:' "${REPO_ROOT}/configs/homeassistant/configuration.yaml" \
        && fail_static "internal_url is set without a verified LAN address"
    local mqtt_entrypoint="${REPO_ROOT}/configs/mosquitto/entrypoint.sh"
    sh -n "${mqtt_entrypoint}" || fail_static "sh -n mosquitto entrypoint"
    if grep -q 'mosquitto_passwd -b' "${mqtt_entrypoint}"; then
        fail_static "Mosquitto still receives the password as a process argument"
    fi
    if grep -q 'mosquitto_passwd -c' "${mqtt_entrypoint}"; then
        fail_static "Mosquitto entrypoint uses mosquitto_passwd -c"
    fi
    grep -q 'mosquitto_passwd -U "${plain}"' "${mqtt_entrypoint}" \
        || fail_static "Mosquitto password is not hashed from a protected temporary file"
    grep -q 'awk -F: -v user="${user}"' "${mqtt_entrypoint}" \
        || fail_static "Mosquitto entrypoint does not preserve other password-file users"
    grep -q 'managed_user_present' "${mqtt_entrypoint}" \
        || fail_static "Mosquitto entrypoint does not check the managed account"
    grep -q 'MQTT_HA_USER' "${mqtt_entrypoint}" \
        && grep -q 'MQTT_HA_PASSWORD' "${mqtt_entrypoint}" \
        && grep -q 'passwd.ha.sha256' "${mqtt_entrypoint}" \
        || fail_static "Mosquitto entrypoint does not track the Home Assistant account separately"
    grep -q 'passwd.sha256' "${mqtt_entrypoint}" \
        || fail_static "Mosquitto entrypoint dropped the existing Zigbee2MQTT checksum"
    if grep -Fq ' > "${passwd_file}"' "${mqtt_entrypoint}"; then
        fail_static "Mosquitto entrypoint overwrites the complete password file"
    fi
    if grep -q '^mqtt:' "${REPO_ROOT}/configs/homeassistant/configuration.yaml"; then
        fail_static "Home Assistant still has the removed MQTT YAML broker block"
    fi
    grep -q 'MQTT_HA_USER: ${MQTT_HA_USER}' "${REPO_ROOT}/compose/50-mosquitto.yml" \
        && grep -q 'MQTT_HA_PASSWORD: ${MQTT_HA_PASSWORD}' "${REPO_ROOT}/compose/50-mosquitto.yml" \
        || fail_static "Mosquitto does not receive the Home Assistant account"
    grep -q 'ZIGBEE2MQTT_CONFIG_MQTT_USER: ${MQTT_USER}' "${REPO_ROOT}/compose/60-zigbee2mqtt.yml" \
        && grep -q 'ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD: ${MQTT_PASSWORD}' "${REPO_ROOT}/compose/60-zigbee2mqtt.yml" \
        || fail_static "Zigbee2MQTT no longer uses MQTT_USER and MQTT_PASSWORD"
    if grep -q 'MQTT_HA_' "${REPO_ROOT}/compose/60-zigbee2mqtt.yml"; then
        fail_static "Zigbee2MQTT received the Home Assistant MQTT account"
    fi
    grep -q 'mqtt_ha_password' "${REPO_ROOT}/scripts/lib/deploy/render.sh" \
        || fail_static "Home Assistant secrets do not receive the Home Assistant MQTT password"
    if grep -q 'MQTT_PASSWORD' "${REPO_ROOT}/scripts/lib/deploy/render.sh"; then
        fail_static "Home Assistant secrets still receive the Zigbee2MQTT password"
    fi
    grep -q 'PG_SUPER_PASS' "${REPO_ROOT}/compose/40-postgresql.yml" \
        || fail_static "PostgreSQL superuser password is not separate"
    grep -q '^\.env$' "${REPO_ROOT}/.gitignore" || fail_static ".env is not ignored"
    grep -q '^set_postgres_password$' <(sed -n 's/^PG_PASS=//p' "${REPO_ROOT}/.env.example") \
        || fail_static "PG_PASS example is not a placeholder"
    grep -q '^set_mqtt_password$' <(sed -n 's/^MQTT_PASSWORD=//p' "${REPO_ROOT}/.env.example") \
        || fail_static "MQTT_PASSWORD example is not a placeholder"
    grep -q '^Zigbee2mqtt_domaPc$' <(sed -n 's/^MQTT_USER=//p' "${REPO_ROOT}/.env.example") \
        || fail_static "MQTT_USER example is not Zigbee2mqtt_domaPc"
    grep -q '^homeassistant$' <(sed -n 's/^MQTT_HA_USER=//p' "${REPO_ROOT}/.env.example") \
        || fail_static "MQTT_HA_USER example is not homeassistant"
    grep -q '^set_mqtt_ha_password$' <(sed -n 's/^MQTT_HA_PASSWORD=//p' "${REPO_ROOT}/.env.example") \
        || fail_static "MQTT_HA_PASSWORD example is not a placeholder"
    grep -q '^set_esphome_password$' <(sed -n 's/^ESPHOME_PASSWORD=//p' "${REPO_ROOT}/.env.example") \
        || fail_static "ESPHOME_PASSWORD example is not a placeholder"
    [[ ! -f "${REPO_ROOT}/.env" ]] || fail_static "a runtime .env is inside the Git checkout"

    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/lib/common.sh"
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/lib/env/load.sh"
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/lib/deploy/load.sh"
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/lib/backup/archive.sh"

    check_env_sync_preserves_secrets
    check_mosquitto_accounts
    check_ha_mqtt_secret_render
    check_post_deploy_mqtt_login_secret
    check_wmbus_script_deploy
    check_mqtt_client_option_files
    check_network_rules
    check_deploy_database_order
    check_archive_roundtrip
    ok "Static checks passed. Containers were not started."
}

check_archive_roundtrip() {
    local stage archive work tree
    stage="$(mktemp -d)"
    archive="$(mktemp)"
    work="$(mktemp -d)"
    mkdir -p "${stage}/postgresql" "${stage}/homeassistant" "${stage}/mosquitto" \
        "${stage}/zigbee2mqtt" "${stage}/esphome" "${stage}/wmbusmeters"
    printf 'PGDMP' > "${stage}/postgresql/homeassistant.dump"
    printf 'config\n' > "${stage}/homeassistant/configuration.yaml"
    printf 'auth\n' > "${stage}/mosquitto/passwd"
    printf 'zigbee\n' > "${stage}/zigbee2mqtt/database.db"
    printf 'esphome\n' > "${stage}/esphome/device.yaml"
    printf 'wmbus\n' > "${stage}/wmbusmeters/publish_mqtt.sh"
    backup_write_manifest "${stage}" "test" "postgres:18.6" "2026.11.0"
    backup_pack "${stage}" "${archive}"
    backup_verify_archive "${archive}" "${work}"
    cmp -s "${stage}/homeassistant/configuration.yaml" "${work}/homeassistant/configuration.yaml" \
        || fail_static "isolated archive extract changed Home Assistant config"
    rm -rf "${stage}" "${work}" "${archive}" "${archive}.sha256"
    ok "Archive checksum and isolated extract passed"
}

check_env_sync_preserves_secrets() {
    local dir example current first super mqtt ha_mqtt esp output again_mqtt again_ha
    dir="$(mktemp -d)"
    example="${REPO_ROOT}/.env.example"
    current="${dir}/runtime.env"
    output="${dir}/sync.out"
    env_sync_file "${example}" "${current}" > "${output}"
    super="$(sed -n 's/^PG_SUPER_PASS=//p' "${current}")"
    first="$(sed -n 's/^PG_PASS=//p' "${current}")"
    mqtt="$(sed -n 's/^MQTT_PASSWORD=//p' "${current}")"
    ha_mqtt="$(sed -n 's/^MQTT_HA_PASSWORD=//p' "${current}")"
    esp="$(sed -n 's/^ESPHOME_PASSWORD=//p' "${current}")"
    [[ "${#super}" -ge 16 && "${super}" != set_* ]] || fail_static "PG_SUPER_PASS was not generated"
    [[ "${#first}" -ge 16 && "${first}" != set_* ]] || fail_static "PG_PASS was not generated"
    [[ "${super}" != "${first}" ]] || fail_static "superuser and application passwords are the same"
    [[ -z "$(sed -n 's/^RESTIC_PASSWORD=//p' "${current}")" ]] || fail_static "RESTIC_PASSWORD was generated"
    [[ "${#mqtt}" -ge 16 && "${mqtt}" != set_* ]] || fail_static "MQTT_PASSWORD was not generated"
    [[ "${#ha_mqtt}" -ge 16 && "${ha_mqtt}" != set_* ]] || fail_static "MQTT_HA_PASSWORD was not generated"
    [[ "${mqtt}" != "${ha_mqtt}" ]] || fail_static "the two MQTT passwords were not generated separately"
    [[ "$(sed -n 's/^MQTT_USER=//p' "${current}")" == "Zigbee2mqtt_domaPc" ]] \
        || fail_static "MQTT_USER was not taken from the example"
    [[ "$(sed -n 's/^MQTT_HA_USER=//p' "${current}")" == "homeassistant" ]] \
        || fail_static "MQTT_HA_USER was not taken from the example"
    [[ "${#esp}" -ge 16 && "${esp}" != set_* ]] || fail_static "ESPHOME_PASSWORD was not generated"
    if grep -F -q -e "${super}" -e "${first}" -e "${mqtt}" -e "${ha_mqtt}" -e "${esp}" "${output}"; then
        fail_static "update of .env printed a generated secret"
    fi
    [[ "$(stat -c '%a' "${current}")" == 600 ]] || fail_static "runtime .env is not mode 600"
    env_sync_file "${example}" "${current}" > "${output}"
    again_mqtt="$(sed -n 's/^MQTT_PASSWORD=//p' "${current}")"
    again_ha="$(sed -n 's/^MQTT_HA_PASSWORD=//p' "${current}")"
    [[ "${again_mqtt}" == "${mqtt}" ]] || fail_static "repeated sync replaced MQTT_PASSWORD"
    [[ "${again_ha}" == "${ha_mqtt}" ]] || fail_static "repeated sync replaced MQTT_HA_PASSWORD"
    if grep -F -q -e "${mqtt}" -e "${ha_mqtt}" "${output}"; then
        fail_static "repeated sync printed an MQTT password"
    fi
    printf '%s\n' \
        'PG_PASS=kept-user-secret-value' \
        'MQTT_PASSWORD=kept-mqtt-secret-value' \
        'MQTT_HA_PASSWORD=kept-ha-mqtt-secret-value' \
        'HA_DOMAIN=old.example' > "${current}"
    env_sync_file "${example}" "${current}" > "${output}"
    grep -q '^PG_PASS=kept-user-secret-value$' "${current}" \
        || fail_static "sync replaced an existing database password"
    grep -q '^MQTT_PASSWORD=kept-mqtt-secret-value$' "${current}" \
        || fail_static "sync replaced an existing MQTT password"
    grep -q '^MQTT_HA_PASSWORD=kept-ha-mqtt-secret-value$' "${current}" \
        || fail_static "sync replaced an existing Home Assistant MQTT password"
    grep -q '^HA_DOMAIN=homeassistant.serveftp.org$' "${current}" \
        || fail_static "sync did not keep the framework domain"
    if grep -F -q -e 'kept-user-secret-value' -e 'kept-mqtt-secret-value' -e 'kept-ha-mqtt-secret-value' "${output}"; then
        fail_static "sync printed an existing secret"
    fi
    sed -i 's/^MQTT_PASSWORD=.*/MQTT_PASSWORD=changed-mqtt-secret-value/' "${current}"
    env_sync_file "${example}" "${current}" > "${output}"
    grep -q '^MQTT_PASSWORD=changed-mqtt-secret-value$' "${current}" \
        || fail_static "an intentional Zigbee2MQTT password change was not kept"
    grep -q '^MQTT_HA_PASSWORD=kept-ha-mqtt-secret-value$' "${current}" \
        || fail_static "changing MQTT_PASSWORD also changed MQTT_HA_PASSWORD"
    sed -i 's/^MQTT_HA_PASSWORD=.*/MQTT_HA_PASSWORD=changed-ha-mqtt-secret-value/' "${current}"
    env_sync_file "${example}" "${current}" > "${output}"
    grep -q '^MQTT_HA_PASSWORD=changed-ha-mqtt-secret-value$' "${current}" \
        || fail_static "an intentional Home Assistant MQTT password change was not kept"
    grep -q '^MQTT_PASSWORD=changed-mqtt-secret-value$' "${current}" \
        || fail_static "changing MQTT_HA_PASSWORD also changed MQTT_PASSWORD"
    rm -rf "${dir}"
    ok "Secret sync is idempotent and does not print passwords"
}

mqtt_test_fail() {
    printf 'mosquitto account check failed: %s\n' "$1" >&2
    exit 1
}

mqtt_test_prepare_fakes() {
    local bin="$1"
    mkdir -p "${bin}"
    cat > "${bin}/mosquitto_passwd" <<'EOF'
#!/bin/sh
printf '%s\n' "passwd $*" >> "${MQTT_ARGV_LOG:?}"
[ "${1:-}" = "-U" ] && [ -n "${2:-}" ] || exit 2
if [ "${MQTT_PASSWD_HOLD:-0}" = 1 ] && [ ! -e "${MQTT_PASSWD_HELD:?}" ]; then
    : > "${MQTT_PASSWD_HELD}"
    printf '%s %s\n' "${PPID}" "$2" > "${MQTT_PASSWD_READY:?}"
    read -r _ < "${MQTT_PASSWD_HOLD_FIFO:?}" || true
fi
file="$2"
line="$(cat "${file}")" || exit 1
user="${line%%:*}"
pass="${line#*:}"
if [ -n "${MQTT_FAIL_USER:-}" ] && [ "${user}" = "${MQTT_FAIL_USER}" ]; then
    exit 1
fi
hash="$(printf '%s' "${pass}" | sha256sum | awk '{print $1}')"
printf '%s:$test$%s\n' "${user}" "${hash}" > "${file}"
chmod 600 "${file}"
exit 0
EOF
    cat > "${bin}/mosquitto" <<'EOF'
#!/bin/sh
printf '%s\n' "broker $*" >> "${MQTT_ARGV_LOG:?}"
exit 0
EOF
    cat > "${bin}/chown" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod 755 "${bin}/mosquitto_passwd" "${bin}/mosquitto" "${bin}/chown"
}

mqtt_test_run() {
    local auth="$1"
    MQTT_ARGV_LOG="${auth}/argv.log" \
    MOSQUITTO_AUTH_DIR="${auth}" \
    MOSQUITTO_DATA_DIR="${auth}/data" \
    MOSQUITTO_LOG_DIR="${auth}/log" \
    MOSQUITTO_CONF="${auth}/mosquitto.conf" \
    PATH="${MQTT_FAKE_BIN}:${PATH}" \
        sh "${REPO_ROOT}/configs/mosquitto/entrypoint.sh"
}

mqtt_test_line() {
    local file="$1" user="$2"
    awk -F: -v user="${user}" '$1 == user { print }' "${file}"
}

check_mosquitto_accounts() {
    local root auth empty passwd zigbee_sum ha_sum extra zigbee_line ha_line \
        before_mtime before_zigbee_checksum before_ha_line before_extra \
        output status plain_left changed_sum
    root="$(mktemp -d)"
    MQTT_FAKE_BIN="${root}/bin"
    mqtt_test_prepare_fakes "${MQTT_FAKE_BIN}"
    auth="${root}/auth"
    mkdir -p "${auth}"
    passwd="${auth}/passwd"
    : > "${auth}/argv.log"
    export MQTT_USER="Zigbee2mqtt_domaPc"
    export MQTT_PASSWORD="zigbee-secret-value-1"
    export MQTT_HA_USER="homeassistant"
    export MQTT_HA_PASSWORD="ha-secret-value-0002"
    export MQTT_FAIL_USER=""
    zigbee_sum="$(printf '%s' "${MQTT_PASSWORD}" | sha256sum | awk '{print $1}')"
    ha_sum="$(printf '%s' "${MQTT_HA_PASSWORD}" | sha256sum | awk '{print $1}')"

    # First deployment creates both accounts and does not invent extra users.
    empty="${root}/empty-auth"
    mkdir -p "${empty}"
    : > "${empty}/argv.log"
    if output="$(mqtt_test_run "${empty}" 2>&1)"; then
        :
    else
        mqtt_test_fail "first deployment failed"
    fi
    [[ "$(mqtt_test_line "${empty}/passwd" Zigbee2mqtt_domaPc)" == "Zigbee2mqtt_domaPc:\$test\$${zigbee_sum}" ]] \
        || mqtt_test_fail "first deployment did not create the Zigbee2MQTT account"
    [[ "$(mqtt_test_line "${empty}/passwd" homeassistant)" == "homeassistant:\$test\$${ha_sum}" ]] \
        || mqtt_test_fail "first deployment did not create the Home Assistant account"
    [[ "$(awk 'NF { count++ } END { print count + 0 }' "${empty}/passwd")" == 2 ]] \
        || mqtt_test_fail "first deployment created an unexpected account"
    [[ "$(stat -c '%a' "${empty}/passwd")" == 600 ]] || mqtt_test_fail "first passwd is not mode 600"
    if [[ "${output}" == *"${MQTT_PASSWORD}"* || "${output}" == *"${MQTT_HA_PASSWORD}"* ]]; then
        mqtt_test_fail "entrypoint output contained a password"
    fi
    if [[ "$(cat "${empty}/argv.log")" == *"${MQTT_PASSWORD}"* || "$(cat "${empty}/argv.log")" == *"${MQTT_HA_PASSWORD}"* ]]; then
        mqtt_test_fail "a process argument contained a password"
    fi

    # Legacy file: Zigbee checksum matches, Home Assistant account is absent.
    printf '%s\n' 'manual:$manual$kept' 'Zigbee2mqtt_domaPc:$7$kept-zigbee' > "${passwd}"
    chmod 600 "${passwd}"
    printf '%s\n' "${zigbee_sum}" > "${auth}/passwd.sha256"
    chmod 600 "${auth}/passwd.sha256"
    before_mtime="$(stat -c '%y' "${auth}/passwd.sha256")"
    if output="$(mqtt_test_run "${auth}" 2>&1)"; then
        :
    else
        mqtt_test_fail "first account creation failed"
    fi
    extra="$(mqtt_test_line "${passwd}" manual)"
    zigbee_line="$(mqtt_test_line "${passwd}" Zigbee2mqtt_domaPc)"
    ha_line="$(mqtt_test_line "${passwd}" homeassistant)"
    [[ "${extra}" == 'manual:$manual$kept' ]] || mqtt_test_fail "creating the Home Assistant account removed another user"
    [[ "${zigbee_line}" == 'Zigbee2mqtt_domaPc:$7$kept-zigbee' ]] || mqtt_test_fail "an unchanged Zigbee2MQTT password was rewritten"
    [[ "${ha_line}" == "homeassistant:\$test\$${ha_sum}" ]] || mqtt_test_fail "the Home Assistant account was not created"
    [[ "$(stat -c '%y' "${auth}/passwd.sha256")" == "${before_mtime}" ]] \
        || mqtt_test_fail "creating the Home Assistant account rewrote the Zigbee2MQTT checksum"
    [[ "$(stat -c '%a' "${passwd}")" == 600 ]] || mqtt_test_fail "passwd is not mode 600"
    [[ "$(tr -d '[:space:]' < "${auth}/passwd.ha.sha256")" == "${ha_sum}" ]] \
        || mqtt_test_fail "Home Assistant checksum does not match its password"
    if [[ "${output}" == *"${MQTT_PASSWORD}"* || "${output}" == *"${MQTT_HA_PASSWORD}"* ]]; then
        mqtt_test_fail "entrypoint output contained a password"
    fi
    if [[ "$(cat "${auth}/argv.log")" == *"${MQTT_PASSWORD}"* || "$(cat "${auth}/argv.log")" == *"${MQTT_HA_PASSWORD}"* ]]; then
        mqtt_test_fail "a process argument contained a password"
    fi
    if grep '^passwd ' "${auth}/argv.log" | grep -Eq '(^| )-c|(^| )-b'; then
        mqtt_test_fail "mosquitto_passwd was invoked with -c or -b"
    fi

    # Restart with unchanged passwords keeps the password file.
    cp -a "${passwd}" "${root}/passwd.before"
    before_mtime="$(stat -c '%y' "${passwd}")"
    if mqtt_test_run "${auth}" >/dev/null 2>&1; then
        :
    else
        mqtt_test_fail "restart with unchanged passwords failed"
    fi
    cmp -s "${passwd}" "${root}/passwd.before" || mqtt_test_fail "unchanged passwords rewrote passwd"
    [[ "$(stat -c '%y' "${passwd}")" == "${before_mtime}" ]] \
        || mqtt_test_fail "unchanged passwords changed the passwd timestamp"

    # Changing only the Zigbee2MQTT password leaves the other lines alone.
    before_ha_line="$(mqtt_test_line "${passwd}" homeassistant)"
    before_extra="$(mqtt_test_line "${passwd}" manual)"
    before_mtime="$(stat -c '%y' "${auth}/passwd.ha.sha256")"
    export MQTT_PASSWORD="zigbee-secret-value-2"
    changed_sum="$(printf '%s' "${MQTT_PASSWORD}" | sha256sum | awk '{print $1}')"
    if mqtt_test_run "${auth}" >/dev/null 2>&1; then
        :
    else
        mqtt_test_fail "Zigbee2MQTT password update failed"
    fi
    [[ "$(mqtt_test_line "${passwd}" Zigbee2mqtt_domaPc)" == "Zigbee2mqtt_domaPc:\$test\$${changed_sum}" ]] \
        || mqtt_test_fail "Zigbee2MQTT password was not updated"
    [[ "$(mqtt_test_line "${passwd}" homeassistant)" == "${before_ha_line}" ]] \
        || mqtt_test_fail "Zigbee2MQTT password update changed the Home Assistant account"
    [[ "$(mqtt_test_line "${passwd}" manual)" == "${before_extra}" ]] \
        || mqtt_test_fail "Zigbee2MQTT password update removed another user"
    [[ "$(stat -c '%y' "${auth}/passwd.ha.sha256")" == "${before_mtime}" ]] \
        || mqtt_test_fail "Zigbee2MQTT password update rewrote the Home Assistant checksum"

    # Changing only the Home Assistant password leaves the Zigbee2MQTT line alone.
    before_zigbee_checksum="$(cat "${auth}/passwd.sha256")"
    zigbee_line="$(mqtt_test_line "${passwd}" Zigbee2mqtt_domaPc)"
    before_mtime="$(stat -c '%y' "${auth}/passwd.sha256")"
    export MQTT_HA_PASSWORD="ha-secret-value-0003"
    ha_sum="$(printf '%s' "${MQTT_HA_PASSWORD}" | sha256sum | awk '{print $1}')"
    if mqtt_test_run "${auth}" >/dev/null 2>&1; then
        :
    else
        mqtt_test_fail "Home Assistant password update failed"
    fi
    [[ "$(mqtt_test_line "${passwd}" homeassistant)" == "homeassistant:\$test\$${ha_sum}" ]] \
        || mqtt_test_fail "Home Assistant password was not updated"
    [[ "$(mqtt_test_line "${passwd}" Zigbee2mqtt_domaPc)" == "${zigbee_line}" ]] \
        || mqtt_test_fail "Home Assistant password update changed the Zigbee2MQTT account"
    [[ "$(mqtt_test_line "${passwd}" manual)" == "${before_extra}" ]] \
        || mqtt_test_fail "Home Assistant password update removed another user"
    [[ "$(cat "${auth}/passwd.sha256")" == "${before_zigbee_checksum}" ]] \
        || mqtt_test_fail "Home Assistant password update changed the Zigbee2MQTT checksum"
    [[ "$(stat -c '%y' "${auth}/passwd.sha256")" == "${before_mtime}" ]] \
        || mqtt_test_fail "Home Assistant password update rewrote the Zigbee2MQTT checksum"

    # Both passwords can change without dropping the manual account.
    export MQTT_PASSWORD="zigbee-secret-value-4"
    export MQTT_HA_PASSWORD="ha-secret-value-0004"
    zigbee_sum="$(printf '%s' "${MQTT_PASSWORD}" | sha256sum | awk '{print $1}')"
    ha_sum="$(printf '%s' "${MQTT_HA_PASSWORD}" | sha256sum | awk '{print $1}')"
    if mqtt_test_run "${auth}" >/dev/null 2>&1; then
        :
    else
        mqtt_test_fail "updating both MQTT passwords failed"
    fi
    [[ "$(mqtt_test_line "${passwd}" Zigbee2mqtt_domaPc)" == "Zigbee2mqtt_domaPc:\$test\$${zigbee_sum}" ]] \
        || mqtt_test_fail "both-password update missed Zigbee2MQTT"
    [[ "$(mqtt_test_line "${passwd}" homeassistant)" == "homeassistant:\$test\$${ha_sum}" ]] \
        || mqtt_test_fail "both-password update missed Home Assistant"
    [[ "$(mqtt_test_line "${passwd}" manual)" == 'manual:$manual$kept' ]] \
        || mqtt_test_fail "both-password update removed another user"

    # A failed hash leaves the previous password file intact.
    cp -a "${passwd}" "${root}/passwd.good"
    export MQTT_PASSWORD="zigbee-secret-value-9"
    export MQTT_FAIL_USER="Zigbee2mqtt_domaPc"
    if mqtt_test_run "${auth}" >/dev/null 2>&1; then
        mqtt_test_fail "a failing password update was treated as success"
    fi
    cmp -s "${passwd}" "${root}/passwd.good" || mqtt_test_fail "a failed update changed passwd"
    plain_left="$(find "${auth}" -type f \
        ! -name passwd ! -name passwd.sha256 ! -name passwd.ha.sha256 ! -name argv.log \
        -print)"
    [[ -z "${plain_left}" ]] || mqtt_test_fail "a failed update left a temporary password file"

    # The first account can be committed while a later failure keeps every other line.
    export MQTT_FAIL_USER="homeassistant"
    export MQTT_PASSWORD="zigbee-secret-value-8"
    export MQTT_HA_PASSWORD="ha-secret-value-0008"
    zigbee_sum="$(printf '%s' "${MQTT_PASSWORD}" | sha256sum | awk '{print $1}')"
    if mqtt_test_run "${auth}" >/dev/null 2>&1; then
        mqtt_test_fail "a failing Home Assistant update was treated as success"
    fi
    [[ "$(mqtt_test_line "${passwd}" Zigbee2mqtt_domaPc)" == "Zigbee2mqtt_domaPc:\$test\$${zigbee_sum}" ]] \
        || mqtt_test_fail "the Zigbee2MQTT update was rolled back after a later failure"
    [[ "$(mqtt_test_line "${passwd}" homeassistant)" == "homeassistant:\$test\$${ha_sum}" ]] \
        || mqtt_test_fail "a failed Home Assistant update changed that account"
    [[ "$(mqtt_test_line "${passwd}" manual)" == 'manual:$manual$kept' ]] \
        || mqtt_test_fail "a failed Home Assistant update removed another user"
    plain_left="$(find "${auth}" -type f \
        ! -name passwd ! -name passwd.sha256 ! -name passwd.ha.sha256 ! -name argv.log \
        -print)"
    [[ -z "${plain_left}" ]] || mqtt_test_fail "a partial update left a temporary password file"

    # A failed checksum pipeline must not rewrite passwd.
    cp -a "${passwd}" "${root}/passwd.before-hash"
    cat > "${MQTT_FAKE_BIN}/sha256sum" <<'EOF'
#!/bin/sh
exit 1
EOF
    chmod 755 "${MQTT_FAKE_BIN}/sha256sum"
    export MQTT_FAIL_USER=""
    if mqtt_test_run "${auth}" >/dev/null 2>&1; then
        mqtt_test_fail "a failing password checksum was treated as success"
    fi
    cmp -s "${passwd}" "${root}/passwd.before-hash" \
        || mqtt_test_fail "a failing password checksum changed passwd"
    plain_left="$(find "${auth}" -type f \
        ! -name passwd ! -name passwd.sha256 ! -name passwd.ha.sha256 ! -name argv.log \
        -print)"
    [[ -z "${plain_left}" ]] || mqtt_test_fail "a failing password checksum left a temporary file"
    rm -f "${MQTT_FAKE_BIN}/sha256sum"

    # TERM while the new passwd is still temporary must keep the original file.
    signal_auth="${root}/signal-auth"
    mkdir -p "${signal_auth}"
    printf '%s\n' 'manual:$manual$kept' > "${signal_auth}/passwd"
    chmod 600 "${signal_auth}/passwd"
    cp -a "${signal_auth}/passwd" "${root}/passwd.signal-before"
    export MQTT_PASSWD_HOLD=1
    export MQTT_PASSWD_READY="${root}/passwd-ready"
    export MQTT_PASSWD_HOLD_FIFO="${root}/passwd-hold"
    export MQTT_PASSWD_HELD="${root}/passwd-held"
    mkfifo "${MQTT_PASSWD_READY}" "${MQTT_PASSWD_HOLD_FIFO}"
    mqtt_test_run "${signal_auth}" >/dev/null 2>&1 &
    login_shell_pid=$!
    IFS=' ' read -r login_signal_pid login_options_path < "${MQTT_PASSWD_READY}"
    [[ "$(<"/proc/${login_signal_pid}/comm")" == "sh" ]] \
        || mqtt_test_fail "TERM was not aimed at the Mosquitto entrypoint"
    cmp -s "${signal_auth}/passwd" "${root}/passwd.signal-before" \
        || mqtt_test_fail "passwd changed before the entrypoint received TERM"
    kill -TERM "${login_signal_pid}"
    printf '\n' > "${MQTT_PASSWD_HOLD_FIFO}"
    login_rc=0
    wait "${login_shell_pid}" || login_rc=$?
    [[ "${login_rc}" -eq 143 ]] || mqtt_test_fail "TERM did not end the Mosquitto entrypoint with status 143"
    cmp -s "${signal_auth}/passwd" "${root}/passwd.signal-before" \
        || mqtt_test_fail "TERM changed the original passwd"
    plain_left="$(find "${signal_auth}" -type f \
        ! -name passwd ! -name passwd.sha256 ! -name passwd.ha.sha256 ! -name argv.log \
        -print)"
    [[ -z "${plain_left}" ]] || mqtt_test_fail "TERM left a temporary password file"
    unset MQTT_PASSWD_HOLD MQTT_PASSWD_READY MQTT_PASSWD_HOLD_FIFO MQTT_PASSWD_HELD

    # The second temporary file fails after the plaintext file already exists.
    mktemp_auth="${root}/mktemp-auth"
    mkdir -p "${mktemp_auth}"
    printf '%s\n' 'manual:$manual$kept' > "${mktemp_auth}/passwd"
    chmod 600 "${mktemp_auth}/passwd"
    cp -a "${mktemp_auth}/passwd" "${root}/passwd.mktemp-before"
    export MQTT_PASSWORD="zigbee-secret-value-7"
    export MQTT_HA_PASSWORD="ha-secret-value-0007"
    export MQTT_MKTEMP_COUNT="${root}/mktemp-count"
    export MQTT_REAL_MKTEMP="$(command -v mktemp)"
    cat > "${MQTT_FAKE_BIN}/mktemp" <<'EOF'
#!/bin/sh
set -eu
count_file="${MQTT_MKTEMP_COUNT:?}"
real="${MQTT_REAL_MKTEMP:?}"
n=0
if [ -f "${count_file}" ]; then
    n="$(cat "${count_file}")"
fi
n=$((n + 1))
printf '%s\n' "${n}" > "${count_file}"
if [ "${n}" -eq 2 ]; then
    exit 1
fi
exec "${real}" "$@"
EOF
    chmod 755 "${MQTT_FAKE_BIN}/mktemp"
    if mqtt_test_run "${mktemp_auth}" >/dev/null 2>&1; then
        mqtt_test_fail "a failing mktemp was treated as success"
    fi
    cmp -s "${mktemp_auth}/passwd" "${root}/passwd.mktemp-before" \
        || mqtt_test_fail "a failing mktemp changed passwd"
    plain_left="$(find "${mktemp_auth}" -type f \
        ! -name passwd ! -name passwd.sha256 ! -name passwd.ha.sha256 ! -name argv.log \
        -print)"
    [[ -z "${plain_left}" ]] || mqtt_test_fail "a failing mktemp left the plaintext password file"
    rm -f "${MQTT_FAKE_BIN}/mktemp"
    unset MQTT_MKTEMP_COUNT MQTT_REAL_MKTEMP

    unset MQTT_USER MQTT_PASSWORD MQTT_HA_USER MQTT_HA_PASSWORD MQTT_FAIL_USER MQTT_FAKE_BIN
    rm -rf "${root}"
    ok "Mosquitto accounts update independently and preserve other users"
}

check_ha_mqtt_secret_render() {
    local dir body
    dir="$(mktemp -d)"
    declare -gA RUNTIME_ENV=()
    RUNTIME_ENV[HA_CONFIG_HOST_DIR]="${dir}"
    RUNTIME_ENV[PG_USER]="homeassistant"
    RUNTIME_ENV[PG_PASS]="database-secret-value"
    RUNTIME_ENV[PG_DB]="homeassistant"
    RUNTIME_ENV[MQTT_USER]="Zigbee2mqtt_domaPc"
    RUNTIME_ENV[MQTT_PASSWORD]="zigbee-secret-value-1"
    RUNTIME_ENV[MQTT_HA_USER]="homeassistant"
    RUNTIME_ENV[MQTT_HA_PASSWORD]="ha-secret-value-0002"
    printf '%s\n' 'other: keep' 'mqtt_user: "old-zigbee"' 'mqtt_password: "old-zigbee-password"' > "${dir}/secrets.yaml"
    deploy_render_secrets
    [[ "$(stat -c '%a' "${dir}/secrets.yaml")" == 600 ]] || fail_static "rendered secrets.yaml is not mode 600"
    body="$(<"${dir}/secrets.yaml")"
    [[ "${body}" == *"mqtt_ha_user: $(yaml_double "${RUNTIME_ENV[MQTT_HA_USER]}")"* ]] \
        || fail_static "rendered secrets do not contain the Home Assistant MQTT user"
    [[ "${body}" == *"mqtt_ha_password: $(yaml_double "${RUNTIME_ENV[MQTT_HA_PASSWORD]}")"* ]] \
        || fail_static "rendered secrets do not contain the Home Assistant MQTT password"
    [[ "${body}" == *"other: keep"* ]] || fail_static "rendered secrets dropped an unrelated key"
    [[ "${body}" != *"zigbee-secret-value-1"* ]] || fail_static "rendered secrets contain the Zigbee2MQTT password"
    [[ "${body}" != *"mqtt_user:"* && "${body}" != *"mqtt_password:"* ]] \
        || fail_static "rendered secrets still contain the old MQTT keys"
    rm -rf "${dir}"
    ok "Home Assistant secrets contain only its own MQTT account"
}

login_secret_absent() {
    local file="$1" secret="$2" what="$3" content
    [[ -f "${file}" ]] || fail_static "missing ${what}"
    content="$(<"${file}")"
    [[ "${content}" != *"${secret}"* ]] || fail_static "password appeared in ${what}"
}

check_post_deploy_mqtt_login_secret() {
    local root bin dir zigbee_pass ha_pass
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/lib/post-deploy/checks.sh"
    root="$(mktemp -d)"
    bin="${root}/bin"
    dir="${root}/work"
    mkdir -p "${bin}" "${dir}/status"
    zigbee_pass="zigbee-login-secret-value"
    ha_pass="ha-login-secret-value-02"
    cat > "${bin}/docker" <<'EOF'
#!/bin/sh
set -eu
status="${MQTT_LOGIN_STATUS:?}"
tr '\0' '\n' < /proc/self/cmdline > "${status}/docker.cmdline"
tr '\0' '\n' < /proc/self/environ > "${status}/docker.environ"
script=""
prev=""
assignments=$(mktemp)
chmod 600 "${assignments}"
for arg in "$@"; do
    if [ "${prev}" = "-e" ]; then
        printf '%s\n' "${arg}" >> "${assignments}"
    fi
    if [ "${prev}" = "-c" ]; then
        script=${arg}
    fi
    prev=${arg}
done
[ -n "${script}" ] || exit 2
if [ -n "${MQTT_LOGIN_CAPTURE:-}" ]; then
    umask 077
    printf '%s\n' "${script}" > "${MQTT_LOGIN_CAPTURE}"
    rm -f "${assignments}"
    exit 0
fi
while IFS= read -r assignment; do
    case "${assignment}" in
        *=*) export "${assignment}" ;;
    esac
done < "${assignments}"
rm -f "${assignments}"
exec sh -c "${script}"
EOF
    cat > "${bin}/mosquitto_pub" <<'EOF'
#!/bin/sh
set -eu
status="${MQTT_LOGIN_STATUS:?}"
expect="${MQTT_LOGIN_EXPECT:?}"
tr '\0' '\n' < /proc/self/cmdline > "${status}/pub.cmdline"
tr '\0' '\n' < /proc/self/environ > "${status}/pub.environ"
tr '\0' '\n' < "/proc/${PPID}/cmdline" > "${status}/shell.cmdline"
tr '\0' '\n' < "/proc/${PPID}/environ" > "${status}/shell.environ"
printf '%s\n' "$@" > "${status}/pub.args"
[ "${1:-}" = "-o" ] || exit 3
[ -n "${2:-}" ] || exit 3
printf '%s\n' "$2" > "${status}/options.path"
stat -c '%a' "$2" > "${status}/mode"
if cmp -s "$2" "${expect}"; then
    printf '%s\n' ok > "${status}/content"
else
    printf '%s\n' bad > "${status}/content"
fi
awk 'NR==3 { sub(/^-u /,""); print }' "$2" >> "${status}/users"
if [ "${MQTT_LOGIN_HOLD:-0}" = 1 ]; then
    printf '%s %s\n' "${PPID}" "$2" > "${MQTT_LOGIN_READY:?}"
    read -r _ < "${MQTT_LOGIN_HOLD_FIFO:?}" || true
fi
if [ "${MQTT_LOGIN_EXIT:-0}" = 1 ]; then
    exit 1
fi
exit 0
EOF
    chmod 755 "${bin}/docker" "${bin}/mosquitto_pub"
    export MQTT_LOGIN_STATUS="${dir}/status"
    export MQTT_LOGIN_EXPECT="${dir}/expect"
    : > "${MQTT_LOGIN_STATUS}/users"

    login_prepare_expect() {
        local user="$1" secret="$2"
        umask 077
        {
            printf '%s\n' "-h 127.0.0.1"
            printf '%s\n' "-p 1883"
            printf '%s\n' "-u ${user}"
            printf '%s\n' "-P ${secret}"
            printf '%s\n' "-t ha/health"
            printf '%s\n' "-m up"
        } > "${MQTT_LOGIN_EXPECT}"
    }

    login_assert_hidden() {
        local secret="$1" path
        login_secret_absent "${MQTT_LOGIN_STATUS}/docker.cmdline" "${secret}" "docker arguments"
        login_secret_absent "${MQTT_LOGIN_STATUS}/docker.environ" "${secret}" "docker environment"
        login_secret_absent "${MQTT_LOGIN_STATUS}/shell.cmdline" "${secret}" "shell arguments"
        login_secret_absent "${MQTT_LOGIN_STATUS}/shell.environ" "${secret}" "shell environment"
        login_secret_absent "${MQTT_LOGIN_STATUS}/pub.cmdline" "${secret}" "mosquitto_pub arguments"
        login_secret_absent "${MQTT_LOGIN_STATUS}/pub.args" "${secret}" "mosquitto_pub arguments"
        login_secret_absent "${MQTT_LOGIN_STATUS}/pub.environ" "${secret}" "mosquitto_pub environment"
        [[ "$(<"${MQTT_LOGIN_STATUS}/mode")" == 600 ]] || fail_static "MQTT options file is not mode 600"
        [[ "$(<"${MQTT_LOGIN_STATUS}/content")" == ok ]] || fail_static "MQTT options file did not match the account"
        path="$(<"${MQTT_LOGIN_STATUS}/options.path")"
        [[ -n "${path}" && ! -e "${path}" ]] || fail_static "MQTT options file was left behind"
    }

    login_prepare_expect "Zigbee2mqtt_domaPc" "${zigbee_pass}"
    PATH="${bin}:${PATH}" post_deploy_mqtt_login "Zigbee2mqtt_domaPc" "${zigbee_pass}" "Zigbee2MQTT"
    login_assert_hidden "${zigbee_pass}"
    [[ "$(tail -n 1 "${MQTT_LOGIN_STATUS}/users")" == "Zigbee2mqtt_domaPc" ]] \
        || fail_static "Zigbee2MQTT login was not checked on its own"

    login_prepare_expect "homeassistant" "${ha_pass}"
    PATH="${bin}:${PATH}" post_deploy_mqtt_login "homeassistant" "${ha_pass}" "Home Assistant"
    login_assert_hidden "${ha_pass}"
    [[ "$(tail -n 1 "${MQTT_LOGIN_STATUS}/users")" == "homeassistant" ]] \
        || fail_static "Home Assistant login was not checked on its own"

    login_prepare_expect "Zigbee2mqtt_domaPc" "${zigbee_pass}"
    export MQTT_LOGIN_EXIT=1
    login_rc=0
    (
        PATH="${bin}:${PATH}"
        post_deploy_mqtt_login "Zigbee2mqtt_domaPc" "${zigbee_pass}" "Zigbee2MQTT"
    ) >/dev/null 2>&1 || login_rc=$?
    [[ "${login_rc}" -ne 0 ]] || fail_static "a failing mosquitto_pub was treated as a successful MQTT login"
    login_assert_hidden "${zigbee_pass}"

    # fail masks the shell status, so the signal is observed on the real sh -c
    # script. The client blocks on a fifo until after TERM is pending; POSIX
    # runs the trap only once that foreground client exits.
    unset MQTT_LOGIN_EXIT
    export MQTT_LOGIN_CAPTURE="${dir}/captured-script"
    PATH="${bin}:${PATH}" post_deploy_mqtt_login "Zigbee2mqtt_domaPc" "${zigbee_pass}" "Zigbee2MQTT" >/dev/null
    unset MQTT_LOGIN_CAPTURE
    [[ -f "${dir}/captured-script" ]] || fail_static "MQTT login shell script was not captured"
    [[ "$(<"${dir}/captured-script")" != *"${zigbee_pass}"* ]] \
        || fail_static "captured MQTT login script contains a password"
    [[ "$(<"${dir}/captured-script")" == *"trap cleanup EXIT"* ]] \
        || fail_static "MQTT login shell has no EXIT cleanup"
    [[ "$(<"${dir}/captured-script")" == *"trap 'exit 143' TERM"* ]] \
        || fail_static "MQTT login shell has no TERM handler"
    [[ "$(<"${dir}/captured-script")" == *'mosquitto_pub -o "$options"'* ]] \
        || fail_static "MQTT login shell does not use an options file"

    export MQTT_LOGIN_HOLD=1
    export MQTT_LOGIN_READY="${dir}/ready"
    export MQTT_LOGIN_HOLD_FIFO="${dir}/hold"
    mkfifo "${MQTT_LOGIN_READY}" "${MQTT_LOGIN_HOLD_FIFO}"
    login_prepare_expect "Zigbee2mqtt_domaPc" "${zigbee_pass}"
    MQTT_USER="Zigbee2mqtt_domaPc" \
        PATH="${bin}:${PATH}" \
        sh -c "$(<"${dir}/captured-script")" <<< "${zigbee_pass}" >/dev/null 2>&1 &
    login_shell_pid=$!
    # config.sh sets IFS to newline and tab, so this read must split on space.
    IFS=' ' read -r login_signal_pid login_options_path < "${MQTT_LOGIN_READY}"
    [[ "${login_signal_pid}" == "${login_shell_pid}" ]] \
        || fail_static "TERM was not aimed at the MQTT login shell"
    [[ -f "${login_options_path}" ]] || fail_static "MQTT options file was not created before TERM"
    kill -TERM "${login_shell_pid}"
    printf '\n' > "${MQTT_LOGIN_HOLD_FIFO}"
    login_rc=0
    wait "${login_shell_pid}" || login_rc=$?
    [[ "${login_rc}" -eq 143 ]] || fail_static "TERM did not end the MQTT login shell with status 143"
    [[ ! -e "${login_options_path}" ]] || fail_static "TERM did not remove the MQTT options file"
    unset MQTT_LOGIN_HOLD MQTT_LOGIN_READY MQTT_LOGIN_HOLD_FIFO

    unset MQTT_LOGIN_STATUS MQTT_LOGIN_EXPECT MQTT_LOGIN_EXIT
    rm -rf "${root}"
    ok "MQTT login keeps the password out of process arguments and the environment"
}

check_wmbus_script_deploy() {
    local root dest backup_count before
    root="$(mktemp -d)"
    dest="${root}/data"
    mkdir -p "${dest}"

    deploy_sync_executable "${WMBUS_PUBLISH_TEMPLATE}" "${dest}/publish_mqtt.sh" "publish"
    deploy_sync_executable "${WMBUS_SUBSCRIBE_TEMPLATE}" "${dest}/mqtt_subscribe.sh" "subscribe"
    [[ "$(stat -c '%a' "${dest}/publish_mqtt.sh")" == 755 ]] \
        || fail_static "first publish script is not mode 755"
    [[ "$(stat -c '%a' "${dest}/mqtt_subscribe.sh")" == 755 ]] \
        || fail_static "first subscribe script is not mode 755"
    cmp -s "${WMBUS_PUBLISH_TEMPLATE}" "${dest}/publish_mqtt.sh" \
        || fail_static "first publish script does not match the template"
    cmp -s "${WMBUS_SUBSCRIBE_TEMPLATE}" "${dest}/mqtt_subscribe.sh" \
        || fail_static "first subscribe script does not match the template"
    backup_count="$(find "${dest}" -name '*.bak' | wc -l)"
    [[ "${backup_count}" -eq 0 ]] || fail_static "first install created a backup"

    deploy_sync_executable "${WMBUS_PUBLISH_TEMPLATE}" "${dest}/publish_mqtt.sh" "publish"
    deploy_sync_executable "${WMBUS_SUBSCRIBE_TEMPLATE}" "${dest}/mqtt_subscribe.sh" "subscribe"
    backup_count="$(find "${dest}" -name '*.bak' | wc -l)"
    [[ "${backup_count}" -eq 0 ]] || fail_static "an unchanged script was backed up again"

    printf 'local edit\n' > "${dest}/publish_mqtt.sh"
    chmod 755 "${dest}/publish_mqtt.sh"
    before="$(<"${dest}/publish_mqtt.sh")"
    deploy_sync_executable "${WMBUS_PUBLISH_TEMPLATE}" "${dest}/publish_mqtt.sh" "publish"
    cmp -s "${WMBUS_PUBLISH_TEMPLATE}" "${dest}/publish_mqtt.sh" \
        || fail_static "a changed template did not replace the publish script"
    [[ "$(stat -c '%a' "${dest}/publish_mqtt.sh")" == 755 ]] \
        || fail_static "an updated publish script is not mode 755"
    backup_count="$(find "${dest}" -name 'publish_mqtt.sh.*.bak' | wc -l)"
    [[ "${backup_count}" -eq 1 ]] || fail_static "an update did not keep exactly one backup"
    [[ "$(<"$(find "${dest}" -name 'publish_mqtt.sh.*.bak')")" == "${before}" ]] \
        || fail_static "the backup is not the previous publish script"

    printf 'stable\n' > "${dest}/mqtt_subscribe.sh"
    chmod 755 "${dest}/mqtt_subscribe.sh"
    mkdir -p "${root}/bin"
    cat > "${root}/bin/mv" <<'EOF'
#!/bin/sh
exit 1
EOF
    chmod 755 "${root}/bin/mv"
    (
        PATH="${root}/bin:${PATH}"
        deploy_sync_executable "${WMBUS_SUBSCRIBE_TEMPLATE}" "${dest}/mqtt_subscribe.sh" "subscribe"
    ) >/dev/null 2>&1 && fail_static "a failed script replace was treated as success"
    [[ "$(<"${dest}/mqtt_subscribe.sh")" == "stable" ]] \
        || fail_static "a failed replace changed the subscribe script"
    [[ "$(stat -c '%a' "${dest}/mqtt_subscribe.sh")" == 755 ]] \
        || fail_static "a failed replace changed the subscribe script mode"
    rm -rf "${root}"
    ok "WMBusmeters scripts install once and update through a backup"
}

mqtt_option_value() {
    local file="$1" key="$2" line
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        [[ "${line}" == \#* ]] && continue
        [[ "${line}" == "${key}" || "${line}" == "${key} "* ]] || continue
        printf '%s' "${line#"${key}" }"
        return 0
    done < "${file}"
    return 1
}

check_mqtt_client_option_files() {
    local root bin dir secret json saved got
    sh -n "${REPO_ROOT}/configs/mosquitto/healthcheck.sh" \
        || fail_static "sh -n mosquitto healthcheck"
    sh -n "${REPO_ROOT}/configs/wmbusmeters/mqtt_subscribe.sh" \
        || fail_static "sh -n WMBusmeters subscribe wrapper"
    sh -n "${REPO_ROOT}/configs/wmbusmeters/publish_mqtt.sh" \
        || fail_static "sh -n WMBusmeters publish script"
    if grep -E '^[[:space:]]*mosquitto_(pub|sub).* -P' \
        "${REPO_ROOT}/compose/50-mosquitto.yml" \
        "${REPO_ROOT}/configs/mosquitto/healthcheck.sh" \
        "${REPO_ROOT}/configs/wmbusmeters/entrypoint.sh" \
        "${REPO_ROOT}/configs/wmbusmeters/mqtt_subscribe.sh" \
        "${REPO_ROOT}/configs/wmbusmeters/publish_mqtt.sh"; then
        fail_static "a Mosquitto client still receives -P on its command"
    fi
    if grep -q 'MQTT_PASSWORD' "${REPO_ROOT}/configs/wmbusmeters/entrypoint.sh"; then
        fail_static "the WMBusmeters command still contains the MQTT password"
    fi
    grep -q 'ha-mosquitto-healthcheck.sh' "${REPO_ROOT}/compose/50-mosquitto.yml" \
        || fail_static "the Mosquitto healthcheck does not use its helper"
    grep -q 'interval: 30s' "${REPO_ROOT}/compose/50-mosquitto.yml" \
        && grep -q 'timeout: 10s' "${REPO_ROOT}/compose/50-mosquitto.yml" \
        && grep -q 'retries: 5' "${REPO_ROOT}/compose/50-mosquitto.yml" \
        && grep -q 'start_period: 20s' "${REPO_ROOT}/compose/50-mosquitto.yml" \
        || fail_static "the Mosquitto healthcheck timing changed"

    root="$(mktemp -d)"
    bin="${root}/bin"
    dir="${root}/work"
    mkdir -p "${bin}" "${dir}/status" "${dir}/tmp"
    secret="$(printf '%s' ' a b'"'"'"$`\#'"end ")"
    json='{"id":"meter 1","note":"a b"}'
    cat > "${bin}/mosquitto_pub" <<'EOF'
#!/bin/sh
set -eu
status="${MQTT_CLIENT_STATUS:?}"
name="${MQTT_CLIENT_NAME:?}"
tr '\0' '\n' < /proc/self/cmdline > "${status}/${name}.cmdline"
tr '\0' '\n' < /proc/self/environ > "${status}/${name}.environ"
printf '%s\n' "$@" > "${status}/${name}.args"
[ "${1:-}" = "-o" ] || exit 3
[ -n "${2:-}" ] || exit 3
cp "$2" "${status}/${name}.options"
stat -c '%a' "$2" > "${status}/${name}.mode"
if [ "${MQTT_CLIENT_HOLD:-0}" = 1 ]; then
    printf '%s %s\n' "${PPID}" "$2" > "${MQTT_CLIENT_READY:?}"
    read -r _ < "${MQTT_CLIENT_HOLD_FIFO:?}" || true
fi
if [ "${MQTT_CLIENT_EXIT:-0}" = 1 ]; then
    exit 1
fi
exit 0
EOF
    cat > "${bin}/mosquitto_sub" <<'EOF'
#!/bin/sh
set -eu
status="${MQTT_CLIENT_STATUS:?}"
name="${MQTT_CLIENT_NAME:?}"
tr '\0' '\n' < /proc/self/cmdline > "${status}/${name}.cmdline"
tr '\0' '\n' < /proc/self/environ > "${status}/${name}.environ"
printf '%s\n' "$@" > "${status}/${name}.args"
[ "${1:-}" = "-o" ] || exit 3
[ -n "${2:-}" ] || exit 3
cp "$2" "${status}/${name}.options"
stat -c '%a' "$2" > "${status}/${name}.mode"
if [ "${MQTT_CLIENT_HOLD:-0}" = 1 ]; then
    printf '%s %s\n' "${PPID}" "$2" > "${MQTT_CLIENT_READY:?}"
    read -r _ < "${MQTT_CLIENT_HOLD_FIFO:?}" || true
fi
printf '%s\n' 'telegram-hex'
if [ "${MQTT_CLIENT_EXIT:-0}" = 1 ]; then
    exit 1
fi
exit 0
EOF
    chmod 755 "${bin}/mosquitto_pub" "${bin}/mosquitto_sub"
    export MQTT_CLIENT_STATUS="${dir}/status"

    mqtt_client_run() {
        local script="$1"
        MQTT_CLIENT_NAME="${MQTT_CLIENT_NAME}" \
            MQTT_USER="Zigbee2mqtt_domaPc" \
            MQTT_PASSWORD="${secret}" \
            METER_ID="Apator04799531" \
            METER_JSON="${json}" \
            TMPDIR="${dir}/tmp" \
            PATH="${bin}:${PATH}" \
            sh "${script}"
    }

    mqtt_client_hidden() {
        local name="$1" options
        login_secret_absent "${MQTT_CLIENT_STATUS}/${name}.cmdline" "${secret}" "${name} arguments"
        login_secret_absent "${MQTT_CLIENT_STATUS}/${name}.args" "${secret}" "${name} arguments"
        login_secret_absent "${MQTT_CLIENT_STATUS}/${name}.environ" "${secret}" "${name} environment"
        [[ "$(<"${MQTT_CLIENT_STATUS}/${name}.mode")" == 600 ]] \
            || fail_static "${name} options file is not mode 600"
        options="${MQTT_CLIENT_STATUS}/${name}.options"
        got="$(mqtt_option_value "${options}" "-P")" || fail_static "${name} options file has no password"
        [[ "${got}" == "${secret}" ]] || fail_static "${name} options file did not keep the password"
        [[ "$(mqtt_option_value "${options}" "-u")" == "Zigbee2mqtt_domaPc" ]] \
            || fail_static "${name} did not use the Zigbee2MQTT account"
        [[ "$(<"${options}")" != *homeassistant* ]] \
            || fail_static "${name} used the Home Assistant MQTT account"
        if find "${dir}/tmp" -type f -print | grep -q .; then
            fail_static "${name} left an options file behind"
        fi
    }

    export MQTT_CLIENT_NAME=health
    mqtt_client_run "${REPO_ROOT}/configs/mosquitto/healthcheck.sh"
    mqtt_client_hidden health
    [[ "$(mqtt_option_value "${MQTT_CLIENT_STATUS}/health.options" "-h")" == "127.0.0.1" ]] \
        || fail_static "healthcheck host changed"
    [[ "$(mqtt_option_value "${MQTT_CLIENT_STATUS}/health.options" "-p")" == 1883 ]] \
        || fail_static "healthcheck port changed"
    [[ "$(mqtt_option_value "${MQTT_CLIENT_STATUS}/health.options" "-t")" == "ha/health" ]] \
        || fail_static "healthcheck topic changed"
    [[ "$(mqtt_option_value "${MQTT_CLIENT_STATUS}/health.options" "-m")" == up ]] \
        || fail_static "healthcheck payload changed"

    export MQTT_CLIENT_NAME=subscribe
    saved="$(mqtt_client_run "${REPO_ROOT}/configs/wmbusmeters/mqtt_subscribe.sh")"
    [[ "${saved}" == "telegram-hex" ]] || fail_static "WMBusmeters subscribe did not pass the telegram through"
    mqtt_client_hidden subscribe
    [[ "$(mqtt_option_value "${MQTT_CLIENT_STATUS}/subscribe.options" "-h")" == mosquitto ]] \
        || fail_static "subscribe host changed"
    [[ "$(mqtt_option_value "${MQTT_CLIENT_STATUS}/subscribe.options" "-p")" == 1883 ]] \
        || fail_static "subscribe port changed"
    [[ "$(mqtt_option_value "${MQTT_CLIENT_STATUS}/subscribe.options" "-t")" == "wmbus/lilygo/telegram" ]] \
        || fail_static "subscribe topic changed"

    export MQTT_CLIENT_NAME=publish
    mqtt_client_run "${REPO_ROOT}/configs/wmbusmeters/publish_mqtt.sh"
    mqtt_client_hidden publish
    [[ "$(mqtt_option_value "${MQTT_CLIENT_STATUS}/publish.options" "-h")" == mosquitto ]] \
        || fail_static "publish host changed"
    [[ "$(mqtt_option_value "${MQTT_CLIENT_STATUS}/publish.options" "-p")" == 1883 ]] \
        || fail_static "publish port changed"
    [[ "$(mqtt_option_value "${MQTT_CLIENT_STATUS}/publish.options" "-t")" == "wmbusmeters/Apator04799531" ]] \
        || fail_static "publish topic changed"
    grep -q -- '-m' "${MQTT_CLIENT_STATUS}/publish.args" \
        || fail_static "publish payload is not an argument"
    [[ "$(<"${MQTT_CLIENT_STATUS}/publish.args")" == *"${json}"* ]] \
        || fail_static "publish payload changed"
    if grep -q -- '-P' "${MQTT_CLIENT_STATUS}/publish.args"; then
        fail_static "publish still passes -P as an argument"
    fi

    export MQTT_CLIENT_NAME=publish-id
    MQTT_CLIENT_NAME=publish-id \
        MQTT_USER="Zigbee2mqtt_domaPc" \
        MQTT_PASSWORD="${secret}" \
        METER_ID="Meter_A-1" \
        METER_JSON="${json}" \
        TMPDIR="${dir}/tmp" \
        PATH="${bin}:${PATH}" \
        sh "${REPO_ROOT}/configs/wmbusmeters/publish_mqtt.sh"
    mqtt_client_hidden publish-id
    [[ "$(mqtt_option_value "${MQTT_CLIENT_STATUS}/publish-id.options" "-t")" == "wmbusmeters/Meter_A-1" ]] \
        || fail_static "a valid METER_ID was not used in the topic"
    mkdir -p "${dir}/empty"
    for saved in "" "bad id" "bad/id" "bad.id" "$(printf 'bad\nid')"; do
        login_rc=0
        MQTT_USER="Zigbee2mqtt_domaPc" \
            MQTT_PASSWORD="${secret}" \
            METER_ID="${saved}" \
            METER_JSON="${json}" \
            TMPDIR="${dir}/empty" \
            PATH="${bin}:${PATH}" \
            sh "${REPO_ROOT}/configs/wmbusmeters/publish_mqtt.sh" >/dev/null 2>&1 || login_rc=$?
        [[ "${login_rc}" -ne 0 ]] || fail_static "an invalid METER_ID was accepted"
    done
    if find "${dir}/empty" -type f -print | grep -q .; then
        fail_static "an invalid METER_ID left an options file"
    fi

    export MQTT_CLIENT_EXIT=1
    for saved in \
        "${REPO_ROOT}/configs/mosquitto/healthcheck.sh" \
        "${REPO_ROOT}/configs/wmbusmeters/mqtt_subscribe.sh" \
        "${REPO_ROOT}/configs/wmbusmeters/publish_mqtt.sh"
    do
        login_rc=0
        mqtt_client_run "${saved}" >/dev/null 2>&1 || login_rc=$?
        [[ "${login_rc}" -ne 0 ]] || fail_static "a failing Mosquitto client was treated as success"
    done
    if find "${dir}/tmp" -type f -print | grep -q .; then
        fail_static "a failing client left an options file behind"
    fi
    unset MQTT_CLIENT_EXIT

    export MQTT_CLIENT_HOLD=1
    export MQTT_CLIENT_READY="${dir}/ready"
    export MQTT_CLIENT_HOLD_FIFO="${dir}/hold"
    for saved in \
        "${REPO_ROOT}/configs/mosquitto/healthcheck.sh:health-signal" \
        "${REPO_ROOT}/configs/wmbusmeters/mqtt_subscribe.sh:subscribe-signal" \
        "${REPO_ROOT}/configs/wmbusmeters/publish_mqtt.sh:publish-signal"
    do
        mkfifo "${MQTT_CLIENT_READY}" "${MQTT_CLIENT_HOLD_FIFO}"
        MQTT_CLIENT_NAME="${saved##*:}" \
            MQTT_USER="Zigbee2mqtt_domaPc" \
            MQTT_PASSWORD="${secret}" \
            METER_ID="Apator04799531" \
            METER_JSON="${json}" \
            TMPDIR="${dir}/tmp" \
            PATH="${bin}:${PATH}" \
            sh "${saved%%:*}" >/dev/null 2>&1 &
        login_shell_pid=$!
        IFS=' ' read -r login_signal_pid login_options_path < "${MQTT_CLIENT_READY}"
        [[ "${login_signal_pid}" == "${login_shell_pid}" ]] \
            || fail_static "TERM was not aimed at ${saved##*:}"
        [[ -f "${login_options_path}" ]] || fail_static "${saved##*:} did not create an options file"
        kill -TERM "${login_shell_pid}"
        printf '\n' > "${MQTT_CLIENT_HOLD_FIFO}"
        login_rc=0
        wait "${login_shell_pid}" || login_rc=$?
        [[ "${login_rc}" -eq 143 ]] || fail_static "TERM did not end ${saved##*:} with status 143"
        [[ ! -e "${login_options_path}" ]] || fail_static "TERM did not remove the ${saved##*:} options file"
        rm -f "${MQTT_CLIENT_READY}" "${MQTT_CLIENT_HOLD_FIFO}"
    done
    unset MQTT_CLIENT_HOLD MQTT_CLIENT_READY MQTT_CLIENT_HOLD_FIFO

    mkdir -p "${dir}/empty"
    login_rc=0
    MQTT_USER="Zigbee2mqtt_domaPc" \
        MQTT_PASSWORD="$(printf 'bad\nsecret')" \
        TMPDIR="${dir}/empty" \
        PATH="${bin}:${PATH}" \
        sh "${REPO_ROOT}/configs/mosquitto/healthcheck.sh" >/dev/null 2>&1 || login_rc=$?
    [[ "${login_rc}" -ne 0 ]] || fail_static "a password containing a newline was accepted"
    if find "${dir}/empty" -type f -print | grep -q .; then
        fail_static "a rejected password left an options file"
    fi
    login_rc=0
    MQTT_USER="Zigbee2mqtt_domaPc" \
        MQTT_PASSWORD="$(printf 'a%.0s' $(seq 1 1100))" \
        TMPDIR="${dir}/empty" \
        PATH="${bin}:${PATH}" \
        sh "${REPO_ROOT}/configs/mosquitto/healthcheck.sh" >/dev/null 2>&1 || login_rc=$?
    [[ "${login_rc}" -ne 0 ]] || fail_static "a password that does not fit an options line was accepted"

    unset MQTT_CLIENT_STATUS MQTT_CLIENT_NAME
    rm -rf "${root}"
    ok "Mosquitto clients keep passwords in a private options file"

    if ! command -v docker >/dev/null 2>&1; then
        ok "Real Mosquitto 2.1.2 login was not run: docker is not available"
        return 0
    fi
    if ! docker image inspect docker.io/library/eclipse-mosquitto:2.1.2-alpine >/dev/null 2>&1; then
        ok "Real Mosquitto 2.1.2 login was not run: the image is not local"
        return 0
    fi
    mqtt_real_broker_login
}

mqtt_real_broker_login() {
    local zigbee_pass ha_pass output
    zigbee_pass="$(printf '%s' 'zig bee/pass+A=')"
    ha_pass="$(printf '%s' 'ha bee/pass+B=')"
    output="$(docker run --rm -i --entrypoint sh \
        docker.io/library/eclipse-mosquitto:2.1.2-alpine \
        -c 'set -eu
umask 077
IFS= read -r zigbee
IFS= read -r ha
mkdir -p /auth
printf "%s:%s\n" Zigbee2mqtt_domaPc "$zigbee" > /auth/plain
printf "%s:%s\n" homeassistant "$ha" >> /auth/plain
mosquitto_passwd -U /auth/plain >/dev/null
mv /auth/plain /auth/passwd
chmod 600 /auth/passwd
cat > /auth/mosquitto.conf <<EOF
listener 1883 127.0.0.1
allow_anonymous false
password_file /auth/passwd
EOF
chown mosquitto:mosquitto /auth
chown mosquitto:mosquitto /auth/passwd
chown mosquitto:mosquitto /auth/mosquitto.conf
version="$(mosquitto -h 2>&1 | head -n 1 || true)"
case "${version}" in
    *2.1.2*) ;;
    *) echo "unexpected mosquitto client" >&2; exit 1 ;;
esac
mosquitto -c /auth/mosquitto.conf >/dev/null 2>&1 &
broker=$!
write_options() {
    user="$1"
    pass="$2"
    file="$3"
    {
        printf "%s\n" "-h 127.0.0.1"
        printf "%s\n" "-p 1883"
        printf "%s\n" "-u ${user}"
        printf "%s\n" "-P ${pass}"
        printf "%s\n" "-t ha/health"
        printf "%s\n" "-m up"
    } > "${file}"
    chmod 600 "${file}"
}
write_options Zigbee2mqtt_domaPc "$zigbee" /auth/zigbee.opts
write_options homeassistant "$ha" /auth/ha.opts
ready=0
attempt=0
while [ "${attempt}" -lt 40 ]; do
    if mosquitto_pub -o /auth/zigbee.opts >/dev/null 2>&1; then
        ready=1
        break
    fi
    attempt=$((attempt + 1))
    sleep 0.05
done
[ "${ready}" = 1 ]
mosquitto_pub -o /auth/ha.opts >/dev/null
{
    printf "%s\n" "-h 127.0.0.1"
    printf "%s\n" "-p 1883"
    printf "%s\n" "-u Zigbee2mqtt_domaPc"
    printf "%s\n" "-P wrong-password-value"
    printf "%s\n" "-t ha/health"
    printf "%s\n" "-m up"
} > /auth/bad.opts
chmod 600 /auth/bad.opts
if mosquitto_pub -o /auth/bad.opts >/dev/null 2>&1; then
    exit 1
fi
kill "${broker}" >/dev/null 2>&1 || true
wait "${broker}" >/dev/null 2>&1 || true
printf "%s\n" broker-login-ok' <<EOF
${zigbee_pass}
${ha_pass}
EOF
)" || fail_static "Mosquitto 2.1.2 did not accept both accounts through an options file"
    [[ "${output}" == *broker-login-ok* ]] \
        || fail_static "Mosquitto 2.1.2 did not accept both accounts through an options file"
    [[ "${output}" != *"${zigbee_pass}"* && "${output}" != *"${ha_pass}"* ]] \
        || fail_static "the real Mosquitto login printed a password"
    ok "Mosquitto 2.1.2 accepts both accounts through an options file"
}

check_network_rules() {
    env_validate_subnet_pair "DOCKER_INTERNAL" "172.31.0.0/24" "172.31.0.1"
    if env_ip_private "${DOMA_HOST_ADDRESS}"; then
        :
    else
        fail_static "the domaPc host address was not recognized as private"
    fi
    [[ "${DOMA_HOST_ADDRESS}" == "10.100.100.100" ]] || fail_static "the domaPc host address changed"
    encoded="$(env_urlencode 'a+b/c=')"
    [[ "${encoded}" == "a%2Bb%2Fc%3D" ]] || fail_static "database password URL encoding changed"
    ok "Network and secret encoding rules passed"
}

check_deploy_database_order() {
    local deploy_file="${REPO_ROOT}/scripts/deploy.sh"
    local db_line role_line compose_line
    db_line="$(grep -n '^deploy_database_services$' "${deploy_file}" | head -n 1 | cut -d: -f1)"
    role_line="$(grep -n '^deploy_postgres_role$' "${deploy_file}" | head -n 1 | cut -d: -f1)"
    compose_line="$(grep -n '^deploy_compose$' "${deploy_file}" | head -n 1 | cut -d: -f1)"
    [[ -n "${db_line}" && -n "${role_line}" && -n "${compose_line}" ]] \
        || fail_static "database deploy steps are missing"
    [[ "${db_line}" -lt "${role_line}" && "${role_line}" -lt "${compose_line}" ]] \
        || fail_static "the database role is not ready before the full stack starts"
    [[ "$(declare -f deploy_database_services)" == *'postgresql mosquitto'* ]] \
        || fail_static "database phase does not start PostgreSQL and Mosquitto"
    [[ "$(declare -f deploy_database_services)" != *'homeassistant'* ]] \
        || fail_static "database phase starts Home Assistant"
    [[ "$(declare -f deploy_postgres_role_sql)" == *'PASSWORD %L'* ]] \
        || fail_static "the database password is not passed as a quoted literal"
    grep -q 'post_deploy_check_database' "${REPO_ROOT}/scripts/post-deploy.sh" \
        || fail_static "post-deploy does not check PostgreSQL"
    grep -q 'post_deploy_check_mqtt' "${REPO_ROOT}/scripts/post-deploy.sh" \
        || fail_static "post-deploy does not check MQTT"
    grep -q 'post_deploy_check_homeassistant' "${REPO_ROOT}/scripts/post-deploy.sh" \
        || fail_static "post-deploy does not check Home Assistant"
    ok "Database services start before the role and the full stack"
}

case "${1:-}" in
    --static|"")
        static_checks
        ;;
    --help)
        printf '%s\n' "Usage: ./scripts/test.sh --static"
        ;;
    *)
        fail "Unknown option: $1"
        ;;
esac
