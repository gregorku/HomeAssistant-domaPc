# Architektura

Vzor připojení je Nextcloud-Gr. Infrastructure-Nextcloud-Lu tím vzorem není: má vlastní Traefik v aplikačním stacku. HomeAssistant-domaPc ho nemá.

Ověřená cesta Nextcloudu:

```text
Internet
  -> HAProxy na VPS, SNI gregor.serveftp.org
  -> Traefik 10.10.10.10:443, entrypoint websecure, PROXY protocol
  -> router nextcloud-gr, TLS letsencrypt, bez Authentik ForwardAuth
  -> http://10.110.100.12:8080
```

`10.110.100.12` je v `wireguard-peers.nix` MikroTik prace, peer wg2 s `allowedIPs = 10.110.100.12/32`. Není to adresa Incus kontejneru. Nginx v kontejneru poslouchá na `192.168.12.232:8080`. VPS na `192.168.12.0/24` routu nemá. Mezi `10.110.100.12:8080` a tou LAN adresou je DNAT na MikroTiku a v tomto Gitu není.

## Stejná cesta pro domaPc

`10.110.100.100` je WireGuard adresa fyzického hostitele domaPc. Incus kontejner HomeAssistant-domaPc poběží na tomto hostiteli. Výchozí profil Incus dává kontejneru `eth0` na bridge `br0`. `incusbr0` (`10.10.10.0/24`) je NAT síť a výchozí profil ji nepoužívá. VPS má v `allowedIPs` jen `10.110.100.100/32`, takže Traefik vidí hostitele a LAN adresu kontejneru přímo nevidí.

```text
Internet
  -> HAProxy na VPS, SNI homeassistant.serveftp.org
  -> Traefik 10.10.10.10:443, entrypoint websecure
  -> WireGuard wg2
  -> domaPc 10.110.100.100
  -> MikroTik DNAT
  -> LAN IP Incus kontejneru, port 8123
  -> Docker služba Home Assistant
```

Port se nemapuje na jiné číslo. `8123` je port procesu i port na adrese hostitele. LAN IP kontejneru se doplní až po ověření na domaPc. Z tohoto checkoutu na `ntbLenovo` ověřit nešla: místní `incus list` je prázdný a není to hostitel domaPc. Historické ani cizí adresy se do DNAT neplní.

`HA_TRUSTED_PROXY=10.110.100.1` je adresa wg2 na VPS. Nextcloud má stejnou hodnotu jako `TRUSTED_PROXIES=10.110.100.1/32`. Při DNAT bez SNAT je to zdroj, který kontejner uvidí.

## DNAT na MikroTiku

Pravidla se zatím nezapisují. Cíl `to-addresses` je LAN IP Incus kontejneru ověřená na domaPc. V přehledu je `<LAN-IP-KONTEJNERU>`.

| Provoz | Příchozí adresa hostitele | Cíl po DNAT | Proč |
| --- | --- | --- | --- |
| Home Assistant | `10.110.100.100:8123` TCP | `<LAN-IP-KONTEJNERU>:8123` | Traefik, entrypoint `websecure` |
| Zigbee2MQTT | `10.110.100.100:8080` TCP | `<LAN-IP-KONTEJNERU>:8080` | Traefik, publikovaný port kontejneru |
| ESPHome | `10.110.100.100:6052` TCP | `<LAN-IP-KONTEJNERU>:6052` | Traefik. Proces poslouchá na síti kontejneru, Compose port nemapuje |

PostgreSQL, Mosquitto a WMBusmeters v této tabulce nejsou. PostgreSQL a WMBusmeters nemají port na hostiteli. Mosquitto `1883` používají zařízení v LAN přímo na LAN IP kontejneru. Do wg2 se broker nepublikuje.

```routeros
/ip firewall nat
add chain=dstnat protocol=tcp dst-address=10.110.100.100 dst-port=8123 \
    action=dst-nat to-addresses=<LAN-IP-KONTEJNERU> to-ports=8123
add chain=dstnat protocol=tcp dst-address=10.110.100.100 dst-port=8080 \
    action=dst-nat to-addresses=<LAN-IP-KONTEJNERU> to-ports=8080
add chain=dstnat protocol=tcp dst-address=10.110.100.100 dst-port=6052 \
    action=dst-nat to-addresses=<LAN-IP-KONTEJNERU> to-ports=6052
```

## Služby

| Kontejner | Port procesu | Backend pro Traefik na VPS |
| --- | --- | --- |
| `ha-homeassistant` | 8123 | `http://10.110.100.100:8123`, entrypoint `websecure` |
| `ha-zigbee2mqtt` | 8080 | `http://10.110.100.100:8080`, samostatný entrypoint |
| `ha-esphome` | 6052 na síti kontejneru | `http://10.110.100.100:6052`, entrypoint `:8456` |
| `ha-postgresql` | 5432 jen v `ha-internal` | žádný |
| `ha-mosquitto` | 1883 na kontejneru | žádný, jen LAN |
| `ha-wmbusmeters` | žádný | čte MQTT v `ha-internal` |

ESPHome má `network_mode: host`, takže `6052` poslouchá přímo na `br0` kontejneru. Samostatné mapování portu nepotřebuje.

Entrypoint `:8445` je `prometheus` a router `PathPrefix(/)` na Monitoring-netcup `10.10.10.11:9090`. Druhý router na tom entrypointu by ho zakryl. Návrh ho nemění. ESPHome dostane nový entrypoint `:8456`. Pro Zigbee2MQTT je v návrhu volný `:8452`, dokud se nezvolí jiný volný port.

## Middleware Home Assistantu

`public-chain` se nepoužije. `headers-default` a `headers-security` nastavují `frameDeny`, COOP a CORP. Nextcloud-Gr kvůli nim má vlastní `nextcloud-headers` a k nim existující `crowdsec`, `rate-limit` a `compress`. Home Assistant má stejný řetěz pod vlastními jmény. Authentik ForwardAuth v něm není. `passHostHeader: true` a `sslProxyHeaders` pro `X-Forwarded-Proto: https` jsou stejné jako u Nextcloudu. Komprese WebSocket upgrade nepřebírá.

Zigbee2MQTT a ESPHome jdou přes existující `ip-whitelist`, `headers-default`, `headers-security`, `compress` a `authentik-forward-auth`, se samostatným outpost routerem bez ForwardAuth. Vzor je `smb-mgmt-virtPc.yml`.

## Co v tomto repozitáři není

HAProxy dnes posílá `homeassistant.serveftp.org` na `10.100.100.100:22080` a `:22443`. Nextcloud už jde na Traefik `10.10.10.10:80` a `:443` s `send-proxy-v2`. Stejný cíl HAProxy je podmínka toho, aby nový router vůbec dostal provoz. Ta úprava je v NixOS a v návrhu Traefiku není. DNAT na MikroTiku doma tam také není.
