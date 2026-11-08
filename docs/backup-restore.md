# Záloha a obnova

Archiv je nešifrovaný tar. Age se nepoužívá. `RESTIC_REPOSITORY` a `BACKUP_EXTERNAL_DIR` zůstávají prázdné, dokud není známá cesta mimo disk s produkčními daty. Na stejném disku je cesta odmítnuta.

## Obsah archivu

- `manifest.txt` s časem a seznamem souborů
- `SHA256SUMS` všech souborů v archivu a `archiv.tar.sha256` pro celý tar
- `postgresql/homeassistant.dump`, logický dump `pg_dump -Fc`
- celý adresář Home Assistantu, včetně `.storage`, automatizací a secrets
- Mosquitto data, log, hesla a kopie konfiguračních souborů z repozitáře
- Zigbee2MQTT, ESPHome a WMBusmeters včetně `publish_mqtt.sh`

Před dumpeem se zastaví Home Assistant, Zigbee2MQTT, ESPHome, WMBusmeters a Mosquitto. PostgreSQL zůstane běžet a dump se udělá rolí `ha_bootstrap`. Po úspěchu i po chybě se zastavené služby znovu spustí.

Restic, pokud je později nastavený, zálohuje až ověřený tar a retenci spustí až po této záloze.

## Obnova

Kontrola bez zápisu do produkce:

```bash
./scripts/restore.sh \
  --archive /docker-data/backups/homeassistant-domapc/homeassistant-domapc-STAMP.tar \
  --target /docker-data/restore-test/homeassistant-domapc \
  --confirm homeassistant-domapc
```

`--target` nesmí ležet v datech, stacku, Gitu, zálohách ani v adresáři PostgreSQL. Produkce se nemění.

Přepis produkce:

```bash
./scripts/restore.sh \
  --archive /cesta/k/archivu.tar \
  --confirm homeassistant-domapc \
  --replace-data
```

Nejdřív se ověří kontrolní součty a `pg_restore -l`. Pak se vytvoří bezpečnostní záloha, služby se zastaví, obnoví se všech pět adresářů a dump do PostgreSQL 18. Server jiné hlavní verze se odmítne.

## Migrace PostgreSQL 16

Stará data v `/zfs-data/postgres-db-homeassistant/data` se nespouštějí pod PostgreSQL 18.6.

```bash
./scripts/migrate-postgres.sh --confirm homeassistant-domapc
```

Příkaz udělá `pg_dump -Fc` z kontejneru `db-homeassistant` a ověří ho `pg_restore -l`. Starý kontejner ani jeho adresář nemaže. Obnova do nové databáze je až druhý běh s `--restore-into-new`, když už běží PostgreSQL 18.6 a role z `deploy.sh`.
