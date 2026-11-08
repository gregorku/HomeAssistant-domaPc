#!/usr/bin/env bash
# sourced by scripts/lib loaders
deploy_check_dockge() {
    print_section "Dockge"
    require_command docker
    docker inspect "${DOCKGE_CONTAINER}" >/dev/null 2>&1 || fail "Dockge is not present. This project does not install it."
    docker inspect -f '{{.State.Running}}' "${DOCKGE_CONTAINER}" | grep -qx true \
        || fail "Dockge is not running. This project does not start, replace or remove it."
    local dockge_path
    dockge_path="$(docker exec "${DOCKGE_CONTAINER}" printenv DOCKGE_STACKS_DIR)"
    [[ "${dockge_path}" == "${STACKS_DIR}" ]] || fail "Dockge stack path is '${dockge_path}', expected '${STACKS_DIR}'."
    ok "Dockge is using ${STACKS_DIR}. Stack name: ${STACK_NAME}."
}

deploy_assert_version() {
    print_section "Version guard"
    [[ ! -f "${UPGRADE_LOCK_FILE}" ]] || fail "Upgrade lock exists. Finish or roll back before deploy."
    local wanted="${1}"
    if [[ -f "${INSTALLED_VERSION_FILE}" ]]; then
        local installed
        installed="$(tr -d '[:space:]' < "${INSTALLED_VERSION_FILE}")"
        [[ "${installed}" == "${wanted}" ]] || fail "Installed Home Assistant tag is ${installed}. Refusing to start ${wanted}. Run ./scripts/upgrade.sh."
        ok "Installed tag matches ${wanted}."
    else
        info "No installed-version file yet. This deploy will not delete existing Home Assistant data."
    fi
}

deploy_compose() {
    print_section "Compose"
    require_command docker
    docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is required and is not installed by this project."
    (
        cd "${STACK_DIR}"
        docker compose --env-file "${ENV_FILE}" config >/dev/null
        docker compose --env-file "${ENV_FILE}" up -d --remove-orphans
    )
    if [[ "${HA_SECRETS_CHANGED:-0}" == 1 ]]; then
        docker restart "${HA_CONTAINER}" >/dev/null \
            || fail "Home Assistant did not restart after the secrets file changed."
        ok "Home Assistant restarted to read updated secrets."
    fi
    ok "Compose started without removing volumes."
}

deploy_database_services() {
    print_section "Database services"
    local wait_seconds=240
    require_command docker
    docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is required and is not installed by this project."
    (
        cd "${STACK_DIR}"
        docker compose --env-file "${ENV_FILE}" up -d --wait --wait-timeout "${wait_seconds}" postgresql mosquitto
    ) || fail "PostgreSQL or Mosquitto did not become healthy before the timeout."
    docker exec "${POSTGRESQL_CONTAINER}" pg_isready -U "${POSTGRES_BOOTSTRAP_USER}" -d "${RUNTIME_ENV[PG_DB]}" >/dev/null 2>&1 \
        || fail "Home Assistant PostgreSQL did not become ready."
    ok "PostgreSQL and Mosquitto are healthy. Home Assistant was not started."
}
