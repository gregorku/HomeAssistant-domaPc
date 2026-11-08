# Záloha a obnova

`./scripts/backup.sh` zastaví Home Assistant, udělá `pg_dump -Fc` a archiv zveřejní až po kontrole hlavičky `PGDMP`. Do archivu přidá `configuration.yaml`, `secrets.yaml` a heslo Mosquitta, pokud už existují. Archiv má oprávnění `0600`. Home Assistant se po záloze znovu spustí.

Obnova nejdřív nic nemění:

```bash
./scripts/restore.sh \
  --archive /docker-data/backups/homeassistant-domapc/homeassistant-domapc-STAMP.tar \
  --confirm homeassistant-domapc
```

Příkaz skončí kódem 2. Druhý běh s `--replace-data` zastaví Home Assistant, obnoví databázi a nechá ho zastavený.
