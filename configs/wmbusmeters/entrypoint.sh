#!/bin/sh
# Original telegram path: LilyGO publishes wmbus/lilygo/telegram.
# mqtt_subscribe.sh reads that topic. wmbusmeters decodes the stream.
# The MQTT password stays in the environment and is not a process argument.
set -eu

publish=/wmbusmeters_data/publish_mqtt.sh
subscribe=/wmbusmeters_data/mqtt_subscribe.sh
if [ ! -x "${publish}" ] || [ ! -x "${subscribe}" ]; then
    echo "Missing ${publish} or ${subscribe}" >&2
    exit 1
fi

exec /wmbusmeters/wmbusmeters \
    --donotprobe=all \
    --ignoreduplicates=true \
    "--shell=${publish}" \
    "hex:CMD(${subscribe})" \
    Apator04799531 apator162 04799531 00000000000000000000000000000000 \
    Apator04806798 apator162 04806798 00000000000000000000000000000000
