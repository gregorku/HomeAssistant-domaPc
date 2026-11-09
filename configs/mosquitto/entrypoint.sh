#!/bin/sh
# Ensures the Zigbee2MQTT and Home Assistant Mosquitto accounts exist.
# MQTT_USER / MQTT_PASSWORD belong to Zigbee2MQTT.
# MQTT_HA_USER / MQTT_HA_PASSWORD belong to Home Assistant.
# A password change replaces only that account.
# Other accounts in the password file are preserved.
# Unchanged passwords do not rewrite passwd.
# Passwords are not printed and are not passed as process arguments.
# Directory variables keep the container paths unless a test sets them.
set -eu
# A failed sha256sum must fail this script. The password is not its argument.
set -o pipefail

auth="${MOSQUITTO_AUTH_DIR:-/mosquitto/config/auth}"
data_dir="${MOSQUITTO_DATA_DIR:-/mosquitto/data}"
log_dir="${MOSQUITTO_LOG_DIR:-/mosquitto/log}"
mosquitto_conf="${MOSQUITTO_CONF:-/mosquitto/config/mosquitto.conf}"
passwd_file="${auth}/passwd"
# Existing installs already store the Zigbee2MQTT password checksum here.
zigbee_checksum="${auth}/passwd.sha256"
ha_checksum="${auth}/passwd.ha.sha256"

mkdir -p "${auth}" "${data_dir}" "${log_dir}"

[ -n "${MQTT_USER:-}" ] && [ -n "${MQTT_PASSWORD:-}" ] || exit 1
[ -n "${MQTT_HA_USER:-}" ] && [ -n "${MQTT_HA_PASSWORD:-}" ] || exit 1

validate_mqtt_user() {
    label="$1"
    value="$2"
    case "${value}" in
        [A-Za-z_]*) ;;
        *) echo "Invalid ${label}" >&2; exit 1 ;;
    esac
    case "${value}" in
        *[!A-Za-z0-9_]*) echo "Invalid ${label}" >&2; exit 1 ;;
    esac
    [ "${#value}" -le 63 ] || { echo "Invalid ${label}" >&2; exit 1; }
}

validate_mqtt_user "MQTT_USER" "${MQTT_USER}"
validate_mqtt_user "MQTT_HA_USER" "${MQTT_HA_USER}"
[ "${MQTT_USER}" != "${MQTT_HA_USER}" ] || { echo "MQTT users must be different" >&2; exit 1; }

password_sha256() {
    # The checksum is a hash. The password stays on stdin of sha256sum.
    printf '%s' "$1" | sha256sum | awk '{print $1}'
}

# Return 0 when this account is absent or its environment password changed.
account_needs_update() {
    user="$1"
    sum="$2"
    checksum="$3"
    old=""
    managed_user_present=false
    if [ -s "${passwd_file}" ] && grep -q "^${user}:" "${passwd_file}"; then
        managed_user_present=true
    fi
    if [ -f "${checksum}" ]; then
        old="$(tr -d '[:space:]' < "${checksum}")"
    fi
    if [ "${managed_user_present}" = true ] && [ "${old}" = "${sum}" ]; then
        return 1
    fi
    return 0
}

# Hash one account in a temporary file and merge that single line back.
# Only mosquitto_passwd -U is used, and only on this temporary file.
apply_account() {
    user="$1"
    password="$2"
    sum="$3"
    checksum="$4"
    plain=""
    merged=""
    checksum_tmp=""
    cleanup() {
        if [ -n "${plain}" ]; then rm -f "${plain}"; fi
        if [ -n "${merged}" ]; then rm -f "${merged}"; fi
        if [ -n "${checksum_tmp}" ]; then rm -f "${checksum_tmp}"; fi
    }
    trap cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    plain="$(mktemp "${auth}/plain.XXXXXX")" || exit 1
    merged="$(mktemp "${auth}/passwd.XXXXXX")" || exit 1
    chmod 600 "${plain}" "${merged}"

    # printf is a shell builtin, so the password is not a process argument.
    printf '%s:%s\n' "${user}" "${password}" > "${plain}"
    if ! mosquitto_passwd -U "${plain}" >/dev/null; then
        exit 1
    fi

    # Keep every existing account except the one account being replaced.
    if [ -s "${passwd_file}" ]; then
        awk -F: -v user="${user}" '$1 != user' "${passwd_file}" > "${merged}"
    fi
    cat "${plain}" >> "${merged}"

    chmod 600 "${merged}"
    chown mosquitto:mosquitto "${merged}"
    # The original passwd is replaced only after the merged copy is complete.
    mv -f "${merged}" "${passwd_file}"
    merged=""
    chmod 600 "${passwd_file}"

    checksum_tmp="$(mktemp "${auth}/passwd.sha256.XXXXXX")" || exit 1
    printf '%s\n' "${sum}" > "${checksum_tmp}"
    chmod 600 "${checksum_tmp}"
    chown mosquitto:mosquitto "${checksum_tmp}"
    mv -f "${checksum_tmp}" "${checksum}"
    checksum_tmp=""

    cleanup
    trap - EXIT HUP INT TERM
    plain=""
}

zigbee_sum="$(password_sha256 "${MQTT_PASSWORD}")" || exit 1
ha_sum="$(password_sha256 "${MQTT_HA_PASSWORD}")" || exit 1

if account_needs_update "${MQTT_USER}" "${zigbee_sum}" "${zigbee_checksum}"; then
    apply_account "${MQTT_USER}" "${MQTT_PASSWORD}" "${zigbee_sum}" "${zigbee_checksum}"
fi
if account_needs_update "${MQTT_HA_USER}" "${ha_sum}" "${ha_checksum}"; then
    apply_account "${MQTT_HA_USER}" "${MQTT_HA_PASSWORD}" "${ha_sum}" "${ha_checksum}"
fi

chown mosquitto:mosquitto "${auth}" "${passwd_file}" "${zigbee_checksum}" "${ha_checksum}" "${data_dir}" "${log_dir}"
chmod 700 "${auth}"
chmod 600 "${passwd_file}" "${zigbee_checksum}" "${ha_checksum}"
exec mosquitto -c "${mosquitto_conf}"
