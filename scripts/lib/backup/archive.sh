#!/usr/bin/env bash

backup_archive_trees() {
    printf '%s\n' homeassistant mosquitto zigbee2mqtt esphome wmbusmeters
}

backup_dump_member() {
    printf '%s\n' postgresql/homeassistant.dump
}

backup_write_manifest() {
    local stage="$1" stamp="$2" postgres_image="$3" ha_tag="$4"
    {
        printf 'created_utc=%s\n' "${stamp}"
        printf 'stack=%s\n' "${STACK_NAME}"
        printf 'postgres_image=%s\n' "${postgres_image}"
        printf 'ha_tag=%s\n' "${ha_tag}"
        printf 'host_wg=%s\n' "${DOMA_HOST_ADDRESS}"
        printf 'members:\n'
        find "${stage}" -type f ! -name manifest.txt ! -name SHA256SUMS -printf '%P\n' | sort
    } > "${stage}/manifest.txt"
}

backup_write_checksums() {
    local stage="$1"
    (
        cd "${stage}"
        find . -type f ! -name SHA256SUMS -print0 | xargs -0 sha256sum > SHA256SUMS
    )
}

backup_pack() {
    local stage="$1" archive="$2"
    backup_write_checksums "${stage}"
    tar -C "${stage}" -cf "${archive}" .
    chmod 600 "${archive}"
    sha256sum "${archive}" > "${archive}.sha256"
    chmod 600 "${archive}.sha256"
}

backup_verify_archive() {
    local archive="$1" work="$2"
    [[ -f "${archive}" ]] || fail "Archive does not exist."
    if [[ -f "${archive}.sha256" ]]; then
        sha256sum -c "${archive}.sha256" >/dev/null || fail "Archive checksum does not match."
    fi
    mkdir -p "${work}"
    tar -C "${work}" -xf "${archive}"
    (
        cd "${work}"
        sha256sum -c SHA256SUMS >/dev/null
    ) || fail "A file inside the archive does not match SHA256SUMS."
    local member tree
    for member in manifest.txt SHA256SUMS "$(backup_dump_member)"; do
        [[ -f "${work}/${member}" ]] || fail "Archive is missing ${member}."
    done
    while IFS= read -r tree; do
        [[ -d "${work}/${tree}" ]] || fail "Archive is missing ${tree}/."
    done < <(backup_archive_trees)
    local dump_head
    dump_head="$(od -An -tx1 -N5 "${work}/$(backup_dump_member)" | tr -d ' \n')"
    [[ "${dump_head}" == "5047444d50" ]] || fail "PostgreSQL dump does not start with PGDMP."
}

backup_list_dump() {
    local dump="$1"
    require_command pg_restore
    pg_restore -l "${dump}" >/dev/null || fail "pg_restore cannot list the dump."
}
