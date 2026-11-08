#!/usr/bin/env bash
# sourced by scripts/lib loaders
assert_sync_paths() {
    [[ -n "${GIT_DIR}" && -n "${STACK_DIR}" && -n "${DATA_DIR}" ]] || fail "A project path is empty."
    [[ "${GIT_DIR}" == /* && "${STACK_DIR}" == /* && "${DATA_DIR}" == /* ]] || fail "Project paths must be absolute."
    [[ "${GIT_DIR}" != "/" && "${STACK_DIR}" != "/" && "${DATA_DIR}" != "/" ]] || fail "Refusing to use '/'."
    [[ "${GIT_DIR}" != "${STACK_DIR}" ]] || fail "GIT_DIR and STACK_DIR must differ."
    [[ "${STACK_DIR}" == "${STACKS_DIR}/${STACK_NAME}" ]] || fail "STACK_DIR is not under this project's stack name."
    [[ "${DATA_DIR}" != "${STACK_DIR}" && "${BACKUP_LOCAL_DIR}" != "${STACK_DIR}" ]] || fail "Data and backups must stay outside the stack directory."
}

sync_tree() {
    local src="$1" dst="$2"
    mkdir -p "${dst}"
    rsync -a --delete "${src}/" "${dst}/"
}

deploy_sync_stack() {
    print_section "Synchronize stack"
    assert_sync_paths
    mkdir -p "${STACK_DIR}"
    local item src dst
    for item in "${DEPLOY_ITEMS[@]}"; do
        [[ "${item}" != /* && "${item}" != *..* ]] || fail "DEPLOY_ITEMS entry is not safe: ${item}"
        src="${GIT_DIR}/${item}"
        dst="${STACK_DIR}/${item}"
        [[ -e "${src}" ]] || fail "Missing deployment item: ${src}"
        if [[ -d "${src}" ]]; then
            sync_tree "${src}" "${dst}"
        else
            install -Dm644 "${src}" "${dst}"
        fi
        info "Synchronized ${item}"
    done
    ok "Stack files synchronized. Persistent data was not touched."
}
