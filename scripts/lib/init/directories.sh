#!/usr/bin/env bash
# sourced by scripts/lib loaders
init_prepare_directories() {
    mkdir -p "${STACK_DIR}" "${DATA_DIR}" "${BACKUP_LOCAL_DIR}"
}
