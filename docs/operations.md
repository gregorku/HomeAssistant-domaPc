# Provoz

## Před prvním nasazením

`check-env.sh` odmítne hodnotu začínající `set_`. `update-env.sh` doplní `PG_SUPER_PASS`, `PG_PASS`, `MQTT_PASSWORD`, `MQTT_HA_PASSWORD` a `ESPHOME_PASSWORD`. Existující hodnoty nechá. `PG_SUPER_PASS` patří bootstrap roli PostgreSQL. `PG_PASS` patří aplikační roli. `RESTIC_PASSWORD` se negeneruje. Doplní se až spolu s cestou úložiště.

Před `deploy.sh`:

- existuje adresář `POSTGRESQL_HOST_DIR` mimo Git, stack, data aplikací a zálohy;
- `DOCKER_INTERNAL_SUBNET` a brána jsou soukromý rozsah s prefixem 16–28 a nepřekrývají existující Docker síť;
- Incus kontejner má viditelné USB uzly pro SLZB-07Mg24 a `/dev/ttyUSB0` až `/dev/ttyUSB3`.

Veřejná cesta je Traefik na VPS a WireGuard wg1 na `10.100.100.100`. MikroTik DNAT se do ní zatím nezapisuje.

## Co deploy dělá

Synchronizuje `compose.yml`, `compose/`, `configs/` a `.env.example`. Persistentní data nemaže. Založí síť `ha-internal`, když chybí. Nejdřív spustí PostgreSQL a Mosquitto, založí aplikační roli a teprve potom celý Compose.

`post-deploy.sh` ověří přihlášení do PostgreSQL, oba MQTT účty, odpověď Home Assistantu na 8123, že Zigbee2MQTT používá svůj účet, ESPHome na 6052 a běžící WMBusmeters. Hesla se do logu nezapisují.

## MQTT účty

`MQTT_USER` / `MQTT_PASSWORD` patří Zigbee2MQTT. `MQTT_HA_USER` / `MQTT_HA_PASSWORD` patří Home Assistantu. Uživatelská jména bere `update-env.sh` z `.env.example`. Hesla generuje samostatně a při dalším běhu je zachová. Změna jednoho hesla v runtime `.env` druhé heslo nemění.

Mosquitto při startu zapíše chybějící účet, nebo při změně hesla vymění jen řádek tohoto účtu. Ostatní řádky v `passwd` nechá. Soubor se při restartu beze změny hesel nepřepisuje. `passwd.sha256` je checksum hesla Zigbee2MQTT a zůstává kompatibilní s dosavadním souborem. `passwd.ha.sha256` je checksum hesla Home Assistantu. Ani jeden soubor neobsahuje heslo. `mosquitto_passwd` dostane jen dočasný soubor, ne heslo jako argument.

WMBusmeters dál používá účet Zigbee2MQTT. Třetí účet tato změna nezakládá.

Healthcheck Mosquitta, odběr `wmbus/lilygo/telegram` a publikování `wmbusmeters/${METER_ID}` předávají heslo přes options file (`mosquitto_pub -o` nebo `mosquitto_sub -o`). Heslo není argument klienta. Soubor má oprávnění `0600` a maže se po skončení, při chybě i po signálu. Heslo s koncem řádku, nebo tak dlouhé, že se `-P` nevejde do řádku o 1022 znacích, klient odmítne. JSON payload zůstává argumentem `-m`, protože může obsahovat konce řádků.

`deploy.sh` drží v datovém adresáři WMBusmeters provozní `publish_mqtt.sh` a `mqtt_subscribe.sh`. Stejný obsah znovu nezapisuje. Když se šablona liší od provozní kopie, nejdřív uloží časově označenou zálohu a potom soubor atomicky nahradí. Oprávnění zůstávají `755`. Původní soubor se při chybě zápisu nemění.

Změna jednoho hesla:

1. V runtime `.env` změň jen `MQTT_PASSWORD`, nebo jen `MQTT_HA_PASSWORD`.
2. Spusť `./scripts/check-env.sh`.
3. Spusť `./scripts/deploy.sh`.

Ověření je `./scripts/post-deploy.sh`. Kontroluje, že Mosquitto běží, že oba účty v `passwd` jsou a že se každý přihlásí svým heslem. Výstup heslo neobsahuje.

Home Assistant 2026.11.0 nemá podporovaný blok `mqtt: broker:`. Výchozí `configuration.yaml` ho proto nemá. Deploy existující `configuration.yaml` v datovém adresáři nepřepisuje. Pokud v něm starý blok zůstal, smaž ho ručně, jinak Home Assistant konfiguraci odmítne.

Účet `homeassistant` v Mosquittu vznikne při startu sám. Integrace MQTT se tím nezaloží. V UI otevři Nastavení → Zařízení a služby → Přidat integraci → MQTT. Broker je `mosquitto`, port `1883`, uživatel `MQTT_HA_USER` a heslo `MQTT_HA_PASSWORD`. Deploy tyhle dvě hodnoty také zapíše do `secrets.yaml` jako `mqtt_ha_user` a `mqtt_ha_password`, soubor má oprávnění `0600`. Klíče jsou jen pro ruční přepis do formuláře. Automatické uložení integrace projekt nedělá.

## Verze

Piny se při této opravě nezvedaly. Home Assistant `2026.11.0`, PostgreSQL `18.6` a Mosquitto `2.1.2` jsou přesné stabilní tagy pro nový stack. Zigbee2MQTT `2.14.3` a ESPHome `2026.8.1` zůstávají, protože novější tag může změnit koordinátor nebo nahrávání zařízení. WMBusmeters zůstává `release-3.0.0` kvůli zpracování telegramů Apator. Přechod z PostgreSQL 16 je jen logickým dumpem, ne výměnou datového adresáře.

## Upgrade

1. Změň `HA_TAG` v `.env.example` na přesný tag `X.Y.Z`.
2. Spusť `./scripts/update-env.sh`.
3. Spusť `./scripts/upgrade.sh --confirm homeassistant-domapc`.

## Veřejné směrování

Změna VPS se do Infrastructure-netcup nezapisuje. Návrh je [infrastructure-netcup.diff](infrastructure-netcup.diff). Home Assistant v něm zůstává na portu 443 bez Authentik ForwardAuth. Zigbee2MQTT je na `8455` a ESPHome na `8456`, obě přes stávající Authentik-netcup. Prometheus na `8445` se nemění. Backend je `10.100.100.100` přes WireGuard wg1.
