#!/bin/sh
# Confirms MQTT_USER can publish ha/health. MQTT_HA_USER is not used.
# mosquitto_pub 2.1 reads -u and -P from a mode 0600 options file.
# -o does not load the client default config, so host, port, topic and
# payload stay explicit. The password is not a client argument.
set -eu
umask 077

[ -n "${MQTT_USER:-}" ] && [ -n "${MQTT_PASSWORD:-}" ] || exit 1

# fgets in mosquitto 2.1.2 strips CR and LF. An apostrophe is ordinary text.
without_breaks="$(printf '%s' "${MQTT_PASSWORD}" | tr -d '\n\r')"
if [ "${MQTT_PASSWORD}" != "${without_breaks}" ]; then
    echo "MQTT password cannot be stored in a Mosquitto options file." >&2
    exit 1
fi
password_line="-P ${MQTT_PASSWORD}"
[ "${#password_line}" -le 1022 ] || {
    echo "MQTT password cannot be stored in a Mosquitto options file." >&2
    exit 1
}

options="$(mktemp)"
cleanup() {
    rm -f "${options}"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
chmod 600 "${options}"
{
    printf '%s\n' "-h 127.0.0.1"
    printf '%s\n' "-p 1883"
    printf '%s\n' "-u ${MQTT_USER}"
    printf '%s\n' "-P ${MQTT_PASSWORD}"
    printf '%s\n' "-t ha/health"
    printf '%s\n' "-m up"
} > "${options}"
unset MQTT_PASSWORD
mosquitto_pub -o "${options}"
