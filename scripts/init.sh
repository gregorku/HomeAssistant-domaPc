#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/checks/load.sh"
source "${SCRIPT_DIR}/lib/init/load.sh"
source "${SCRIPT_DIR}/lib/deploy/load.sh"

print_header "HomeAssistant-domaPc initialization"
check_environment
require_mountpoint "${DOCKER_DATA_DIR}"
init_prepare_directories
deploy_sync_stack
print_footer "Initialization completed. Next: ./scripts/update-env.sh"
