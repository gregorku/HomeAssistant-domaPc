#!/bin/sh
# stdout is the LilyGO telegram stream. wmbusmeters starts this command
# with /bin/sh -c and later sends SIGTERM to that process group.
# The Zigbee2MQTT account is used. The password is not a client argument.
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
    printf '%s\n' "-h mosquitto"
    printf '%s\n' "-p 1883"
    printf '%s\n' "-u ${MQTT_USER}"
    printf '%s\n' "-P ${MQTT_PASSWORD}"
    printf '%s\n' "-t wmbus/lilygo/telegram"
} > "${options}"
unset MQTT_PASSWORD
mosquitto_sub -o "${options}"
