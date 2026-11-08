#!/usr/bin/env bash
# sourced by scripts/lib loaders
deploy_ensure_one_network() {
    local name="$1" subnet="$2" gateway="$3"
    if docker network inspect "${name}" >/dev/null 2>&1; then
        local existing_subnet existing_gateway
        existing_subnet="$(docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "${name}")"
        existing_gateway="$(docker network inspect --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' "${name}")"
        [[ "${existing_subnet}" == "${subnet}" ]] || fail "Docker network ${name} already uses ${existing_subnet}, not ${subnet}. It was not changed."
        [[ "${existing_gateway}" == "${gateway}" ]] || fail "Docker network ${name} gateway is ${existing_gateway}, not ${gateway}. It was not changed."
        ok "Docker network ${name} already matches ${subnet}."
        return 0
    fi
    local other other_subnet
    while read -r other; do
        [[ -n "${other}" && "${other}" != "${name}" ]] || continue
        other_subnet="$(docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "${other}" 2>/dev/null || true)"
        [[ -n "${other_subnet}" ]] || continue
        if env_cidr_overlaps "${subnet}" "${other_subnet}"; then
            fail "Refusing to create ${name} ${subnet}: it overlaps existing network ${other} ${other_subnet}."
        fi
    done < <(docker network ls --format '{{.Name}}')
    docker network create --driver bridge --subnet "${subnet}" --gateway "${gateway}" "${name}" >/dev/null
    ok "Docker network ${name} created."
}

deploy_ensure_networks() {
    print_section "Docker networks"
    deploy_ensure_one_network "${NETWORK_INTERNAL}" "${RUNTIME_ENV[DOCKER_INTERNAL_SUBNET]}" "${RUNTIME_ENV[DOCKER_INTERNAL_GATEWAY]}"
}
