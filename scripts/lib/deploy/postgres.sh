#!/usr/bin/env bash
# sourced by scripts/lib loaders
deploy_postgres_role_sql() {
    case "$1" in
        role)
            cat <<'SQL'
\getenv app_pass PGAPP_PASS
SELECT CASE
    WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')
    THEN format('ALTER ROLE %I WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L', :'app_user', :'app_pass')
    ELSE format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L', :'app_user', :'app_pass')
END
\gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', :'app_db', :'app_user')
\gexec
SQL
            ;;
        schema)
            cat <<'SQL'
SELECT format('ALTER SCHEMA public OWNER TO %I', :'app_user')
\gexec
SQL
            ;;
        *)
            return 1
            ;;
    esac
}

deploy_postgres_admin_sql() {
    local database="$1"
    docker exec -i \
        -e PGAPP_USER="${RUNTIME_ENV[PG_USER]}" \
        -e PGAPP_PASS="${RUNTIME_ENV[PG_PASS]}" \
        -e PGAPP_DB="${RUNTIME_ENV[PG_DB]}" \
        "${POSTGRESQL_CONTAINER}" \
        sh -c 'exec psql -v ON_ERROR_STOP=1 -q -U "$1" -d "$2" -v app_user="$PGAPP_USER" -v app_db="$PGAPP_DB" -f -' \
        sh "${POSTGRES_BOOTSTRAP_USER}" "${database}"
}

deploy_postgres_role() {
    print_section "Home Assistant database role"
    local user="${RUNTIME_ENV[PG_USER]}"
    local db="${RUNTIME_ENV[PG_DB]}"
    [[ "${user}" != "${POSTGRES_BOOTSTRAP_USER}" ]] || fail "Refusing to change the bootstrap superuser."
    docker exec "${POSTGRESQL_CONTAINER}" pg_isready -U "${POSTGRES_BOOTSTRAP_USER}" -d "${db}" >/dev/null 2>&1 \
        || fail "Home Assistant PostgreSQL did not become ready."
    deploy_postgres_role_sql role | deploy_postgres_admin_sql postgres \
        || fail "Unable to prepare the Home Assistant database role."
    deploy_postgres_role_sql schema | deploy_postgres_admin_sql "${db}" \
        || fail "Unable to set the Home Assistant schema owner."
    docker exec \
        -e PGPASSWORD="${RUNTIME_ENV[PG_PASS]}" \
        -e PGAPP_USER="${user}" \
        -e PGAPP_DB="${db}" \
        "${POSTGRESQL_CONTAINER}" \
        sh -c 'exec psql -v ON_ERROR_STOP=1 -q -h "$(hostname)" -U "$PGAPP_USER" -d "$PGAPP_DB" -c "SELECT 1"' \
        >/dev/null \
        || fail "Application role could not log in to ${db}."
    ok "Application role is present. The bootstrap superuser was not removed."
}
