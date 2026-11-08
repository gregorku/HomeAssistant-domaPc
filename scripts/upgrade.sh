#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/env.sh"
source "${SCRIPT_DIR}/lib/deploy.sh"

confirm="${2:-}"
[[ "${1:-}" == "--confirm" && "${confirm}" == "${STACK_NAME}" ]] \
    || fail "Refusing upgrade. Usage: ./scripts/upgrade.sh --confirm ${STACK_NAME}"

print_header "Upgrade Home Assistant"
check_environment
require_command docker
env_load_runtime
[[ ! -f "${UPGRADE_LOCK_FILE}" ]] || fail "An upgrade lock already exists."
[[ -f "${INSTALLED_VERSION_FILE}" ]] || fail "No installed version is recorded."
installed="$(tr -d '[:space:]' < "${INSTALLED_VERSION_FILE}")"
wanted="${RUNTIME_ENV[HA_TAG]}"
[[ "${installed}" != "${wanted}" ]] || fail "Tag ${wanted} is already recorded. Change HA_TAG first."
[[ "${wanted}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Refusing a non-exact Home Assistant tag."

avail="$(df -Pm "${DATA_DIR}" | awk 'NR==2 {print $4}')"
[[ "${avail}" -ge "${RUNTIME_ENV[UPGRADE_MIN_FREE_MB]}" ]] \
    || fail "Free space on ${DATA_DIR} is ${avail} MiB, below UPGRADE_MIN_FREE_MB."

printf '%s\n' "${wanted}" > "${UPGRADE_LOCK_FILE}"
info "Upgrade lock written. Data directories are not deleted."
(
    cd "${STACK_DIR}"
    docker compose --env-file "${ENV_FILE}" up -d homeassistant
)
if ! post_deploy_check_homeassistant; then
    fail "Home Assistant did not answer after the upgrade. The lock remains at ${UPGRADE_LOCK_FILE}."
fi
reported="$(post_deploy_homeassistant_version || true)"
[[ "${reported}" == "${wanted}" ]] || fail "Home Assistant reports '${reported}', not ${wanted}. The lock remains at ${UPGRADE_LOCK_FILE}."
rm -f "${UPGRADE_LOCK_FILE}"
printf '%s\n' "${wanted}" > "${INSTALLED_VERSION_FILE}"
ok "Upgrade recorded as ${wanted}."
