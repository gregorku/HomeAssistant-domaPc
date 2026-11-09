#!/usr/bin/env bash
# sourced by scripts/lib loaders
env_validate_subnet_pair() {
    local name="$1" subnet="$2" gateway="$3" prefix
    env_cidr_ok "${subnet}" || fail "${name} subnet is not a CIDR."
    env_cidr_is_network_address "${subnet}" || fail "${name} subnet must be the network address."
    prefix="${subnet#*/}"
    [[ "${prefix}" -ge 16 && "${prefix}" -le 28 ]] || fail "${name} prefix must be between 16 and 28."
    [[ "${subnet}" != "0.0.0.0/0" ]] || fail "${name} must not be 0.0.0.0/0."
    env_ip_private "${subnet%/*}" || fail "${name} must be RFC1918 or CGNAT."
    env_ipv4_octets_ok "${gateway}" || fail "${name} gateway is not an IPv4 address."
    env_cidr_contains_ip "${subnet}" "${gateway}" || fail "${name} gateway is outside its subnet."
    [[ "${gateway}" != "${subnet%/*}" ]] || fail "${name} gateway must not be the network address."
}

env_validate_runtime() {
    local -n env_ref=$1

    [[ "${env_ref[COMPOSE_PROJECT_NAME]}" == "${STACK_NAME}" ]] || fail "COMPOSE_PROJECT_NAME must be ${STACK_NAME}."
    [[ "${env_ref[DATA_DIR]}" == "${DATA_DIR}" ]] || fail "DATA_DIR must be ${DATA_DIR}."
    [[ "${env_ref[HA_CONFIG_HOST_DIR]}" == "${DATA_DIR}/homeassistant" ]] || fail "HA_CONFIG_HOST_DIR must be ${DATA_DIR}/homeassistant."
    [[ "${env_ref[ZIGBEE2MQTT_HOST_DIR]}" == "${DATA_DIR}/zigbee2mqtt" ]] || fail "ZIGBEE2MQTT_HOST_DIR must be ${DATA_DIR}/zigbee2mqtt."
    [[ "${env_ref[ESPHOME_HOST_DIR]}" == "${DATA_DIR}/esphome" ]] || fail "ESPHOME_HOST_DIR must be ${DATA_DIR}/esphome."
    [[ "${env_ref[WMBUSMETERS_HOST_DIR]}" == "${DATA_DIR}/wmbusmeters" ]] || fail "WMBUSMETERS_HOST_DIR must be ${DATA_DIR}/wmbusmeters."
    [[ "${env_ref[BACKUP_LOCAL_DIR]}" == "${BACKUP_LOCAL_DIR}" ]] || fail "BACKUP_LOCAL_DIR must be ${BACKUP_LOCAL_DIR}."
    [[ "${env_ref[HA_DOMAIN]}" == "${HA_DOMAIN}" ]] || fail "HA_DOMAIN must be ${HA_DOMAIN}."

    [[ "${env_ref[HA_IMAGE]}" == "ghcr.io/home-assistant/home-assistant" ]] || fail "HA_IMAGE must be ghcr.io/home-assistant/home-assistant."
    [[ "${env_ref[HA_TAG]}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "HA_TAG must be an exact X.Y.Z release."
    [[ "${env_ref[POSTGRES_IMAGE]}" =~ ^docker\.io/library/postgres:18\.[0-9]+$ ]] || fail "POSTGRES_IMAGE must be an exact postgres 18 patch."
    [[ "${env_ref[MOSQUITTO_IMAGE]}" =~ ^docker\.io/library/eclipse-mosquitto:2\.1\.[0-9]+-alpine$ ]] || fail "MOSQUITTO_IMAGE must be an exact 2.1 patch tag."
    [[ "${env_ref[ZIGBEE2MQTT_IMAGE]}" =~ ^docker\.io/koenkk/zigbee2mqtt:2\.[0-9]+\.[0-9]+$ ]] || fail "ZIGBEE2MQTT_IMAGE must be an exact 2.x tag."
    [[ "${env_ref[ESPHOME_IMAGE]}" =~ ^docker\.io/esphome/esphome:[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "ESPHOME_IMAGE must be an exact tag."
    [[ "${env_ref[WMBUSMETERS_IMAGE]}" == "docker.io/wmbusmeters/wmbusmeters:release-3.0.0" ]] || fail "WMBUSMETERS_IMAGE must stay on release-3.0.0."

    env_validate_subnet_pair "DOCKER_INTERNAL" "${env_ref[DOCKER_INTERNAL_SUBNET]}" "${env_ref[DOCKER_INTERNAL_GATEWAY]}"

    env_path_ok "POSTGRESQL_HOST_DIR" "${env_ref[POSTGRESQL_HOST_DIR]}"
    local pg="${env_ref[POSTGRESQL_HOST_DIR]}"
    env_path_nested "${pg}" "${env_ref[HA_CONFIG_HOST_DIR]}" && fail "PostgreSQL and Home Assistant config directories overlap."
    case "${pg}" in
        "${DATA_DIR}"|"${DATA_DIR}"/*|"${STACK_DIR}"|"${STACK_DIR}"/*|"${GIT_DIR}"|"${GIT_DIR}"/*|"${BACKUP_LOCAL_DIR}"|"${BACKUP_LOCAL_DIR}"/*)
            fail "POSTGRESQL_HOST_DIR must stay outside this project's Git checkout, stack, application data and backups."
            ;;
    esac

    [[ "${#env_ref[PG_SUPER_PASS]}" -ge 16 && "${#env_ref[PG_SUPER_PASS]}" -le 99 ]] || fail "PG_SUPER_PASS must be 16 to 99 characters."
    [[ "${#env_ref[PG_PASS]}" -ge 16 && "${#env_ref[PG_PASS]}" -le 99 ]] || fail "PG_PASS must be 16 to 99 characters."
    [[ "${env_ref[PG_SUPER_PASS]}" != "${env_ref[PG_PASS]}" ]] || fail "PG_SUPER_PASS and PG_PASS must be different."
    [[ "${#env_ref[MQTT_PASSWORD]}" -ge 16 ]] || fail "MQTT_PASSWORD is too short."
    [[ "${#env_ref[MQTT_HA_PASSWORD]}" -ge 16 ]] || fail "MQTT_HA_PASSWORD is too short."
    [[ "${env_ref[MQTT_PASSWORD]}" != "${env_ref[MQTT_HA_PASSWORD]}" ]] || fail "MQTT_PASSWORD and MQTT_HA_PASSWORD must be different."
    [[ "${#env_ref[ESPHOME_PASSWORD]}" -ge 16 ]] || fail "ESPHOME_PASSWORD is too short."
    [[ "${env_ref[PG_USER]}" != "${POSTGRES_BOOTSTRAP_USER}" ]] || fail "PG_USER must not be the bootstrap superuser."
    [[ "${env_ref[PG_USER]}" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || fail "PG_USER is not a safe PostgreSQL role name."
    [[ "${env_ref[MQTT_USER]}" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || fail "MQTT_USER is not a safe MQTT user name."
    [[ "${env_ref[MQTT_HA_USER]}" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || fail "MQTT_HA_USER is not a safe MQTT user name."
    [[ "${env_ref[MQTT_USER]}" != "${env_ref[MQTT_HA_USER]}" ]] || fail "MQTT_USER and MQTT_HA_USER must be different."
    [[ "${env_ref[PG_DB]}" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || fail "PG_DB is not a safe database name."
    [[ "${env_ref[ESPHOME_USERNAME]}" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || fail "ESPHOME_USERNAME is not a safe dashboard user."

    env_ipv4_octets_ok "${env_ref[HA_TRUSTED_PROXY]}" || fail "HA_TRUSTED_PROXY is not an IPv4 address."
    env_ip_private "${env_ref[HA_TRUSTED_PROXY]}" || fail "HA_TRUSTED_PROXY must be a private address."
    [[ "${env_ref[HA_TRUSTED_PROXY]}" != "${DOMA_HOST_ADDRESS}" ]] || fail "HA_TRUSTED_PROXY must not be the domaPc host address ${DOMA_HOST_ADDRESS}."
    [[ "${env_ref[HA_TRUSTED_PROXY]}" != "0.0.0.0" ]] || fail "HA_TRUSTED_PROXY must not be 0.0.0.0."

    if [[ -n "${env_ref[RESTIC_REPOSITORY]}" ]]; then
        env_path_ok "RESTIC_REPOSITORY" "${env_ref[RESTIC_REPOSITORY]}"
        local restic="${env_ref[RESTIC_REPOSITORY]}"
        env_path_nested "${restic}" "${DATA_DIR}" && fail "RESTIC_REPOSITORY must not sit on the application data disk."
        env_path_nested "${restic}" "${BACKUP_LOCAL_DIR}" && fail "RESTIC_REPOSITORY must not sit in the local backup directory."
        env_path_nested "${restic}" "${STACK_DIR}" && fail "RESTIC_REPOSITORY must not sit in the stack directory."
        env_path_nested "${restic}" "${env_ref[POSTGRESQL_HOST_DIR]}" && fail "RESTIC_REPOSITORY must not sit on the PostgreSQL directory."
        [[ -n "${env_ref[RESTIC_PASSWORD]}" ]] || fail "RESTIC_PASSWORD is required when RESTIC_REPOSITORY is set."
        [[ "${#env_ref[RESTIC_PASSWORD]}" -ge 16 ]] || fail "RESTIC_PASSWORD is too short."
    fi
    if [[ -n "${env_ref[BACKUP_EXTERNAL_DIR]}" ]]; then
        env_path_ok "BACKUP_EXTERNAL_DIR" "${env_ref[BACKUP_EXTERNAL_DIR]}"
        env_path_nested "${env_ref[BACKUP_EXTERNAL_DIR]}" "${DATA_DIR}" && fail "BACKUP_EXTERNAL_DIR must not sit on the application data disk."
        env_path_nested "${env_ref[BACKUP_EXTERNAL_DIR]}" "${BACKUP_LOCAL_DIR}" && fail "BACKUP_EXTERNAL_DIR must not sit in the local backup directory."
    fi
}
