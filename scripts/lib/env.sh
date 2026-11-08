#!/usr/bin/env bash

declare -gA ENV_POLICY

ENV_POLICY[TZ]="user"
ENV_POLICY[COMPOSE_PROJECT_NAME]="framework"
ENV_POLICY[DATA_DIR]="framework"
ENV_POLICY[HA_CONFIG_HOST_DIR]="framework"
ENV_POLICY[ZIGBEE2MQTT_HOST_DIR]="framework"
ENV_POLICY[ESPHOME_HOST_DIR]="framework"
ENV_POLICY[WMBUSMETERS_HOST_DIR]="framework"
ENV_POLICY[POSTGRESQL_HOST_DIR]="user"
ENV_POLICY[HA_DOMAIN]="framework"
ENV_POLICY[HA_IMAGE]="framework"
ENV_POLICY[HA_TAG]="framework"
ENV_POLICY[POSTGRES_IMAGE]="framework"
ENV_POLICY[MOSQUITTO_IMAGE]="framework"
ENV_POLICY[ZIGBEE2MQTT_IMAGE]="framework"
ENV_POLICY[ESPHOME_IMAGE]="framework"
ENV_POLICY[WMBUSMETERS_IMAGE]="framework"
ENV_POLICY[DOCKER_INTERNAL_SUBNET]="user"
ENV_POLICY[DOCKER_INTERNAL_GATEWAY]="user"
ENV_POLICY[PG_DB]="framework"
ENV_POLICY[PG_USER]="framework"
ENV_POLICY[PG_PASS]="generated"
ENV_POLICY[MQTT_USER]="framework"
ENV_POLICY[MQTT_PASSWORD]="generated"
ENV_POLICY[ESPHOME_USERNAME]="framework"
ENV_POLICY[ESPHOME_PASSWORD]="generated"
ENV_POLICY[HA_TRUSTED_PROXY]="user"
ENV_POLICY[LOG_MAX_SIZE]="framework"
ENV_POLICY[LOG_MAX_FILES]="framework"
ENV_POLICY[BACKUP_LOCAL_DIR]="framework"
ENV_POLICY[BACKUP_EXTERNAL_DIR]="user"
ENV_POLICY[BACKUP_AGE_RECIPIENT]="user"
ENV_POLICY[RESTIC_REPOSITORY]="user"
ENV_POLICY[RESTIC_PASSWORD]="generated"
ENV_POLICY[RESTIC_KEEP_DAILY]="framework"
ENV_POLICY[RESTIC_KEEP_WEEKLY]="framework"
ENV_POLICY[RESTIC_KEEP_MONTHLY]="framework"
ENV_POLICY[RESTIC_KEEP_YEARLY]="framework"
ENV_POLICY[UPGRADE_MIN_FREE_MB]="framework"

env_is_placeholder() { [[ "$1" == set_* ]]; }
env_is_sensitive() {
    [[ "$1" == *PASSWORD* || "$1" == *SECRET* || "$1" == PG_PASS ]]
}

env_parse_file() {
    local file="$1"
    local array_name="$2"
    local line key value
    [[ -f "${file}" ]] || fail "Missing env file: ${file}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ "${line}" == *=* ]] || fail "Not a variable assignment: ${line}"
        key="${line%%=*}"
        value="${line#*=}"
        [[ "${key}" =~ ^[A-Z0-9_]+$ ]] || fail "Invalid variable name: ${key}"
        eval "${array_name}[\"${key}\"]=\"\${value}\""
    done < "${file}"
}

env_generate_secret() {
    local bytes="$1" value
    require_command openssl
    value="$(openssl rand -base64 "${bytes}" | tr -d '\n')"
    [[ -n "${value}" ]] || fail "openssl returned an empty secret."
    printf '%s\n' "${value}"
}

env_generate_secret_for() {
    case "$1" in
        PG_PASS|MQTT_PASSWORD|ESPHOME_PASSWORD|RESTIC_PASSWORD) env_generate_secret 36 ;;
        *) fail "No secret generator for $1." ;;
    esac
}

env_ipv4_octets_ok() {
    local ip="$1" octet
    [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS=.
    # shellcheck disable=SC2086
    for octet in ${ip}; do
        [[ "$((10#${octet}))" -le 255 ]] || return 1
    done
}

env_ipv4_to_int() {
    local a b c d
    IFS=. read -r a b c d <<< "$1"
    printf '%s\n' $(( (10#${a} << 24) + (10#${b} << 16) + (10#${c} << 8) + 10#${d} ))
}

env_cidr_ok() {
    local cidr="$1" base prefix
    [[ "${cidr}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || return 1
    base="${cidr%/*}"
    prefix="${cidr#*/}"
    env_ipv4_octets_ok "${base}" || return 1
    [[ "$((10#${prefix}))" -le 32 ]] || return 1
}

env_cidr_contains_ip() {
    local cidr="$1" ip="$2" base prefix ip_int base_int mask
    base="${cidr%/*}"; prefix="${cidr#*/}"
    ip_int="$(env_ipv4_to_int "${ip}")"
    base_int="$(env_ipv4_to_int "${base}")"
    if [[ "${prefix}" -eq 0 ]]; then return 0; fi
    mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
    [[ $(( ip_int & mask )) -eq $(( base_int & mask )) ]]
}

env_cidr_is_network_address() {
    local cidr="$1" base prefix base_int mask network
    base="${cidr%/*}"; prefix="${cidr#*/}"
    base_int="$(env_ipv4_to_int "${base}")"
    if [[ "${prefix}" -eq 0 ]]; then
        [[ "${base}" == "0.0.0.0" ]]
        return
    fi
    mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
    network=$(( base_int & mask ))
    [[ "${network}" -eq "${base_int}" ]]
}

env_ip_private() {
    local ip="$1"
    env_cidr_contains_ip "10.0.0.0/8" "${ip}" && return 0
    env_cidr_contains_ip "172.16.0.0/12" "${ip}" && return 0
    env_cidr_contains_ip "192.168.0.0/16" "${ip}" && return 0
    env_cidr_contains_ip "100.64.0.0/10" "${ip}" && return 0
    return 1
}

env_cidr_overlaps() {
    local a="$1" b="$2"
    env_cidr_contains_ip "${a}" "${b%/*}" && return 0
    env_cidr_contains_ip "${b}" "${a%/*}" && return 0
    return 1
}

env_path_ok() {
    local name="$1" value="$2"
    [[ "${value}" == /* ]] || fail "${name} must be an absolute path."
    [[ "${value}" != "/" && "${value}" != *..* ]] || fail "${name} is not a safe path."
}

env_path_nested() {
    local a="$1" b="$2"
    [[ "${a}" == "${b}" || "${a}" == "${b}"/* || "${b}" == "${a}"/* ]]
}

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

    [[ "${#env_ref[PG_PASS]}" -ge 16 && "${#env_ref[PG_PASS]}" -le 99 ]] || fail "PG_PASS must be 16 to 99 characters."
    [[ "${#env_ref[MQTT_PASSWORD]}" -ge 16 ]] || fail "MQTT_PASSWORD is too short."
    [[ "${#env_ref[ESPHOME_PASSWORD]}" -ge 16 ]] || fail "ESPHOME_PASSWORD is too short."
    [[ "${#env_ref[RESTIC_PASSWORD]}" -ge 16 ]] || fail "RESTIC_PASSWORD is too short."
    [[ "${env_ref[PG_USER]}" != "${POSTGRES_BOOTSTRAP_USER}" ]] || fail "PG_USER must not be the bootstrap superuser."
    [[ "${env_ref[PG_USER]}" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || fail "PG_USER is not a safe PostgreSQL role name."
    [[ "${env_ref[MQTT_USER]}" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || fail "MQTT_USER is not a safe MQTT user name."
    [[ "${env_ref[PG_DB]}" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || fail "PG_DB is not a safe database name."
    [[ "${env_ref[ESPHOME_USERNAME]}" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || fail "ESPHOME_USERNAME is not a safe dashboard user."

    env_ipv4_octets_ok "${env_ref[HA_TRUSTED_PROXY]}" || fail "HA_TRUSTED_PROXY is not an IPv4 address."
    env_ip_private "${env_ref[HA_TRUSTED_PROXY]}" || fail "HA_TRUSTED_PROXY must be a private address."
    [[ "${env_ref[HA_TRUSTED_PROXY]}" != "${DOMA_WG2_ADDRESS}" ]] || fail "HA_TRUSTED_PROXY must not be the MikroTik wg2 address ${DOMA_WG2_ADDRESS}."
    [[ "${env_ref[HA_TRUSTED_PROXY]}" != "0.0.0.0" ]] || fail "HA_TRUSTED_PROXY must not be 0.0.0.0."

    if [[ -n "${env_ref[BACKUP_AGE_RECIPIENT]}" ]]; then
        [[ "${env_ref[BACKUP_AGE_RECIPIENT]}" != AGE-SECRET-KEY-* ]] || fail "BACKUP_AGE_RECIPIENT must be a public recipient."
    fi
}

declare -gA RUNTIME_ENV

env_load_runtime() {
    [[ -f "${ENV_FILE}" ]] || fail "Runtime .env is missing. Run ./scripts/update-env.sh."
    env_parse_file "${ENV_FILE}" RUNTIME_ENV
    local key
    for key in "${!ENV_POLICY[@]}"; do
        [[ -v RUNTIME_ENV["${key}"] ]] || fail "Missing variable: ${key}"
        if [[ -z "${RUNTIME_ENV[${key}]}" ]]; then
            case "${key}" in
                BACKUP_EXTERNAL_DIR|BACKUP_AGE_RECIPIENT)
                    ;;
                *) fail "Empty variable: ${key}" ;;
            esac
        fi
        if env_is_placeholder "${RUNTIME_ENV[${key}]}"; then
            fail "Placeholder is not usable: ${key}"
        fi
    done
    env_validate_runtime RUNTIME_ENV
}

env_sync_file() {
    local example="$1" target="$2"
    [[ -f "${example}" ]] || fail "Missing ${example}"
    declare -A CURRENT=()
    if [[ -f "${target}" ]]; then
        env_parse_file "${target}" CURRENT
    fi
    local tmp line key value policy existing
    tmp="$(mktemp "${target}.tmp.XXXXXX")"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# || "${line}" != *=* ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        key="${line%%=*}"
        value="${line#*=}"
        policy="${ENV_POLICY[${key}]:-user}"
        existing="${CURRENT[${key}]:-}"
        case "${policy}" in
            framework) ;;
            user)
                if [[ -n "${existing}" ]]; then
                    value="${existing}"
                fi
                ;;
            generated)
                if [[ -n "${existing}" ]] && ! env_is_placeholder "${existing}"; then
                    value="${existing}"
                else
                    value="$(env_generate_secret_for "${key}")"
                fi
                ;;
        esac
        printf '%s=%s\n' "${key}" "${value}" >> "${tmp}"
    done < "${example}"
    chmod 600 "${tmp}"
    if [[ -f "${target}" ]]; then
        cp -a "${target}" "${target}.bak-$(date +%Y%m%d-%H%M%S)"
        chmod 600 "${target}.bak-"* 2>/dev/null || true
    fi
    mv "${tmp}" "${target}"
    chmod 600 "${target}"
}
