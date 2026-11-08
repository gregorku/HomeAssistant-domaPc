#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/env.sh"

print_header "Backup"
check_environment
require_command docker
env_load_runtime
mkdir -p "${BACKUP_LOCAL_DIR}"
chmod 700 "${BACKUP_LOCAL_DIR}"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
stage="$(mktemp -d "${BACKUP_LOCAL_DIR}/stage-${stamp}.XXXXXX")"
chmod 700 "${stage}"
cleanup() { rm -rf "${stage}"; }
trap cleanup EXIT

docker stop "${HA_CONTAINER}" >/dev/null
start_ha() {
    docker start "${HA_CONTAINER}" >/dev/null || true
}
trap 'start_ha; cleanup' EXIT

docker exec -e PGPASSWORD="${RUNTIME_ENV[PG_PASS]}" "${POSTGRESQL_CONTAINER}" \
    pg_dump -U "${RUNTIME_ENV[PG_USER]}" -d "${RUNTIME_ENV[PG_DB]}" -Fc \
    > "${stage}/homeassistant.dump"
dump_head="$(od -An -tx1 -N5 "${stage}/homeassistant.dump" | tr -d ' \n')"
[[ "${dump_head}" == "5047444d50" ]] || fail "Database dump does not start with PGDMP. No archive was published."

config_dir="${RUNTIME_ENV[HA_CONFIG_HOST_DIR]}"
mkdir -p "${stage}/homeassistant"
if [[ -f "${config_dir}/configuration.yaml" ]]; then
    cp -a "${config_dir}/configuration.yaml" "${stage}/homeassistant/configuration.yaml"
fi
if [[ -f "${config_dir}/secrets.yaml" ]]; then
    cp -a "${config_dir}/secrets.yaml" "${stage}/homeassistant/secrets.yaml"
fi
if [[ -d "${DATA_DIR}/mosquitto/auth" ]]; then
    mkdir -p "${stage}/mosquitto"
    cp -a "${DATA_DIR}/mosquitto/auth/." "${stage}/mosquitto/"
fi

(
    cd "${stage}"
    sha256sum homeassistant.dump > SHA256SUMS
    tar -cf "${BACKUP_LOCAL_DIR}/${STACK_NAME}-${stamp}.tar" .
)
archive="${BACKUP_LOCAL_DIR}/${STACK_NAME}-${stamp}.tar"
chmod 600 "${archive}"
tar -tf "${archive}" >/dev/null
ok "Unencrypted archive written: ${archive}"

if [[ -n "${RUNTIME_ENV[BACKUP_AGE_RECIPIENT]}" ]]; then
    require_command age
    age -r "${RUNTIME_ENV[BACKUP_AGE_RECIPIENT]}" -o "${archive}.age" "${archive}"
    chmod 600 "${archive}.age"
    ok "Age archive written. The identity key was not stored."
fi

if command -v restic >/dev/null 2>&1 && [[ -n "${RUNTIME_ENV[RESTIC_REPOSITORY]}" ]]; then
    RESTIC_PASSWORD="${RUNTIME_ENV[RESTIC_PASSWORD]}" restic -r "${RUNTIME_ENV[RESTIC_REPOSITORY]}" snapshots >/dev/null 2>&1 \
        || RESTIC_PASSWORD="${RUNTIME_ENV[RESTIC_PASSWORD]}" restic -r "${RUNTIME_ENV[RESTIC_REPOSITORY]}" init
    RESTIC_PASSWORD="${RUNTIME_ENV[RESTIC_PASSWORD]}" restic -r "${RUNTIME_ENV[RESTIC_REPOSITORY]}" backup \
        "${config_dir}" "${DATA_DIR}/mosquitto"
    ok "Restic snapshot created for Home Assistant config and Mosquitto data."
else
    warn "Restic backup was skipped. The tar archive does not replace an off-site copy."
fi

start_ha
trap cleanup EXIT
print_footer "Backup completed. Home Assistant was started again."
