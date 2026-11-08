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
    mosquitto_passwd -b -c "${auth}/passwd" "${MQTT_USER}" "${MQTT_PASSWORD}"
    chmod 600 "${auth}/passwd"
    printf '%s\n' "${sum}" > "${auth}/passwd.sha256"
    chmod 600 "${auth}/passwd.sha256"
fi

chown mosquitto:mosquitto "${auth}" "${auth}/passwd" "${auth}/passwd.sha256" /mosquitto/data /mosquitto/log
chmod 700 "${auth}"
exec mosquitto -c /mosquitto/config/mosquitto.conf
