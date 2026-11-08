#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly PROJECT_NAME="HomeAssistant-domaPc"
readonly STACK_NAME="homeassistant-domapc"

SCRIPT_DIR_RESOLVED="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR_RESOLVED}/.." && pwd)"
readonly GIT_DIR="${REPO_ROOT}"

readonly BASE_DIR="/docker-data"
readonly DATA_DIR="${BASE_DIR}/homeassistant-domapc"
readonly DOCKER_DATA_DIR="${BASE_DIR}"
readonly STACKS_DIR="${BASE_DIR}/stacks"
readonly STACK_DIR="${STACKS_DIR}/${STACK_NAME}"
readonly BACKUP_LOCAL_DIR="${BASE_DIR}/backups/${STACK_NAME}"

readonly COMPOSE_FILE="${STACK_DIR}/compose.yml"
readonly ENV_FILE="${STACK_DIR}/.env"
readonly ENV_EXAMPLE_FILE="${GIT_DIR}/.env.example"

readonly DEPLOY_ITEMS=(
    compose.yml
    compose
    configs
    .env.example
)

readonly NETWORK_INTERNAL="ha-internal"

# wg2 address of the VPS. With DNAT and without SNAT this is the
# address Home Assistant sees as the immediate TCP peer.
readonly VPS_WG2_ADDRESS="10.110.100.1"

# wg2 address of MikroTik doma. The VPS reaches this address.
# It is not the Incus container address.
readonly DOMA_WG2_ADDRESS="10.110.100.100"

readonly HA_DOMAIN="homeassistant.serveftp.org"

readonly DOCKGE_CONTAINER="dockge"
readonly DOCKGE_PORT="5001"

readonly POSTGRESQL_CONTAINER="ha-postgresql"
readonly MOSQUITTO_CONTAINER="ha-mosquitto"
readonly HA_CONTAINER="ha-homeassistant"
readonly ZIGBEE2MQTT_CONTAINER="ha-zigbee2mqtt"
readonly ESPHOME_CONTAINER="ha-esphome"
readonly WMBUSMETERS_CONTAINER="ha-wmbusmeters"

readonly HA_STATE_DIR="${DATA_DIR}/state"
readonly INSTALLED_VERSION_FILE="${HA_STATE_DIR}/installed-version"
readonly UPGRADE_LOCK_FILE="${HA_STATE_DIR}/upgrade.lock"

readonly HA_CONFIG_TEMPLATE="${GIT_DIR}/configs/homeassistant/configuration.yaml"
readonly WMBUS_PUBLISH_TEMPLATE="${GIT_DIR}/configs/wmbusmeters/publish_mqtt.sh"

readonly ZIGBEE_DEVICE="/dev/serial/by-id/usb-SMLIGHT_SMLIGHT_SLZB-07Mg24_0ab50f4025adef1196c58a4ba8793231-if00-port0"

readonly POSTGRESQL_UID_GID="999:999"
readonly MOSQUITTO_UID_GID="1883:1883"
readonly POSTGRES_BOOTSTRAP_USER="ha_bootstrap"

readonly COLOR_RED="\033[0;31m"
readonly COLOR_GREEN="\033[0;32m"
readonly COLOR_YELLOW="\033[1;33m"
readonly COLOR_BLUE="\033[0;34m"
readonly COLOR_RESET="\033[0m"
