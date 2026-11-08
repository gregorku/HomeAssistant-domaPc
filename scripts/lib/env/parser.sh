#!/usr/bin/env bash
# sourced by scripts/lib loaders
env_parse_file() {
    local file="$1"
    local array_name="$2"
    local line key value
    [[ -f "${file}" ]] || fail "Missing env file: ${file}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ "${line}" == *=* ]] || fail "Not a variable assignment: ${line}"
        key="${line%%=*}"
        value="${line#*=}"
        [[ "${key}" =~ ^[A-Z0-9_]+$ ]] || fail "Invalid variable name: ${key}"
        eval "${array_name}[\"${key}\"]=\"\${value}\""
    done < "${file}"
}
