#!/usr/bin/env bash
# sourced by scripts/lib loaders
env_is_placeholder() { [[ "$1" == set_* ]]; }
env_is_sensitive() {
    [[ "$1" == *PASSWORD* || "$1" == *SECRET* || "$1" == PG_PASS || "$1" == PG_SUPER_PASS ]]
}

env_ipv4_octets_ok() {
    local ip="$1" octet
    [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS=.
    # shellcheck disable=SC2086
    for octet in ${ip}; do
        [[ "$((10#${octet}))" -le 255 ]] || return 1
    done
}

env_ipv4_to_int() {
    local a b c d
    IFS=. read -r a b c d <<< "$1"
    printf '%s\n' $(( (10#${a} << 24) + (10#${b} << 16) + (10#${c} << 8) + 10#${d} ))
}

env_cidr_ok() {
    local cidr="$1" base prefix
    [[ "${cidr}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || return 1
    base="${cidr%/*}"
    prefix="${cidr#*/}"
    env_ipv4_octets_ok "${base}" || return 1
    [[ "$((10#${prefix}))" -le 32 ]] || return 1
}

env_cidr_contains_ip() {
    local cidr="$1" ip="$2" base prefix ip_int base_int mask
    base="${cidr%/*}"; prefix="${cidr#*/}"
    ip_int="$(env_ipv4_to_int "${ip}")"
    base_int="$(env_ipv4_to_int "${base}")"
    if [[ "${prefix}" -eq 0 ]]; then return 0; fi
    mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
    [[ $(( ip_int & mask )) -eq $(( base_int & mask )) ]]
}

env_cidr_is_network_address() {
    local cidr="$1" base prefix base_int mask network
    base="${cidr%/*}"; prefix="${cidr#*/}"
    base_int="$(env_ipv4_to_int "${base}")"
    if [[ "${prefix}" -eq 0 ]]; then
        [[ "${base}" == "0.0.0.0" ]]
        return
    fi
    mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
    network=$(( base_int & mask ))
    [[ "${network}" -eq "${base_int}" ]]
}

env_ip_private() {
    local ip="$1"
    env_cidr_contains_ip "10.0.0.0/8" "${ip}" && return 0
    env_cidr_contains_ip "172.16.0.0/12" "${ip}" && return 0
    env_cidr_contains_ip "192.168.0.0/16" "${ip}" && return 0
    env_cidr_contains_ip "100.64.0.0/10" "${ip}" && return 0
    return 1
}

env_cidr_overlaps() {
    local a="$1" b="$2"
    env_cidr_contains_ip "${a}" "${b%/*}" && return 0
    env_cidr_contains_ip "${b}" "${a%/*}" && return 0
    return 1
}

env_path_ok() {
    local name="$1" value="$2"
    [[ "${value}" == /* ]] || fail "${name} must be an absolute path."
    [[ "${value}" != "/" && "${value}" != *..* ]] || fail "${name} is not a safe path."
}

env_path_nested() {
    local a="$1" b="$2"
    [[ "${a}" == "${b}" || "${a}" == "${b}"/* || "${b}" == "${a}"/* ]]
}
