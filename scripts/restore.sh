#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/checks/load.sh"
source "${SCRIPT_DIR}/lib/env/load.sh"
source "${SCRIPT_DIR}/lib/backup/archive.sh"

archive=""
target=""
replace=0
confirm=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive) archive="$2"; shift 2 ;;
        --target) target="$2"; shift 2 ;;
        --replace-data) replace=1; shift ;;
        --confirm) confirm="$2"; shift 2 ;;
        *) fail "Unknown option: $1" ;;
    esac
done

[[ -n "${archive}" && "${confirm}" == "${STACK_NAME}" ]] \
    || fail "Usage: ./scripts/restore.sh --archive PATH --confirm ${STACK_NAME} [--target DIR | --replace-data]"
[[ "${replace}" -eq 0 || -z "${target}" ]] || fail "Use either --target or --replace-data."
[[ "${replace}" -eq 1 || -n "${target}" ]] || fail "The first restore needs --target DIR and does not change production data."

print_header "Restore"
check_environment
env_load_runtime

work="$(mktemp -d)"
chmod 700 "${work}"
trap 'rm -rf "${work}"' EXIT
backup_verify_archive "${archive}" "${work}/checked"
if [[ "${replace}" -eq 1 ]]; then
    docker exec -i "${POSTGRESQL_CONTAINER}" pg_restore -l < "${work}/checked/$(backup_dump_member)" >/dev/null \
        || fail "pg_restore cannot list the dump. Production data was not changed."
elif command -v pg_restore >/dev/null 2>&1; then
    backup_list_dump "${work}/checked/$(backup_dump_member)"
else
    warn "pg_restore is not installed here. Dump listing was not run. The PGDMP header was checked."
fi
ok "Archive and checksums passed."

if [[ -n "${target}" ]]; then
    [[ "${target}" == /* && "${target}" != "/" ]] || fail "Restore target must be an absolute directory."
    case "${target}" in
        "${DATA_DIR}"|"${DATA_DIR}"/*|"${STACK_DIR}"|"${STACK_DIR}"/*|"${GIT_DIR}"|"${GIT_DIR}"/*|"${BACKUP_LOCAL_DIR}"|"${BACKUP_LOCAL_DIR}"/*|"${RUNTIME_ENV[POSTGRESQL_HOST_DIR]}"|"${RUNTIME_ENV[POSTGRESQL_HOST_DIR]}"/*)
            fail "Refusing to extract into production data, the stack, Git or PostgreSQL."
            ;;
    esac
    mkdir -p "${target}"
    find "${target}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    cp -a "${work}/checked/." "${target}/"
    ok "Archive extracted to ${target}. Production data was not changed."
    print_footer "Isolated restore completed."
    exit 0
fi

require_command docker
version="$(docker exec "${POSTGRESQL_CONTAINER}" psql -U "${POSTGRES_BOOTSTRAP_USER}" -d "${RUNTIME_ENV[PG_DB]}" -Atc 'SHOW server_version')"
[[ "${version}" == 18.* ]] || fail "Running PostgreSQL is ${version}. Refusing to restore a dump into a server that is not 18."

print_section "Safety backup"
"${SCRIPT_DIR}/backup.sh"

stop_names=(
    "${HA_CONTAINER}"
    "${ZIGBEE2MQTT_CONTAINER}"
    "${ESPHOME_CONTAINER}"
    "${WMBUSMETERS_CONTAINER}"
    "${MOSQUITTO_CONTAINER}"
)
for name in "${stop_names[@]}"; do
    docker stop "${name}" >/dev/null 2>&1 || true
done

restore_tree() {
    local name="$1" dest="$2"
    mkdir -p "${dest}"
    find "${dest}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    cp -a "${work}/checked/${name}/." "${dest}/"
}

restore_tree homeassistant "${RUNTIME_ENV[HA_CONFIG_HOST_DIR]}"
restore_tree mosquitto "${DATA_DIR}/mosquitto"
restore_tree zigbee2mqtt "${RUNTIME_ENV[ZIGBEE2MQTT_HOST_DIR]}"
restore_tree esphome "${RUNTIME_ENV[ESPHOME_HOST_DIR]}"
restore_tree wmbusmeters "${RUNTIME_ENV[WMBUSMETERS_HOST_DIR]}"
chmod 700 "${DATA_DIR}/mosquitto/auth" "${RUNTIME_ENV[WMBUSMETERS_HOST_DIR]}" 2>/dev/null || true
chmod 600 "${RUNTIME_ENV[HA_CONFIG_HOST_DIR]}/secrets.yaml" 2>/dev/null || true

docker exec -i -e PGPASSWORD="${RUNTIME_ENV[PG_SUPER_PASS]}" "${POSTGRESQL_CONTAINER}" \
    pg_restore -U "${POSTGRES_BOOTSTRAP_USER}" -d "${RUNTIME_ENV[PG_DB]}" --clean --if-exists --no-owner \
    < "${work}/checked/$(backup_dump_member)" \
    || fail "pg_restore failed. Production services were left stopped."

for name in "${stop_names[@]}"; do
    docker start "${name}" >/dev/null 2>&1 || warn "Could not start ${name}."
done
ok "Production data was replaced from the archive and services were started."
print_footer "Restore completed."
