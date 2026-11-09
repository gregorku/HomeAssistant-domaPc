# Ověření

`./scripts/test.sh --static` kontroluje syntaxi, nepřítomnost Traefiku a CrowdSec v aplikačním stacku, doménu `homeassistant.serveftp.org`, USB zařízení, porty a generování hesel. Kontejnery nespouští.

Po nasazení v kontejneru:

1. `docker ps` ukazuje `ha-homeassistant`, `ha-postgresql`, `ha-mosquitto`, `ha-zigbee2mqtt`, `ha-esphome` a `ha-wmbusmeters`. Neukazuje Traefik ani CrowdSec.
2. PostgreSQL nepublikuje port 5432.
3. Z Incus kontejneru odpovídá `127.0.0.1:8123`, `:8080` a `:6052`.
4. Z VPS Traefiku vede cesta přes WireGuard wg1 na `10.100.100.100`. Home Assistant je backend port 8123 na vstupu 443. Zigbee2MQTT je backend 8080 na vstupu 8455. ESPHome je backend 6052 na vstupu 8456. MikroTik DNAT se neověřuje, dokud není zapojení potvrzené.
5. `post-deploy.sh` nevypíše heslo PostgreSQL, MQTT ani ESPHome. Mosquitto přijme účet Zigbee2MQTT i účet Home Assistantu, každý jeho vlastním heslem. Zigbee2MQTT je nastavený na `MQTT_USER`. V `secrets.yaml` jsou `mqtt_ha_user` a `mqtt_ha_password` pro ruční MQTT integraci. Samotná integrace v UI se tím neověřuje, protože ji deploy nezakládá.

`docker compose config` se na této stanici nespouštěl. Patří do cílového kontejneru:

```bash
cd /docker-data/stacks/homeassistant-domapc
docker compose --env-file .env config
```
