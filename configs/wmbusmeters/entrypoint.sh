#!/bin/sh
# Original telegram path: LilyGO publishes wmbus/lilygo/telegram.
# wmbusmeters decodes that stream. The MQTT password stays in the
# environment and is not written into this file.
set -eu

publish=/wmbusmeters_data/publish_mqtt.sh
if [ ! -x "${publish}" ]; then
    echo "Missing ${publish}" >&2
    exit 1
fi

exec /wmbusmeters/wmbusmeters \
    --donotprobe=all \
    --ignoreduplicates=true \
    "--shell=${publish}" \
    "hex:CMD(/usr/bin/mosquitto_sub -h mosquitto -p 1883 -u ${MQTT_USER} -P ${MQTT_PASSWORD} -t wmbus/lilygo/telegram)" \
    Apator04799531 apator162 04799531 00000000000000000000000000000000 \
    Apator04806798 apator162 04806798 00000000000000000000000000000000
