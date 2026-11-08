#!/bin/sh
# Called by wmbusmeters for each decoded telegram.
# MQTT_USER and MQTT_PASSWORD come from the container environment.
set -eu

mosquitto_pub \
    -h mosquitto \
    -p 1883 \
    -u "${MQTT_USER}" \
    -P "${MQTT_PASSWORD}" \
    -t "wmbusmeters/${METER_ID}" \
    -m "${METER_JSON}"
