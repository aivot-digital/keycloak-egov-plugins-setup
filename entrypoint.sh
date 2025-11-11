#!/bin/bash

kc=/app/keycloak-config-cli.jar

# Try to apply the bootstrap master realm configuration to create the deployment client
echo "Applying bootstrap master realm configuration..."
java -jar ${kc} \
    --keycloak.url=${KEYCLOAK_URL} \
    --keycloak.user=${KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME} \
    --keycloak.password=${KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD} \
    --import.files.locations=/configs/bootstrap-master.yml

# Apply the real master realm configuration
echo "Applying master realm configuration..."
java -jar ${kc} \
    --keycloak.url=${KEYCLOAK_URL} \
    --keycloak.grant-type=client_credentials \
    --keycloak.client-id=${KEYCLOAK_DEPLOYMENT_CLIENT_NAME} \
    --keycloak.client-secret=${KEYCLOAK_DEPLOYMENT_CLIENT_SECRET} \
    --import.files.locations=/configs/master.yml

if [ $? -ne 0 ]; then
    echo "Failed to apply master realm configuration"
    exit 1
fi

# Apply the staff realm configuration
echo "Applying staff realm configuration..."
java -jar ${kc} \
    --keycloak.url=${KEYCLOAK_URL} \
    --keycloak.grant-type=client_credentials \
    --keycloak.client-id=${KEYCLOAK_DEPLOYMENT_CLIENT_NAME} \
    --keycloak.client-secret=${KEYCLOAK_DEPLOYMENT_CLIENT_SECRET} \
    --import.files.locations=/configs/staff.yml

if [ $? -ne 0 ]; then
    echo "Failed to apply staff realm configuration"
    exit 1
fi

# Apply the customer realm configuration
echo "Applying customer realm configuration..."
java -jar ${kc} \
    --keycloak.url=${KEYCLOAK_URL} \
    --keycloak.grant-type=client_credentials \
    --keycloak.client-id=${KEYCLOAK_DEPLOYMENT_CLIENT_NAME} \
    --keycloak.client-secret=${KEYCLOAK_DEPLOYMENT_CLIENT_SECRET} \
    --import.files.locations=/configs/customer.yml

if [ $? -ne 0 ]; then
    echo "Failed to apply customer realm configuration"
    exit 1
fi

echo "All configurations applied successfully."

exit 0