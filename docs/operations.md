# Provoz

## Před prvním nasazením

`check-env.sh` odmítne hodnotu začínající `set_`. `update-env.sh` doplní `PG_PASS`, `MQTT_PASSWORD`, `ESPHOME_PASSWORD` a `RESTIC_PASSWORD`. Existující hodnoty nechá.

Před `deploy.sh`:

- existuje adresář `POSTGRESQL_HOST_DIR` mimo Git, stack, data aplikací a zálohy;
- `DOCKER_INTERNAL_SUBNET` a brána jsou soukromý rozsah s prefixem 16–28 a nepřekrývají existující Docker síť;
- Incus kontejner má viditelné USB uzly pro SLZB-07Mg24 a `/dev/ttyUSB0` až `/dev/ttyUSB3`;
- Na domaPc je ověřená LAN IP Incus kontejneru a MikroTik má DNAT z `10.110.100.100` portů 8123, 8080 a 6052 na tuto adresu.

## Co deploy dělá

Synchronizuje `compose.yml`, `compose/`, `configs/` a `.env.example`. Persistentní data nemaže. Založí síť `ha-internal`, když chybí. Nejdřív spustí PostgreSQL a Mosquitto, založí aplikační roli a teprve potom celý Compose.

`post-deploy.sh` ověří přihlášení do PostgreSQL a MQTT, odpověď Home Assistantu na 8123, Zigbee2MQTT na 8080, ESPHome na 6052 a běžící WMBusmeters. Hesla se do logu nezapisují.

## Upgrade

1. Změň `HA_TAG` v `.env.example` na přesný tag `X.Y.Z`.
2. Spusť `./scripts/update-env.sh`.
3. Spusť `./scripts/upgrade.sh --confirm homeassistant-domapc`.

## Veřejné směrování

Změna VPS se do Infrastructure-netcup nezapisuje. Návrh je [infrastructure-netcup.diff](infrastructure-netcup.diff). HAProxy musí poslat `homeassistant.serveftp.org` na Traefik VPS. Tahle úprava HAProxy v návrhu není, protože patří do NixOS a nebyla součástí schvalovaného diffu.
