#!/bin/bash

kc=/app/keycloak-config-cli.jar

# KEYCLOAK_URL may be provided with a trailing slash. Strip it once so token
# endpoint and keycloak-config-cli calls are built consistently.
keycloak_url="${KEYCLOAK_URL%/}"
token_endpoint="${keycloak_url}/realms/master/protocol/openid-connect/token"

# Reuse the existing keycloak-config-cli timeout for the fast credential check,
# but allow overriding it independently if needed.
auth_check_timeout="${KEYCLOAK_AUTH_CHECK_TIMEOUT:-${KEYCLOAK_AVAILABILITYCHECK_TIMEOUT:-120s}}"
auth_check_interval="${KEYCLOAK_AUTH_CHECK_INTERVAL:-2s}"

# Convert the Java/Spring duration values used in the compose files to seconds
# for shell arithmetic. Unknown values intentionally fall back to 120s.
duration_to_seconds() {
    local value="${1:-0}"
    local number

    case "${value}" in
        *ms)
            echo 1
            ;;
        *s)
            number="${value%s}"
            case "${number}" in
                ''|*[!0-9]*) echo 120 ;;
                *) echo "${number}" ;;
            esac
            ;;
        *m)
            number="${value%m}"
            case "${number}" in
                ''|*[!0-9]*) echo 120 ;;
                *) echo $((number * 60)) ;;
            esac
            ;;
        *h)
            number="${value%h}"
            case "${number}" in
                ''|*[!0-9]*) echo 120 ;;
                *) echo $((number * 3600)) ;;
            esac
            ;;
        ''|*[!0-9]*)
            echo 120
            ;;
        *)
            echo "${value}"
            ;;
    esac
}

# curl returns "000" for connection errors in some cases and an empty string in
# others. Normalize both forms so the decision logic below only handles codes.
normalize_http_status() {
    local status
    status="${1}"

    case "${status}" in
        [0-9][0-9][0-9]) echo "${status}" ;;
        *) echo "000" ;;
    esac
}

# Probe the regular update path. If this succeeds, the deployment client already
# exists and the bootstrap admin is no longer needed.
deployment_client_http_status() {
    normalize_http_status "$(curl \
        --silent \
        --output /dev/null \
        --write-out '%{http_code}' \
        --connect-timeout 2 \
        --max-time 5 \
        --data-urlencode 'grant_type=client_credentials' \
        --data-urlencode "client_id=${KEYCLOAK_DEPLOYMENT_CLIENT_NAME}" \
        --data-urlencode "client_secret=${KEYCLOAK_DEPLOYMENT_CLIENT_SECRET}" \
        "${token_endpoint}" 2>/dev/null || true)"
}

# Probe the initial setup path. If this succeeds, Keycloak is fresh enough that
# the bootstrap import can create the deployment client.
bootstrap_admin_http_status() {
    normalize_http_status "$(curl \
        --silent \
        --output /dev/null \
        --write-out '%{http_code}' \
        --connect-timeout 2 \
        --max-time 5 \
        --data-urlencode 'grant_type=password' \
        --data-urlencode 'client_id=admin-cli' \
        --data-urlencode "username=${KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME}" \
        --data-urlencode "password=${KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD}" \
        "${token_endpoint}" 2>/dev/null || true)"
}

# These statuses mean Keycloak is reachable and the token endpoint actively
# rejected the credentials. That is different from "not ready yet".
is_auth_rejected() {
    case "${1}" in
        400|401|403) return 0 ;;
        *) return 1 ;;
    esac
}

# Decide whether the bootstrap import is required before invoking
# keycloak-config-cli. This avoids the expensive 120s availability loop with a
# disabled bootstrap admin on already configured systems.
determine_bootstrap_requirement() {
    local timeout_seconds interval_seconds deadline next_log_at
    local deployment_status bootstrap_status

    timeout_seconds="$(duration_to_seconds "${auth_check_timeout}")"
    interval_seconds="$(duration_to_seconds "${auth_check_interval}")"

    if [ "${interval_seconds}" -lt 1 ]; then
        interval_seconds=1
    fi

    deadline=$((SECONDS + timeout_seconds))
    next_log_at=0

    if ! command -v curl >/dev/null 2>&1; then
        echo "curl is required for the fast Keycloak setup credential check."
        return 1
    fi

    echo "Checking Keycloak setup credentials..."

    while [ "${SECONDS}" -le "${deadline}" ]; do
        # Prefer the steady-state update credential. This is the expected path
        # for all non-initial runs of the setup sidecar.
        deployment_status="$(deployment_client_http_status)"

        if [ "${deployment_status}" = "200" ]; then
            bootstrap_required=false
            echo "Deployment client authentication succeeded. Skipping bootstrap import."
            return 0
        fi

        # Fall back to the temporary bootstrap admin only if the deployment
        # client is not usable yet.
        bootstrap_status="$(bootstrap_admin_http_status)"

        if [ "${bootstrap_status}" = "200" ]; then
            bootstrap_required=true
            echo "Bootstrap admin authentication succeeded. Bootstrap import is required."
            return 0
        fi

        # If both auth methods are explicitly rejected, waiting longer will not
        # help. Fail early with a credential-focused message.
        if is_auth_rejected "${deployment_status}" && is_auth_rejected "${bootstrap_status}"; then
            echo "Neither deployment client nor bootstrap admin credentials were accepted by Keycloak."
            echo "Check KEYCLOAK_DEPLOYMENT_CLIENT_NAME, KEYCLOAK_DEPLOYMENT_CLIENT_SECRET, KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME, and KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD."
            return 1
        fi

        # Any other status usually means startup/readiness/network timing. Keep
        # retrying, but do not spam the logs every two seconds.
        if [ "${SECONDS}" -ge "${next_log_at}" ]; then
            echo "Keycloak is not ready for setup authentication yet (deployment=${deployment_status}, bootstrap=${bootstrap_status}). Retrying..."
            next_log_at=$((SECONDS + 10))
        fi

        sleep "${interval_seconds}"
    done

    echo "Timed out after ${timeout_seconds}s while waiting for usable Keycloak setup credentials."
    return 1
}

# Initial setup only: create the deployment client and configure its service
# account while the temporary bootstrap admin still works.
run_bootstrap_import() {
    echo "Applying bootstrap master realm configuration..."
    java -jar "${kc}" \
        --keycloak.url="${KEYCLOAK_URL}" \
        --keycloak.user="${KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME}" \
        --keycloak.password="${KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD}" \
        --import.files.locations=/configs/bootstrap-master.yml
}

# Regular import path: all real realm configuration is applied through the
# deployment client service account.
run_deployment_import() {
    local name="${1}"
    local file="${2}"

    echo "Applying ${name} realm configuration..."
    java -jar "${kc}" \
        --keycloak.url="${KEYCLOAK_URL}" \
        --keycloak.grant-type=client_credentials \
        --keycloak.client-id="${KEYCLOAK_DEPLOYMENT_CLIENT_NAME}" \
        --keycloak.client-secret="${KEYCLOAK_DEPLOYMENT_CLIENT_SECRET}" \
        --import.files.locations="${file}"
}

# The image contains generated configs for dev and prod. Select the right set at
# runtime so the same image can be used in both modes.
case "${ENVIRONMENT:-production}" in
    development|dev)
        configs_dir=/configs/dev
        ;;
    production|prod)
        configs_dir=/configs/prod
        ;;
    *)
        echo "Unsupported ENVIRONMENT '${ENVIRONMENT}'. Use 'development' or 'production'."
        exit 1
        ;;
esac

# Select the realms this run applies and their names. Several staff realms are
# deployed by running the container once per staff realm.
realms="${KEYCLOAK_REALMS:-master,staff,customer}"
IFS=',' read -ra realm_templates <<< "${realms// /}"
export KEYCLOAK_STAFF_REALM_NAME="${KEYCLOAK_STAFF_REALM_NAME:-staff}"
export KEYCLOAK_CUSTOMER_REALM_NAME="${KEYCLOAK_CUSTOMER_REALM_NAME:-customer}"

# Validate before contacting Keycloak, so misconfigurations fail without waiting
# for the credential check.
for realm in "${realm_templates[@]}"; do
    case "${realm}" in
        master|staff|customer) ;;
        *)
            echo "Unsupported realm '${realm}' in KEYCLOAK_REALMS. Use 'master', 'staff' or 'customer'."
            exit 1
            ;;
    esac
done

# The names are inserted verbatim into the realm YAML, and the master realm must
# never be overwritten with the staff or customer configuration. Lowercase only,
# because Keycloak names the default role "default-roles-<lowercased name>".
for realm_name in "${KEYCLOAK_STAFF_REALM_NAME}" "${KEYCLOAK_CUSTOMER_REALM_NAME}"; do
    if [[ ! "${realm_name}" =~ ^[a-z0-9_-]+$ ]] || [ "${realm_name}" = "master" ]; then
        echo "Invalid realm name '${realm_name}'. Use only lowercase letters, digits, '_' and '-', and not 'master'."
        exit 1
    fi
done

# Importing both templates into one realm would overwrite the staff configuration.
if [ "${KEYCLOAK_STAFF_REALM_NAME}" = "${KEYCLOAK_CUSTOMER_REALM_NAME}" ]; then
    echo "KEYCLOAK_STAFF_REALM_NAME and KEYCLOAK_CUSTOMER_REALM_NAME must differ (both are '${KEYCLOAK_STAFF_REALM_NAME}')."
    exit 1
fi

echo "Selected realms: ${realm_templates[*]} (staff realm name: ${KEYCLOAK_STAFF_REALM_NAME}, customer realm name: ${KEYCLOAK_CUSTOMER_REALM_NAME})"

bootstrap_required=false

# First classify the Keycloak state. This keeps initial setup and update runs
# explicit in the logs and avoids a blind bootstrap-admin import attempt.
if ! determine_bootstrap_requirement; then
    exit 1
fi

# Only fresh systems need the bootstrap config. Existing systems skip directly to
# the deployment client imports.
if [ "${bootstrap_required}" = "true" ]; then
    if ! run_bootstrap_import; then
        echo "Failed to apply bootstrap master realm configuration"
        exit 1
    fi
fi

# Apply the selected realms in the configured order. The default puts master
# first because it owns the deployment client/admin users.
for realm in "${realm_templates[@]}"; do
    if ! run_deployment_import "${realm}" "${configs_dir}/${realm}.yml"; then
        echo "Failed to apply ${realm} realm configuration"
        exit 1
    fi
done

echo "All configurations applied successfully."

exit 0
