#!/usr/bin/env bash

assert_sync_paths() {
    [[ -n "${GIT_DIR}" && -n "${STACK_DIR}" && -n "${DATA_DIR}" ]] || fail "A project path is empty."
    [[ "${GIT_DIR}" == /* && "${STACK_DIR}" == /* && "${DATA_DIR}" == /* ]] || fail "Project paths must be absolute."
    [[ "${GIT_DIR}" != "/" && "${STACK_DIR}" != "/" && "${DATA_DIR}" != "/" ]] || fail "Refusing to use '/'."
    [[ "${GIT_DIR}" != "${STACK_DIR}" ]] || fail "GIT_DIR and STACK_DIR must differ."
    [[ "${STACK_DIR}" == "${STACKS_DIR}/${STACK_NAME}" ]] || fail "STACK_DIR is not under this project's stack name."
    [[ "${DATA_DIR}" != "${STACK_DIR}" && "${BACKUP_LOCAL_DIR}" != "${STACK_DIR}" ]] || fail "Data and backups must stay outside the stack directory."
}

sync_tree() {
    local src="$1" dst="$2"
    mkdir -p "${dst}"
    rsync -a --delete "${src}/" "${dst}/"
}

deploy_sync_stack() {
    print_section "Synchronize stack"
    assert_sync_paths
    mkdir -p "${STACK_DIR}"
    local item src dst
    for item in "${DEPLOY_ITEMS[@]}"; do
        [[ "${item}" != /* && "${item}" != *..* ]] || fail "DEPLOY_ITEMS entry is not safe: ${item}"
        src="${GIT_DIR}/${item}"
        dst="${STACK_DIR}/${item}"
        [[ -e "${src}" ]] || fail "Missing deployment item: ${src}"
        if [[ -d "${src}" ]]; then
            sync_tree "${src}" "${dst}"
        else
            install -Dm644 "${src}" "${dst}"
        fi
        info "Synchronized ${item}"
    done
    ok "Stack files synchronized. Persistent data was not touched."
}

prepare_owned_dir() {
    local path="$1" owner="$2" purpose="$3"
    [[ -d "${path}" ]] || fail "${purpose} directory ${path} does not exist."
    findmnt -T "${path}" >/dev/null 2>&1 || fail "${purpose} directory ${path} is not on a mount."
    local mounted
    mounted="$(findmnt -T "${path}" -n -o TARGET)"
    [[ "${path}" != "${mounted}" ]] || fail "${purpose} directory ${path} is the mountpoint itself. Use a directory inside the disk."
    if [[ -n "$(ls -A "${path}")" ]]; then
        local uid
        uid="$(stat -c '%u' "${path}")"
        [[ "${uid}" == "${owner%%:*}" || "${uid}" == "0" ]] \
            || fail "${purpose} directory ${path} is owned by uid ${uid}. Refusing chown -R."
        return 0
    fi
    chown "${owner}" "${path}"
}

deploy_prepare_storage() {
    print_section "Persistent storage"
    require_mountpoint "${DOCKER_DATA_DIR}"
    mkdir -p \
        "${DATA_DIR}/homeassistant" \
        "${DATA_DIR}/zigbee2mqtt" \
        "${DATA_DIR}/esphome" \
        "${DATA_DIR}/wmbusmeters" \
        "${DATA_DIR}/state" \
        "${DATA_DIR}/mosquitto/data" \
        "${DATA_DIR}/mosquitto/log" \
        "${DATA_DIR}/mosquitto/auth" \
        "${BACKUP_LOCAL_DIR}"
    chmod 700 "${DATA_DIR}/state" "${BACKUP_LOCAL_DIR}" "${DATA_DIR}/mosquitto/auth" "${DATA_DIR}/wmbusmeters"
    if [[ -z "$(ls -A "${DATA_DIR}/mosquitto/data")" ]]; then
        chown "${MOSQUITTO_UID_GID}" "${DATA_DIR}/mosquitto/data" "${DATA_DIR}/mosquitto/log"
    fi
    if [[ ! -f "${RUNTIME_ENV[HA_CONFIG_HOST_DIR]}/configuration.yaml" ]]; then
        sed "s/__HA_TRUSTED_PROXY__/${RUNTIME_ENV[HA_TRUSTED_PROXY]}/g" \
            "${HA_CONFIG_TEMPLATE}" > "${RUNTIME_ENV[HA_CONFIG_HOST_DIR]}/configuration.yaml"
        chmod 644 "${RUNTIME_ENV[HA_CONFIG_HOST_DIR]}/configuration.yaml"
        ok "Seeded Home Assistant configuration.yaml."
    fi
    if [[ ! -f "${RUNTIME_ENV[WMBUSMETERS_HOST_DIR]}/publish_mqtt.sh" ]]; then
        install -m 755 "${WMBUS_PUBLISH_TEMPLATE}" "${RUNTIME_ENV[WMBUSMETERS_HOST_DIR]}/publish_mqtt.sh"
        ok "Seeded WMBusmeters publish script."
    fi
    prepare_owned_dir "${RUNTIME_ENV[POSTGRESQL_HOST_DIR]}" "${POSTGRESQL_UID_GID}" "Home Assistant PostgreSQL"
    ok "Persistent directories are ready."
}

deploy_ensure_one_network() {
    local name="$1" subnet="$2" gateway="$3"
    if docker network inspect "${name}" >/dev/null 2>&1; then
        local existing_subnet existing_gateway
        existing_subnet="$(docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "${name}")"
        existing_gateway="$(docker network inspect --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' "${name}")"
        [[ "${existing_subnet}" == "${subnet}" ]] || fail "Docker network ${name} already uses ${existing_subnet}, not ${subnet}. It was not changed."
        [[ "${existing_gateway}" == "${gateway}" ]] || fail "Docker network ${name} gateway is ${existing_gateway}, not ${gateway}. It was not changed."
        ok "Docker network ${name} already matches ${subnet}."
        return 0
    fi
    local other other_subnet
    while read -r other; do
        [[ -n "${other}" && "${other}" != "${name}" ]] || continue
        other_subnet="$(docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "${other}" 2>/dev/null || true)"
        [[ -n "${other_subnet}" ]] || continue
        if env_cidr_overlaps "${subnet}" "${other_subnet}"; then
            fail "Refusing to create ${name} ${subnet}: it overlaps existing network ${other} ${other_subnet}."
        fi
    done < <(docker network ls --format '{{.Name}}')
    docker network create --driver bridge --subnet "${subnet}" --gateway "${gateway}" "${name}" >/dev/null
    ok "Docker network ${name} created."
}

deploy_ensure_networks() {
    print_section "Docker networks"
    deploy_ensure_one_network "${NETWORK_INTERNAL}" "${RUNTIME_ENV[DOCKER_INTERNAL_SUBNET]}" "${RUNTIME_ENV[DOCKER_INTERNAL_GATEWAY]}"
}

yaml_quote() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

yaml_double() {
    printf '"%s"' "$(yaml_quote "$1")"
}

env_urlencode() {
    local LC_ALL=C
    local s="$1" i c
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        case "${c}" in
            [a-zA-Z0-9.~_-]) printf '%s' "${c}" ;;
            *) printf '%%%02X' "'${c}" ;;
        esac
    done
}

deploy_recorder_url() {
    local user pass db
    user="$(env_urlencode "${RUNTIME_ENV[PG_USER]}")"
    pass="$(env_urlencode "${RUNTIME_ENV[PG_PASS]}")"
    db="$(env_urlencode "${RUNTIME_ENV[PG_DB]}")"
    printf 'postgresql://%s:%s@postgresql:5432/%s' "${user}" "${pass}" "${db}"
}

deploy_render_secrets() {
    local dest="${RUNTIME_ENV[HA_CONFIG_HOST_DIR]}/secrets.yaml"
    local tmp url
    HA_SECRETS_CHANGED=0
    url="$(deploy_recorder_url)"
    tmp="$(mktemp "${RUNTIME_ENV[HA_CONFIG_HOST_DIR]}/secrets.yaml.tmp.XXXXXX")"
    chmod 600 "${tmp}"
    if [[ -f "${dest}" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            case "${line}" in
                recorder_db_url:*|mqtt_user:*|mqtt_password:*) continue ;;
            esac
            printf '%s\n' "${line}" >> "${tmp}"
        done < "${dest}"
    fi
    {
        printf 'recorder_db_url: %s\n' "$(yaml_double "${url}")"
        printf 'mqtt_user: %s\n' "$(yaml_double "${RUNTIME_ENV[MQTT_USER]}")"
        printf 'mqtt_password: %s\n' "$(yaml_double "${RUNTIME_ENV[MQTT_PASSWORD]}")"
    } >> "${tmp}"
    if [[ -f "${dest}" ]] && cmp -s "${tmp}" "${dest}"; then
        rm -f "${tmp}"
        return 0
    fi
    if [[ -f "${dest}" ]]; then
        HA_SECRETS_CHANGED=1
    fi
    mv "${tmp}" "${dest}"
    chmod 600 "${dest}"
}

deploy_render_runtime() {
    print_section "Render runtime files"
    deploy_render_secrets
    ok "Runtime secrets rendered. No proxy configuration was written."
}

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

deploy_postgres_role_sql() {
    case "$1" in
        role)
            cat <<'SQL'
\getenv app_pass PGAPP_PASS
SELECT CASE
    WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')
    THEN format('ALTER ROLE %I WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L', :'app_user', :'app_pass')
    ELSE format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L', :'app_user', :'app_pass')
END
\gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', :'app_db', :'app_user')
\gexec
SQL
            ;;
        schema)
            cat <<'SQL'
SELECT format('ALTER SCHEMA public OWNER TO %I', :'app_user')
\gexec
SQL
            ;;
        *)
            return 1
            ;;
    esac
}

deploy_postgres_admin_sql() {
    local database="$1"
    docker exec -i \
        -e PGAPP_USER="${RUNTIME_ENV[PG_USER]}" \
        -e PGAPP_PASS="${RUNTIME_ENV[PG_PASS]}" \
        -e PGAPP_DB="${RUNTIME_ENV[PG_DB]}" \
        "${POSTGRESQL_CONTAINER}" \
        sh -c 'exec psql -v ON_ERROR_STOP=1 -q -U "$1" -d "$2" -v app_user="$PGAPP_USER" -v app_db="$PGAPP_DB" -f -' \
        sh "${POSTGRES_BOOTSTRAP_USER}" "${database}"
}

deploy_postgres_role() {
    print_section "Home Assistant database role"
    local user="${RUNTIME_ENV[PG_USER]}"
    local db="${RUNTIME_ENV[PG_DB]}"
    [[ "${user}" != "${POSTGRES_BOOTSTRAP_USER}" ]] || fail "Refusing to change the bootstrap superuser."
    docker exec "${POSTGRESQL_CONTAINER}" pg_isready -U "${POSTGRES_BOOTSTRAP_USER}" -d "${db}" >/dev/null 2>&1 \
        || fail "Home Assistant PostgreSQL did not become ready."
    deploy_postgres_role_sql role | deploy_postgres_admin_sql postgres \
        || fail "Unable to prepare the Home Assistant database role."
    deploy_postgres_role_sql schema | deploy_postgres_admin_sql "${db}" \
        || fail "Unable to set the Home Assistant schema owner."
    docker exec \
        -e PGPASSWORD="${RUNTIME_ENV[PG_PASS]}" \
        -e PGAPP_USER="${user}" \
        -e PGAPP_DB="${db}" \
        "${POSTGRESQL_CONTAINER}" \
        sh -c 'exec psql -v ON_ERROR_STOP=1 -q -h "$(hostname)" -U "$PGAPP_USER" -d "$PGAPP_DB" -c "SELECT 1"' \
        >/dev/null \
        || fail "Application role could not log in to ${db}."
    ok "Application role is present. The bootstrap superuser was not removed."
}

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
