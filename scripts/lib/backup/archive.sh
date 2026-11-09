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
    local archive_dir="" archive_name="" tmp_archive="" tmp_sidecar="" sum=""
    local archive_slot="" archive_slot_inode="" sidecar_slot="" sidecar_slot_inode=""
    local prev_hup="" prev_int="" prev_term="" signals_installed=0 handling_signal=0

    # A preserved file replaces the empty mktemp inode. The original inode means the slot is still unused.
    backup_pack_restore_slot() {
        local slot="$1" inode="$2" dest="$3" label="$4" current=""
        [[ -n "${slot}" ]] || return 0
        if [[ ! -e "${slot}" && ! -L "${slot}" ]]; then
            return 0
        fi
        current="$(stat -c '%i' "${slot}" 2>/dev/null || true)"
        if [[ -z "${inode}" || -z "${current}" ]]; then
            printf 'Could not identify the preserved %s %s.\n' "${label}" "${slot}" >&2
            return 1
        fi
        if [[ "${current}" == "${inode}" ]]; then
            if [[ -e "${dest}" || -L "${dest}" ]]; then
                rm -f "${slot}" || {
                    printf 'Could not remove the temporary %s slot %s.\n' "${label}" "${slot}" >&2
                    return 1
                }
                return 0
            fi
            printf 'Could not identify the preserved %s %s.\n' "${label}" "${slot}" >&2
            return 1
        fi
        if ! mv -f "${slot}" "${dest}"; then
            printf 'Could not restore the previous %s %s.\n' "${label}" "${dest}" >&2
            if ! rm -f "${dest}"; then
                printf 'Could not remove the unpublished %s %s.\n' "${label}" "${dest}" >&2
            fi
            return 1
        fi
    }

    backup_pack_drop_slot() {
        local slot="$1" label="$2"
        [[ -n "${slot}" ]] || return 0
        if [[ -e "${slot}" || -L "${slot}" ]]; then
            rm -f "${slot}" || {
                printf 'Could not remove the preserved %s %s.\n' "${label}" "${slot}" >&2
                return 1
            }
        fi
    }

    backup_pack_published() {
        local tmp="$1" dest="$2"
        [[ -n "${tmp}" && ! -e "${tmp}" && ! -L "${tmp}" && ( -e "${dest}" || -L "${dest}" ) ]]
    }

    backup_pack_resolve() {
        local error=0 new_archive=0 new_sidecar=0
        if backup_pack_published "${tmp_archive}" "${archive}"; then
            new_archive=1
        fi
        if backup_pack_published "${tmp_sidecar}" "${archive}.sha256"; then
            new_sidecar=1
        fi
        if [[ "${new_archive}" -eq 1 && "${new_sidecar}" -eq 1 ]]; then
            backup_pack_drop_slot "${archive_slot}" "archive copy" || error=1
            backup_pack_drop_slot "${sidecar_slot}" "checksum copy" || error=1
        else
            if [[ "${new_archive}" -eq 1 && -z "${archive_slot}" ]]; then
                rm -f "${archive}" || {
                    printf 'Could not remove the archive published without a checksum %s.\n' "${archive}" >&2
                    error=1
                }
            fi
            if [[ "${new_sidecar}" -eq 1 && -z "${sidecar_slot}" ]]; then
                rm -f "${archive}.sha256" || {
                    printf 'Could not remove the checksum published without the archive %s.\n' "${archive}.sha256" >&2
                    error=1
                }
            fi
            backup_pack_restore_slot "${archive_slot}" "${archive_slot_inode}" "${archive}" "archive" || error=1
            backup_pack_restore_slot "${sidecar_slot}" "${sidecar_slot_inode}" "${archive}.sha256" "checksum" || error=1
            if [[ -n "${tmp_archive}" && ( -e "${tmp_archive}" || -L "${tmp_archive}" ) ]]; then
                rm -f "${tmp_archive}" || {
                    printf 'Could not remove the temporary archive %s.\n' "${tmp_archive}" >&2
                    error=1
                }
            fi
            if [[ -n "${tmp_sidecar}" && ( -e "${tmp_sidecar}" || -L "${tmp_sidecar}" ) ]]; then
                rm -f "${tmp_sidecar}" || {
                    printf 'Could not remove the temporary checksum %s.\n' "${tmp_sidecar}" >&2
                    error=1
                }
            fi
        fi
        tmp_archive=""
        tmp_sidecar=""
        archive_slot=""
        sidecar_slot=""
        if [[ "${error}" -ne 0 ]]; then
            return 1
        fi
        return 0
    }

    restore_pack_signals() {
        [[ "${signals_installed}" -eq 1 ]] || return 0
        if [[ -n "${prev_hup}" ]]; then
            eval "${prev_hup}"
        else
            trap - HUP
        fi
        if [[ -n "${prev_int}" ]]; then
            eval "${prev_int}"
        else
            trap - INT
        fi
        if [[ -n "${prev_term}" ]]; then
            eval "${prev_term}"
        else
            trap - TERM
        fi
        signals_installed=0
    }

    backup_pack_on_signal() {
        local status="$1"
        if [[ "${handling_signal}" -eq 1 ]]; then
            return
        fi
        handling_signal=1
        if ! backup_pack_resolve; then
            restore_pack_signals
            fail "Could not roll back the archive pair."
        fi
        restore_pack_signals
        exit "${status}"
    }

    pack_fail() {
        local message="$1" rollback_failed=0
        handling_signal=1
        if ! backup_pack_resolve; then
            rollback_failed=1
        fi
        restore_pack_signals
        if [[ "${rollback_failed}" -ne 0 ]]; then
            fail "Could not roll back the archive pair after: ${message}"
        fi
        fail "${message}"
    }

    prev_hup="$(trap -p HUP)"
    prev_int="$(trap -p INT)"
    prev_term="$(trap -p TERM)"
    trap 'backup_pack_on_signal 129' HUP
    trap 'backup_pack_on_signal 130' INT
    trap 'backup_pack_on_signal 143' TERM
    signals_installed=1

    backup_write_checksums "${stage}"
    archive_dir="$(dirname "${archive}")"
    archive_name="$(basename "${archive}")"
    tmp_archive="$(mktemp "${archive_dir}/${archive_name}.XXXXXX")" || pack_fail "Could not stage the archive."
    tmp_sidecar="$(mktemp "${archive_dir}/${archive_name}.sha256.XXXXXX")" || pack_fail "Could not stage the archive checksum."
    if ! chmod 600 "${tmp_archive}" "${tmp_sidecar}"; then
        pack_fail "Could not protect the archive files."
    fi
    if ! tar -C "${stage}" -cf "${tmp_archive}" .; then
        pack_fail "Could not create the archive."
    fi
    sum="$(sha256sum < "${tmp_archive}")" || pack_fail "Could not checksum the archive."
    sum="${sum%% *}"
    if [[ -z "${sum}" ]] || ! printf '%s  %s\n' "${sum}" "${archive_name}" > "${tmp_sidecar}"; then
        pack_fail "Could not write the archive checksum."
    fi
    if ! chmod 600 "${tmp_archive}" "${tmp_sidecar}"; then
        pack_fail "Could not protect the archive files."
    fi
    if [[ -L "${archive}" ]]; then
        pack_fail "Archive path must not be a symlink."
    fi
    if [[ -e "${archive}" && ! -f "${archive}" ]]; then
        pack_fail "Archive path is not a regular file."
    fi
    if [[ -L "${archive}.sha256" ]]; then
        pack_fail "Checksum path must not be a symlink."
    fi
    if [[ -e "${archive}.sha256" && ! -f "${archive}.sha256" ]]; then
        pack_fail "Checksum path is not a regular file."
    fi
    if [[ -e "${archive}" || -L "${archive}" ]]; then
        archive_slot="$(mktemp "${archive_dir}/${archive_name}.previous.XXXXXX")" || pack_fail "Could not preserve the existing archive."
        chmod 600 "${archive_slot}" || pack_fail "Could not protect the preserved archive."
        archive_slot_inode="$(stat -c '%i' "${archive_slot}")" || pack_fail "Could not preserve the existing archive."
        if ! mv -f "${archive}" "${archive_slot}"; then
            pack_fail "Could not preserve the existing archive."
        fi
        if ! chmod 600 "${archive_slot}"; then
            pack_fail "Could not set mode 600 on the preserved archive ${archive_slot}."
        fi
    fi
    if [[ -e "${archive}.sha256" || -L "${archive}.sha256" ]]; then
        sidecar_slot="$(mktemp "${archive_dir}/${archive_name}.sha256.previous.XXXXXX")" || pack_fail "Could not preserve the existing archive checksum."
        chmod 600 "${sidecar_slot}" || pack_fail "Could not protect the preserved archive checksum."
        sidecar_slot_inode="$(stat -c '%i' "${sidecar_slot}")" || pack_fail "Could not preserve the existing archive checksum."
        if ! mv -f "${archive}.sha256" "${sidecar_slot}"; then
            pack_fail "Could not preserve the existing archive checksum."
        fi
        if ! chmod 600 "${sidecar_slot}"; then
            pack_fail "Could not set mode 600 on the preserved checksum ${sidecar_slot}."
        fi
    fi
    if ! mv -f "${tmp_archive}" "${archive}"; then
        pack_fail "Could not publish the archive."
    fi
    if ! mv -f "${tmp_sidecar}" "${archive}.sha256"; then
        pack_fail "Could not publish the archive checksum."
    fi
    if ! backup_pack_resolve; then
        restore_pack_signals
        fail "Could not remove the previous archive copy."
    fi
    restore_pack_signals
    unset -f backup_pack_restore_slot backup_pack_drop_slot backup_pack_published backup_pack_resolve restore_pack_signals backup_pack_on_signal pack_fail
}

backup_verify_archive() {
    local archive="$1" work="$2"
    [[ -f "${archive}" ]] || fail "Archive does not exist."
    if [[ -f "${archive}.sha256" ]]; then
        (
            cd "$(dirname "${archive}")"
            sha256sum -c "$(basename "${archive}").sha256" >/dev/null
        ) || fail "Archive checksum does not match."
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
