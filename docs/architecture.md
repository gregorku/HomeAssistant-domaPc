# Architektura

HomeAssistant-domaPc je aplikační stack. Traefik, CrowdSec a Authentik běží v Infrastructure-netcup a tento projekt je neinstaluje.

## Cesta na domaPc

`10.100.100.100` je WireGuard adresa fyzického hostitele domaPc. Incus kontejner HomeAssistant-domaPc poběží na tomto hostiteli. Traefik na ni posílá provoz přes WireGuard wg1. Adresa hostitele není adresa Incus kontejneru. MikroTik DNAT do této cesty nepatří, dokud nebude ověřené skutečné síťové zapojení.

```text
VPS Traefik
  -> WireGuard wg1
  -> domaPc 10.100.100.100
  -> Docker služba
```

| Služba | Vstup na VPS | Backend | Autentizace |
| --- | --- | --- | --- |
| Home Assistant | port 443, entrypoint `websecure`, `homeassistant.serveftp.org` | `http://10.100.100.100:8123` | vlastní přihlášení Home Assistantu, bez Authentik ForwardAuth |
| Zigbee2MQTT | port 8455, entrypoint `zigbee2mqtt-domapc` | `http://10.100.100.100:8080` | stávající Authentik-netcup, ForwardAuth |
| ESPHome | port 8456, entrypoint `esphome-domapc` | `http://10.100.100.100:6052` | stávající Authentik-netcup, ForwardAuth |

Prometheus zůstává na portu `8445`. Jeho router se nemění. Nový Authentik se nezakládá a soubor Authentik-netcup se neupravuje. Zigbee2MQTT a ESPHome používají existující Embedded Outpost, `ip-whitelist`, `headers-default`, `headers-security` a `compress`. Outpost router má vyšší prioritu a ForwardAuth nemá. Služba `authentik` se sdílí z existujícího `authentik.yml`.

`HA_TRUSTED_PROXY` zůstává `10.110.100.1`, dokud se na domaPc neověří adresa, kterou Home Assistant uvidí jako bezprostřední proxy. Není to adresa hostitele `10.100.100.100`.

## Služby

| Kontejner | Port procesu | Backend pro Traefik na VPS |
| --- | --- | --- |
| `ha-homeassistant` | 8123 | `http://10.100.100.100:8123`, entrypoint `websecure` |
| `ha-zigbee2mqtt` | 8080 | `http://10.100.100.100:8080`, entrypoint `zigbee2mqtt-domapc` `:8455` |
| `ha-esphome` | 6052 na síti kontejneru | `http://10.100.100.100:6052`, entrypoint `esphome-domapc` `:8456` |
| `ha-postgresql` | 5432 jen v `ha-internal` | žádný |
| `ha-mosquitto` | 1883 na kontejneru | žádný, jen LAN |
| `ha-wmbusmeters` | žádný | čte MQTT v `ha-internal` |

Mosquitto má dva účty. `Zigbee2mqtt_domaPc` používá Zigbee2MQTT a WMBusmeters. `homeassistant` je vyhrazený integraci MQTT v Home Assistantu. Jejich hesla se spravují odděleně. Broker se v Home Assistantu 2026.11.0 ukládá v UI, ne v `configuration.yaml`.

ESPHome má `network_mode: host`, takže `6052` poslouchá přímo na `br0` kontejneru. Samostatné mapování portu nepotřebuje.

Entrypoint `:8445` zůstává Prometheu. Zigbee2MQTT má na VPS entrypoint `zigbee2mqtt-domapc` na portu `:8455`. ESPHome má entrypoint `esphome-domapc` na portu `:8456`. Oba už jsou ve statickém `traefik.yml` Infrastructure-netcup. Návrh je znovu nepřidává.

## Middleware Home Assistantu

`public-chain` se nepoužije. `headers-default` a `headers-security` nastavují `frameDeny`, COOP a CORP. Nextcloud-Gr kvůli nim má vlastní `nextcloud-headers` a k nim existující `crowdsec`, `rate-limit` a `compress`. Home Assistant má stejný řetěz pod vlastními jmény. Authentik ForwardAuth v něm není. `passHostHeader: true` a `sslProxyHeaders` pro `X-Forwarded-Proto: https` jsou stejné jako u Nextcloudu. Komprese WebSocket upgrade nepřebírá.

Zigbee2MQTT a ESPHome používají existující Authentik-netcup. Řetěz je `ip-whitelist`, `headers-default`, `headers-security`, `compress` a `authentik-forward-auth`. Outpost `/outpost.goauthentik.io/` má prioritu 100 a ForwardAuth v něm není. Nová definice Authentiku v návrhu není.

## Co v tomto repozitáři není

Návrh Traefiku je v [infrastructure-netcup.diff](infrastructure-netcup.diff). Do Infrastructure-netcup se nezapisuje. Statické porty `8455` a `8456` se znovu nepřidávají. Prometheus na `8445` v něm není. MikroTik DNAT v návrhu není.
