#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/env.sh"

archive=""
identity=""
replace=0
confirm=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive) archive="$2"; shift 2 ;;
        --identity) identity="$2"; shift 2 ;;
        --replace-data) replace=1; shift ;;
        --confirm) confirm="$2"; shift 2 ;;
        *) fail "Unknown option: $1" ;;
    esac
done

[[ -n "${archive}" && "${confirm}" == "${STACK_NAME}" ]] \
    || fail "Usage: ./scripts/restore.sh --archive PATH --confirm ${STACK_NAME} [--identity KEY] [--replace-data]"
[[ -f "${archive}" ]] || fail "Archive does not exist: ${archive}"

print_header "Restore check"
check_environment
env_load_runtime

work="$(mktemp -d)"
chmod 700 "${work}"
cleanup() { rm -rf "${work}"; }
trap cleanup EXIT

source_tar="${archive}"
if [[ "${archive}" == *.age ]]; then
    [[ -n "${identity}" && -f "${identity}" ]] || fail "An age archive needs --identity before any data is changed."
    require_command age
    age -d -i "${identity}" -o "${work}/archive.tar" "${archive}"
    source_tar="${work}/archive.tar"
fi
tar -tf "${source_tar}" | grep -qx "homeassistant.dump"
tar -xOf "${source_tar}" homeassistant.dump > "${work}/homeassistant.dump"
dump_head="$(od -An -tx1 -N5 "${work}/homeassistant.dump" | tr -d ' \n')"
[[ "${dump_head}" == "5047444d50" ]] \
    || fail "The dump is not a PostgreSQL custom archive. Live data was not changed."
if tar -tf "${source_tar}" | grep -qx "SHA256SUMS"; then
    tar -xOf "${source_tar}" SHA256SUMS > "${work}/SHA256SUMS"
    (
        cd "${work}"
        sha256sum -c SHA256SUMS
    )
fi
ok "Archive is readable and the dump has a PGDMP header."

if [[ "${replace}" -ne 1 ]]; then
    warn "No data was changed. Re-run with --replace-data after this check succeeds."
    exit 2
fi

require_command docker
docker stop "${HA_CONTAINER}" "${MOSQUITTO_CONTAINER}" >/dev/null
docker exec -i -e PGPASSWORD="${RUNTIME_ENV[PG_PASS]}" "${POSTGRESQL_CONTAINER}" \
    pg_restore -U "${RUNTIME_ENV[PG_USER]}" -d "${RUNTIME_ENV[PG_DB]}" --clean --if-exists \
    < "${work}/homeassistant.dump"
config_dir="${RUNTIME_ENV[HA_CONFIG_HOST_DIR]}"
mkdir -p "${config_dir}"
if tar -tf "${source_tar}" | grep -qx "homeassistant/configuration.yaml"; then
    tar -C "${work}" -xf "${source_tar}" homeassistant/configuration.yaml
    cp -a "${work}/homeassistant/configuration.yaml" "${config_dir}/configuration.yaml"
fi
if tar -tf "${source_tar}" | grep -qx "homeassistant/secrets.yaml"; then
    tar -C "${work}" -xf "${source_tar}" homeassistant/secrets.yaml
    cp -a "${work}/homeassistant/secrets.yaml" "${config_dir}/secrets.yaml"
    chmod 600 "${config_dir}/secrets.yaml"
fi
if tar -tf "${source_tar}" | grep -q '^mosquitto/'; then
    mkdir -p "${DATA_DIR}/mosquitto/auth"
    tar -C "${work}" -xf "${source_tar}" mosquitto
    cp -a "${work}/mosquitto/." "${DATA_DIR}/mosquitto/auth/"
    chmod 700 "${DATA_DIR}/mosquitto/auth"
    chmod 600 "${DATA_DIR}/mosquitto/auth/passwd" "${DATA_DIR}/mosquitto/auth/passwd.sha256" 2>/dev/null || true
fi
ok "Database restore finished. Review Home Assistant before starting it again."
print_footer "Home Assistant and Mosquitto were left stopped."
