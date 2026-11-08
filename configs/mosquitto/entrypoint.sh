#!/bin/sh
# Writes the Mosquitto password file from the environment.
# An existing file is kept while MQTT_PASSWORD is unchanged.
# The password is not printed and is not a command argument of this script.
set -eu

auth=/mosquitto/config/auth
mkdir -p "${auth}" /mosquitto/data /mosquitto/log

[ -n "${MQTT_USER:-}" ] && [ -n "${MQTT_PASSWORD:-}" ] || exit 1

sum="$(printf '%s' "${MQTT_PASSWORD}" | sha256sum | awk '{print $1}')"
old=""
if [ -f "${auth}/passwd.sha256" ]; then
    old="$(tr -d '[:space:]' < "${auth}/passwd.sha256")"
fi

if [ ! -s "${auth}/passwd" ] || [ "${old}" != "${sum}" ]; then
    plain="$(mktemp "${auth}/plain.XXXXXX")"
    chmod 600 "${plain}"
    # printf is a shell builtin, so the password is not a process argument.
    # mosquitto_passwd -U reads that file and replaces it with a hash.
    printf '%s:%s\n' "${MQTT_USER}" "${MQTT_PASSWORD}" > "${plain}"
    if ! mosquitto_passwd -U "${plain}" >/dev/null; then
        rm -f "${plain}"
        exit 1
    fi
    mv "${plain}" "${auth}/passwd"
    chmod 600 "${auth}/passwd"
    printf '%s\n' "${sum}" > "${auth}/passwd.sha256"
    chmod 600 "${auth}/passwd.sha256"
fi

chown mosquitto:mosquitto "${auth}" "${auth}/passwd" "${auth}/passwd.sha256" /mosquitto/data /mosquitto/log
chmod 700 "${auth}"
exec mosquitto -c /mosquitto/config/mosquitto.conf
