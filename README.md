# HomeAssistant-domaPc

Aplikační Docker Compose stack pro Incus kontejner na fyzickém hostiteli domaPc. Veřejný vstup končí na Traefiku v Infrastructure-netcup. Tento projekt proxy neinstaluje.

```text
Internet
  -> HAProxy na VPS
  -> Traefik, entrypoint websecure
  -> WireGuard wg2
  -> domaPc 10.110.100.100
  -> MikroTik DNAT
  -> LAN IP Incus kontejneru, port 8123
```

`10.110.100.100` je WireGuard adresa fyzického hostitele domaPc. Není to adresa Incus kontejneru. LAN adresa kontejneru se bere až z ověření na domaPc.

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

Home Assistant má vlastní přihlášení. Zigbee2MQTT a ESPHome se zvenku otevírají přes Authentik na VPS. Návrh této směrovačky je v [docs/infrastructure-netcup.diff](docs/infrastructure-netcup.diff) a do Infrastructure-netcup se nezapisuje.

Další popis je v [docs/architecture.md](docs/architecture.md), provoz v [docs/operations.md](docs/operations.md), zálohy v [docs/backup-restore.md](docs/backup-restore.md) a ověření v [docs/checks.md](docs/checks.md).
