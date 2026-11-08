#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/checks/load.sh"
source "${SCRIPT_DIR}/lib/env/load.sh"

confirm=""
source_container="db-homeassistant"
source_db="homeassistant"
source_user="gregor"
dump=""
restore_new=0
old_data="/zfs-data/postgres-db-homeassistant/data"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --confirm) confirm="$2"; shift 2 ;;
        --source-container) source_container="$2"; shift 2 ;;
        --dump) dump="$2"; shift 2 ;;
        --restore-into-new) restore_new=1; shift ;;
        *) fail "Unknown option: $1" ;;
    esac
done

[[ "${confirm}" == "${STACK_NAME}" ]] \
    || fail "Usage: ./scripts/migrate-postgres.sh --confirm ${STACK_NAME} [--dump PATH] [--restore-into-new]"

print_header "PostgreSQL 16 to 18.6 migration"
check_environment
require_command docker
env_load_runtime

[[ "${RUNTIME_ENV[POSTGRESQL_HOST_DIR]}" != "${old_data}" ]] \
    || fail "POSTGRESQL_HOST_DIR is the PostgreSQL 16 data directory. Refusing to start 18.6 on it."

image="$(docker inspect -f '{{.Config.Image}}' "${source_container}")"
[[ "${image}" == *postgres:16* ]] || fail "Source container ${source_container} image is ${image}, not postgres:16."

if [[ -z "${dump}" ]]; then
    mkdir -p "${BACKUP_LOCAL_DIR}"
    chmod 700 "${BACKUP_LOCAL_DIR}"
    dump="${BACKUP_LOCAL_DIR}/postgres16-$(date -u +%Y%m%dT%H%M%SZ).dump"
fi

docker exec -u postgres "${source_container}" \
    pg_dump -U "${source_user}" -d "${source_db}" -Fc > "${dump}"
chmod 600 "${dump}"
head="$(od -An -tx1 -N5 "${dump}" | tr -d ' \n')"
[[ "${head}" == "5047444d50" ]] || fail "Dump does not start with PGDMP. The old data directory was not touched."
docker exec -i "${source_container}" pg_restore -l < "${dump}" >/dev/null \
    || fail "pg_restore cannot list the dump. The old data directory was not touched."
ok "Logical dump written and listed: ${dump}"

if [[ "${restore_new}" -ne 1 ]]; then
    print_footer "Dump only. The PostgreSQL 16 directory was not changed. Re-run with --restore-into-new after PostgreSQL 18.6 is up."
    exit 0
fi

version="$(docker exec "${POSTGRESQL_CONTAINER}" psql -U "${POSTGRES_BOOTSTRAP_USER}" -d postgres -Atc 'SHOW server_version')"
[[ "${version}" == 18.* ]] || fail "New server is ${version}. Refusing to restore into anything but PostgreSQL 18."
docker exec -i -e PGPASSWORD="${RUNTIME_ENV[PG_SUPER_PASS]}" "${POSTGRESQL_CONTAINER}" \
    pg_restore -U "${POSTGRES_BOOTSTRAP_USER}" -d "${RUNTIME_ENV[PG_DB]}" --no-owner --role="${RUNTIME_ENV[PG_USER]}" \
    < "${dump}" \
    || fail "Restore into PostgreSQL 18 failed. The old container and its data directory were not changed."
ok "Dump restored into ${POSTGRESQL_CONTAINER}. Source ${source_container} and ${old_data} were left in place."
print_footer "Migration restore completed."
