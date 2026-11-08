# Provoz

## Před prvním nasazením

`check-env.sh` odmítne hodnotu začínající `set_`. `update-env.sh` doplní `PG_SUPER_PASS`, `PG_PASS`, `MQTT_PASSWORD` a `ESPHOME_PASSWORD`. Existující hodnoty nechá. `PG_SUPER_PASS` patří bootstrap roli PostgreSQL. `PG_PASS` patří aplikační roli. `RESTIC_PASSWORD` se negeneruje. Doplní se až spolu s cestou úložiště.

Před `deploy.sh`:

- existuje adresář `POSTGRESQL_HOST_DIR` mimo Git, stack, data aplikací a zálohy;
- `DOCKER_INTERNAL_SUBNET` a brána jsou soukromý rozsah s prefixem 16–28 a nepřekrývají existující Docker síť;
- Incus kontejner má viditelné USB uzly pro SLZB-07Mg24 a `/dev/ttyUSB0` až `/dev/ttyUSB3`.

Veřejná cesta je Traefik na VPS a WireGuard wg1 na `10.100.100.100`. MikroTik DNAT se do ní zatím nezapisuje.

## Co deploy dělá

Synchronizuje `compose.yml`, `compose/`, `configs/` a `.env.example`. Persistentní data nemaže. Založí síť `ha-internal`, když chybí. Nejdřív spustí PostgreSQL a Mosquitto, založí aplikační roli a teprve potom celý Compose.

`post-deploy.sh` ověří přihlášení do PostgreSQL a MQTT, odpověď Home Assistantu na 8123, Zigbee2MQTT na 8080, ESPHome na 6052 a běžící WMBusmeters. Hesla se do logu nezapisují.

## Verze

Piny se při této opravě nezvedaly. Home Assistant `2026.11.0`, PostgreSQL `18.6` a Mosquitto `2.1.2` jsou přesné stabilní tagy pro nový stack. Zigbee2MQTT `2.14.3` a ESPHome `2026.8.1` zůstávají, protože novější tag může změnit koordinátor nebo nahrávání zařízení. WMBusmeters zůstává `release-3.0.0` kvůli zpracování telegramů Apator. Přechod z PostgreSQL 16 je jen logickým dumpem, ne výměnou datového adresáře.

## Upgrade

1. Změň `HA_TAG` v `.env.example` na přesný tag `X.Y.Z`.
2. Spusť `./scripts/update-env.sh`.
3. Spusť `./scripts/upgrade.sh --confirm homeassistant-domapc`.

## Veřejné směrování

Změna VPS se do Infrastructure-netcup nezapisuje. Návrh je [infrastructure-netcup.diff](infrastructure-netcup.diff). Home Assistant v něm zůstává na portu 443 bez Authentik ForwardAuth. Zigbee2MQTT je na `8455` a ESPHome na `8456`, obě přes stávající Authentik-netcup. Prometheus na `8445` se nemění. Backend je `10.100.100.100` přes WireGuard wg1.
