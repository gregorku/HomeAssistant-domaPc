#!/bin/sh
# Ensures the environment-managed Mosquitto account exists in the password file.
# Other accounts in the password file are preserved.
# The password is not printed and is not passed as a process argument.
set -eu

auth=/mosquitto/config/auth
passwd_file="${auth}/passwd"
checksum_file="${auth}/passwd.sha256"
mkdir -p "${auth}" /mosquitto/data /mosquitto/log

[ -n "${MQTT_USER:-}" ] && [ -n "${MQTT_PASSWORD:-}" ] || exit 1

# MQTT_USER is validated by the project, but keep this script safe on its own.
case "${MQTT_USER}" in
    [A-Za-z_]* ) ;;
    *) echo "Invalid MQTT_USER" >&2; exit 1 ;;
esac
case "${MQTT_USER}" in
    *[!A-Za-z0-9_]* ) echo "Invalid MQTT_USER" >&2; exit 1 ;;
esac
[ "${#MQTT_USER}" -le 63 ] || { echo "Invalid MQTT_USER" >&2; exit 1; }

sum="$(printf '%s' "${MQTT_PASSWORD}" | sha256sum | awk '{print $1}')"
old=""
if [ -f "${checksum_file}" ]; then
    old="$(tr -d '[:space:]' < "${checksum_file}")"
fi

# Update only when the managed account is absent or its environment password changed.
# A temporary one-account file is hashed by mosquitto_passwd, then its hash line
# is merged into a copy of the existing password file. This preserves all other users.
managed_user_present=false
if [ -s "${passwd_file}" ] && grep -q "^${MQTT_USER}:" "${passwd_file}"; then
    managed_user_present=true
fi

if [ "${managed_user_present}" != true ] || [ "${old}" != "${sum}" ]; then
    plain="$(mktemp "${auth}/plain.XXXXXX")"
    merged="$(mktemp "${auth}/passwd.XXXXXX")"
    cleanup() {
        rm -f "${plain}" "${merged}"
    }
    trap cleanup EXIT HUP INT TERM
    chmod 600 "${plain}" "${merged}"

    # printf is a shell builtin, so the password is not a process argument.
    printf '%s:%s\n' "${MQTT_USER}" "${MQTT_PASSWORD}" > "${plain}"
    if ! mosquitto_passwd -U "${plain}" >/dev/null; then
        exit 1
    fi

    # Keep every existing account except the environment-managed account being replaced.
    if [ -s "${passwd_file}" ]; then
        awk -F: -v user="${MQTT_USER}" '$1 != user' "${passwd_file}" > "${merged}"
    fi
    cat "${plain}" >> "${merged}"

    chmod 600 "${merged}"
    chown mosquitto:mosquitto "${merged}"
    mv -f "${merged}" "${passwd_file}"
    chmod 600 "${passwd_file}"

    # This checksum tracks the environment-managed password, not the whole user file.
    checksum_tmp="$(mktemp "${auth}/passwd.sha256.XXXXXX")"
    printf '%s\n' "${sum}" > "${checksum_tmp}"
    chmod 600 "${checksum_tmp}"
    chown mosquitto:mosquitto "${checksum_tmp}"
    mv -f "${checksum_tmp}" "${checksum_file}"

    cleanup
    trap - EXIT HUP INT TERM
fi

chown mosquitto:mosquitto "${auth}" "${passwd_file}" "${checksum_file}" /mosquitto/data /mosquitto/log
chmod 700 "${auth}"
chmod 600 "${passwd_file}" "${checksum_file}"
exec mosquitto -c /mosquitto/config/mosquitto.conf
