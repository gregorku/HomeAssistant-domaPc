# HomeAssistant-domaPc

Aplikační Docker Compose stack pro Incus kontejner na fyzickém hostiteli domaPc. Veřejný vstup končí na Traefiku v Infrastructure-netcup. Tento projekt proxy neinstaluje.

```text
Internet
  -> HAProxy na VPS
  -> Traefik v Infrastructure-netcup
  -> WireGuard wg1
  -> domaPc 10.100.100.100
```

`10.100.100.100` je WireGuard adresa fyzického hostitele domaPc. Není to adresa Incus kontejneru. MikroTik DNAT v této cestě není, dokud nebude ověřené skutečné zapojení.

## Pořadí skriptů

Skripty se spouštějí jako root v kontejneru, z checkoutu repozitáře.

1. `./scripts/init.sh` zkopíruje Compose a konfiguraci do `/docker-data/stacks/homeassistant-domapc`.
2. `./scripts/update-env.sh` vytvoří nebo doplní runtime `.env`. Vygenerovaná hesla se nevypisují a při dalším běhu se nemění.
3. `./scripts/check-env.sh` ověří povinné hodnoty.
4. `./scripts/deploy.sh` připraví data, síť `ha-internal` a spustí Compose.
5. `./scripts/post-deploy.sh` ověří PostgreSQL, MQTT, Home Assistant, Zigbee2MQTT, ESPHome a WMBusmeters.

`./scripts/test.sh --static` kontejnery nespouští.

## Služby

| Kontejner | Účel | Port na kontejneru |
| --- | --- | --- |
| `ha-homeassistant` | Home Assistant 2026.11.0 | `8123` |
| `ha-postgresql` | PostgreSQL 18.6 | žádný |
| `ha-mosquitto` | MQTT 2.1.2 | `1883` pro zařízení v LAN |
| `ha-zigbee2mqtt` | Zigbee2MQTT, SLZB-07Mg24 | `8080` |
| `ha-esphome` | ESPHome dashboard, čtyři USB porty | `6052` přes síť kontejneru |
| `ha-wmbusmeters` | dekódování telegramů z `wmbus/lilygo/telegram` | žádný |

## MQTT účty

Mosquitto má dva účty z runtime `.env`. `update-env.sh` hesla vygeneruje jen tehdy, když v `.env` ještě nejsou. Další běh je nemění.

| Účet | Uživatel | Heslo | Kdo se jím přihlašuje |
| --- | --- | --- | --- |
| Zigbee2MQTT | `MQTT_USER` (`Zigbee2mqtt_domaPc`) | `MQTT_PASSWORD` | Zigbee2MQTT a stávající WMBusmeters |
| Home Assistant | `MQTT_HA_USER` (`homeassistant`) | `MQTT_HA_PASSWORD` | jen Home Assistant |

Změna jednoho hesla v `.env` a následný `deploy.sh` přepíše v souboru `passwd` jen tento účet. Druhé heslo i případné další MQTT účty zůstanou. Hesla se do logu nezapisují.

Home Assistant 2026.11.0 broker v YAML nekonfiguruje. Účet v Mosquittu vznikne automaticky. Integraci MQTT je potřeba uložit v UI: Nastavení → Zařízení a služby → Přidat integraci → MQTT, broker `mosquitto`, port `1883`. Uživatel a heslo jsou `MQTT_HA_USER` a `MQTT_HA_PASSWORD`. Stejné hodnoty jsou v `secrets.yaml` jako `mqtt_ha_user` a `mqtt_ha_password`. Samy o sobě integraci nepřihlásí.

Home Assistant jde na port 443 entrypointu `websecure` a má vlastní přihlášení, bez Authentik ForwardAuth. Zigbee2MQTT je na portu VPS `8455` a ESPHome na `8456`. Obě chrání stávající Authentik-netcup přes Authentik ForwardAuth, Embedded Outpost, `ip-whitelist` a bezpečnostní middleware. Nový Authentik se nezakládá a Authentik-netcup se nemění. Prometheus zůstává na `8445`. Návrh je v [docs/infrastructure-netcup.diff](docs/infrastructure-netcup.diff) a do Infrastructure-netcup se nezapisuje.

Další popis je v [docs/architecture.md](docs/architecture.md), provoz v [docs/operations.md](docs/operations.md), zálohy v [docs/backup-restore.md](docs/backup-restore.md) a ověření v [docs/checks.md](docs/checks.md).
