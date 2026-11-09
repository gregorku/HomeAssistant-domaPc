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
    grep -q 'wmbus/lilygo/telegram' "${REPO_ROOT}/configs/wmbusmeters/entrypoint.sh" \
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
    grep -q 'mosquitto_passwd -b' "${mqtt_entrypoint}" \
        && fail_static "Mosquitto still receives the password as a process argument"
    grep -q 'mosquitto_passwd -U "${plain}"' "${mqtt_entrypoint}" \
        || fail_static "Mosquitto password is not hashed from a protected temporary file"
    grep -q 'awk -F: -v user="${MQTT_USER}"' "${mqtt_entrypoint}" \
        || fail_static "Mosquitto entrypoint does not preserve other password-file users"
    grep -q 'managed_user_present' "${mqtt_entrypoint}" \
        || fail_static "Mosquitto entrypoint does not check the managed account"
    if grep -Fq ' > "${passwd_file}"' "${mqtt_entrypoint}"; then
        fail_static "Mosquitto entrypoint overwrites the complete password file"
    fi
    grep -q 'PG_SUPER_PASS' "${REPO_ROOT}/compose/40-postgresql.yml" \
        || fail_static "PostgreSQL superuser password is not separate"
    grep -q '^\.env$' "${REPO_ROOT}/.gitignore" || fail_static ".env is not ignored"
    grep -q '^set_postgres_password$' <(sed -n 's/^PG_PASS=//p' "${REPO_ROOT}/.env.example") \
        || fail_static "PG_PASS example is not a placeholder"
    grep -q '^set_mqtt_password$' <(sed -n 's/^MQTT_PASSWORD=//p' "${REPO_ROOT}/.env.example") \
        || fail_static "MQTT_PASSWORD example is not a placeholder"
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
    local dir example current first super mqtt esp output
    dir="$(mktemp -d)"
    example="${REPO_ROOT}/.env.example"
    current="${dir}/runtime.env"
    output="${dir}/sync.out"
    env_sync_file "${example}" "${current}" > "${output}"
    super="$(sed -n 's/^PG_SUPER_PASS=//p' "${current}")"
    first="$(sed -n 's/^PG_PASS=//p' "${current}")"
    mqtt="$(sed -n 's/^MQTT_PASSWORD=//p' "${current}")"
    esp="$(sed -n 's/^ESPHOME_PASSWORD=//p' "${current}")"
    [[ "${#super}" -ge 16 && "${super}" != set_* ]] || fail_static "PG_SUPER_PASS was not generated"
    [[ "${#first}" -ge 16 && "${first}" != set_* ]] || fail_static "PG_PASS was not generated"
    [[ "${super}" != "${first}" ]] || fail_static "superuser and application passwords are the same"
    [[ -z "$(sed -n 's/^RESTIC_PASSWORD=//p' "${current}")" ]] || fail_static "RESTIC_PASSWORD was generated"
    [[ "${#mqtt}" -ge 16 && "${mqtt}" != set_* ]] || fail_static "MQTT_PASSWORD was not generated"
    [[ "${#esp}" -ge 16 && "${esp}" != set_* ]] || fail_static "ESPHOME_PASSWORD was not generated"
    if grep -F -q -e "${super}" -e "${first}" -e "${mqtt}" -e "${esp}" "${output}"; then
        fail_static "update of .env printed a generated secret"
    fi
    [[ "$(stat -c '%a' "${current}")" == 600 ]] || fail_static "runtime .env is not mode 600"
    printf '%s\n' 'PG_PASS=kept-user-secret-value' 'MQTT_PASSWORD=kept-mqtt-secret-value' 'HA_DOMAIN=old.example' > "${current}"
    env_sync_file "${example}" "${current}" > "${output}"
    grep -q '^PG_PASS=kept-user-secret-value$' "${current}" \
        || fail_static "sync replaced an existing database password"
    grep -q '^MQTT_PASSWORD=kept-mqtt-secret-value$' "${current}" \
        || fail_static "sync replaced an existing MQTT password"
    grep -q '^HA_DOMAIN=homeassistant.serveftp.org$' "${current}" \
        || fail_static "sync did not keep the framework domain"
    if grep -F -q -e 'kept-user-secret-value' -e 'kept-mqtt-secret-value' "${output}"; then
        fail_static "sync printed an existing secret"
    fi
    rm -rf "${dir}"
    ok "Secret sync is idempotent and does not print passwords"
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
