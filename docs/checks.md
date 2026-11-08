# Ověření

`./scripts/test.sh --static` kontroluje syntaxi, nepřítomnost Traefiku a CrowdSec v aplikačním stacku, doménu `homeassistant.serveftp.org`, USB zařízení, porty a generování hesel. Kontejnery nespouští.

Po nasazení v kontejneru:

1. `docker ps` ukazuje `ha-homeassistant`, `ha-postgresql`, `ha-mosquitto`, `ha-zigbee2mqtt`, `ha-esphome` a `ha-wmbusmeters`. Neukazuje Traefik ani CrowdSec.
2. PostgreSQL nepublikuje port 5432.
3. Z Incus kontejneru odpovídá `127.0.0.1:8123`, `:8080` a `:6052`.
4. Z VPS je služba dostupná na `10.110.100.100`. MikroTik DNAT ji předá na LAN IP kontejneru. Tu adresu je potřeba přečíst na domaPc.
5. `post-deploy.sh` nevypíše heslo PostgreSQL, MQTT ani ESPHome.

`docker compose config` se na této stanici nespouštěl. Patří do cílového kontejneru:

```bash
cd /docker-data/stacks/homeassistant-domapc
docker compose --env-file .env config
```
