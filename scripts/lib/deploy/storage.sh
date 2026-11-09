#!/usr/bin/env bash
# sourced by scripts/lib loaders
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

deploy_sync_executable() {
    local source="$1" dest="$2" label="$3"
    local tmp backup="" stamp n
    [[ -f "${source}" ]] || fail "Missing source for ${label}."
    if [[ -L "${dest}" ]]; then
        fail "${label} target ${dest} is a symbolic link."
    fi
    if [[ -e "${dest}" && ! -f "${dest}" ]]; then
        fail "${label} target ${dest} is not a regular file."
    fi
    if [[ -f "${dest}" ]] && cmp -s "${source}" "${dest}"; then
        return 0
    fi
    if [[ -f "${dest}" ]]; then
        stamp="$(date +%Y%m%dT%H%M%S)"
        backup="${dest}.${stamp}.bak"
        n=0
        while [[ -e "${backup}" ]]; do
            n=$((n + 1))
            backup="${dest}.${stamp}.${n}.bak"
        done
        cp -a "${dest}" "${backup}" || fail "Could not back up ${label}. Left ${dest} unchanged."
        if ! chmod 600 "${backup}"; then
            rm -f "${backup}"
            fail "Could not protect the backup of ${label}. Left ${dest} unchanged."
        fi
    fi
    tmp="$(mktemp "${dest}.XXXXXX")" || fail "Could not stage ${label}."
    if ! cp "${source}" "${tmp}"; then
        rm -f "${tmp}"
        fail "Could not copy ${label}. Left the previous file unchanged."
    fi
    if ! chmod 755 "${tmp}"; then
        rm -f "${tmp}"
        fail "Could not set permissions on ${label}. Left the previous file unchanged."
    fi
    if ! mv -f "${tmp}" "${dest}"; then
        rm -f "${tmp}"
        fail "Could not replace ${label}. Left the previous file unchanged."
    fi
    if [[ -n "${backup}" ]]; then
        ok "Updated ${label}. Previous copy saved as ${backup}."
    else
        ok "Seeded ${label}."
    fi
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
    deploy_sync_executable "${WMBUS_PUBLISH_TEMPLATE}" \
        "${RUNTIME_ENV[WMBUSMETERS_HOST_DIR]}/publish_mqtt.sh" \
        "WMBusmeters publish script"
    deploy_sync_executable "${WMBUS_SUBSCRIBE_TEMPLATE}" \
        "${RUNTIME_ENV[WMBUSMETERS_HOST_DIR]}/mqtt_subscribe.sh" \
        "WMBusmeters subscribe script"
    prepare_owned_dir "${RUNTIME_ENV[POSTGRESQL_HOST_DIR]}" "${POSTGRESQL_UID_GID}" "Home Assistant PostgreSQL"
    ok "Persistent directories are ready."
}
