#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/checks/load.sh"
source "${SCRIPT_DIR}/lib/env/load.sh"
source "${SCRIPT_DIR}/lib/backup/archive.sh"

print_header "Backup"
check_environment
require_command docker
env_load_runtime
mkdir -p "${BACKUP_LOCAL_DIR}"
chmod 700 "${BACKUP_LOCAL_DIR}"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
stage="$(mktemp -d "${BACKUP_LOCAL_DIR}/stage-${stamp}.XXXXXX")"
chmod 700 "${stage}"
archive="${BACKUP_LOCAL_DIR}/${STACK_NAME}-${stamp}.tar"
stopped=()

start_stopped() {
    local container
    for ((container = ${#stopped[@]} - 1; container >= 0; container--)); do
        docker start "${stopped[container]}" >/dev/null || warn "Could not start ${stopped[container]} again."
    done
    stopped=()
}

cleanup() {
    start_stopped
    rm -rf "${stage}"
}
trap cleanup EXIT

stop_one() {
    local name="$1"
    docker inspect "${name}" >/dev/null 2>&1 || return 0
    local running
    running="$(docker inspect -f '{{.State.Running}}' "${name}")"
    [[ "${running}" == true ]] || return 0
    docker stop "${name}" >/dev/null
    stopped+=("${name}")
}

stop_one "${HA_CONTAINER}"
stop_one "${ZIGBEE2MQTT_CONTAINER}"
stop_one "${ESPHOME_CONTAINER}"
stop_one "${WMBUSMETERS_CONTAINER}"
stop_one "${MOSQUITTO_CONTAINER}"

mkdir -p "${stage}/postgresql"
docker exec -e PGPASSWORD="${RUNTIME_ENV[PG_SUPER_PASS]}" "${POSTGRESQL_CONTAINER}" \
    pg_dump -U "${POSTGRES_BOOTSTRAP_USER}" -d "${RUNTIME_ENV[PG_DB]}" -Fc \
    > "${stage}/postgresql/homeassistant.dump"
dump_head="$(od -An -tx1 -N5 "${stage}/postgresql/homeassistant.dump" | tr -d ' \n')"
[[ "${dump_head}" == "5047444d50" ]] || fail "Database dump does not start with PGDMP. No archive was published."
docker exec -i "${POSTGRESQL_CONTAINER}" pg_restore -l < "${stage}/postgresql/homeassistant.dump" >/dev/null \
    || fail "pg_restore cannot list the dump. No archive was published."

copy_tree() {
    local src="$1" name="$2"
    [[ -d "${src}" ]] || fail "Missing data directory ${src}."
    mkdir -p "${stage}/${name}"
    cp -a "${src}/." "${stage}/${name}/"
}

copy_tree "${RUNTIME_ENV[HA_CONFIG_HOST_DIR]}" homeassistant
copy_tree "${DATA_DIR}/mosquitto" mosquitto
copy_tree "${RUNTIME_ENV[ZIGBEE2MQTT_HOST_DIR]}" zigbee2mqtt
copy_tree "${RUNTIME_ENV[ESPHOME_HOST_DIR]}" esphome
copy_tree "${RUNTIME_ENV[WMBUSMETERS_HOST_DIR]}" wmbusmeters
mkdir -p "${stage}/mosquitto/repo-config"
cp -a "${GIT_DIR}/configs/mosquitto/mosquitto.conf" "${stage}/mosquitto/repo-config/mosquitto.conf"
cp -a "${GIT_DIR}/configs/mosquitto/entrypoint.sh" "${stage}/mosquitto/repo-config/entrypoint.sh"
cp -a "${GIT_DIR}/configs/wmbusmeters/publish_mqtt.sh" "${stage}/wmbusmeters/publish_mqtt.sh.from-repo"
cp -a "${GIT_DIR}/configs/wmbusmeters/mqtt_subscribe.sh" "${stage}/wmbusmeters/mqtt_subscribe.sh.from-repo"

backup_write_manifest "${stage}" "${stamp}" "${RUNTIME_ENV[POSTGRES_IMAGE]}" "${RUNTIME_ENV[HA_TAG]}"
backup_pack "${stage}" "${archive}"
verify="$(mktemp -d)"
backup_verify_archive "${archive}" "${verify}"
rm -rf "${verify}" "${stage}"

if [[ -n "${RUNTIME_ENV[BACKUP_EXTERNAL_DIR]}" ]]; then
    mkdir -p "${RUNTIME_ENV[BACKUP_EXTERNAL_DIR]}"
    cp -a "${archive}" "${archive}.sha256" "${RUNTIME_ENV[BACKUP_EXTERNAL_DIR]}/"
    ok "Copied the verified archive to BACKUP_EXTERNAL_DIR."
fi

if [[ -n "${RUNTIME_ENV[RESTIC_REPOSITORY]}" ]]; then
    require_command restic
    export RESTIC_PASSWORD="${RUNTIME_ENV[RESTIC_PASSWORD]}"
    restic -r "${RUNTIME_ENV[RESTIC_REPOSITORY]}" snapshots >/dev/null 2>&1 \
        || restic -r "${RUNTIME_ENV[RESTIC_REPOSITORY]}" init >/dev/null
    restic -r "${RUNTIME_ENV[RESTIC_REPOSITORY]}" backup "${archive}" >/dev/null
    restic -r "${RUNTIME_ENV[RESTIC_REPOSITORY]}" forget \
        --keep-daily "${RUNTIME_ENV[RESTIC_KEEP_DAILY]}" \
        --keep-weekly "${RUNTIME_ENV[RESTIC_KEEP_WEEKLY]}" \
        --keep-monthly "${RUNTIME_ENV[RESTIC_KEEP_MONTHLY]}" \
        --keep-yearly "${RUNTIME_ENV[RESTIC_KEEP_YEARLY]}" \
        --prune >/dev/null
    unset RESTIC_PASSWORD
    ok "Restic copy of the verified archive finished, then retention ran."
fi

start_stopped
trap - EXIT
ok "Unencrypted archive written: ${archive}"
print_footer "Backup completed. Stopped services were started again."
