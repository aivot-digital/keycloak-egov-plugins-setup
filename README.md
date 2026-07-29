# Keycloak eGov Plugins Setup

This repository builds a setup sidecar for `ghcr.io/aivot-digital/keycloak-egov-plugins`.
The sidecar renders the realm templates in `realms/` and applies the desired Keycloak
configuration with `keycloak-config-cli`.

## What It Configures

- `master` realm for administration and deployment automation
- `staff` realm for employee authentication
- `customer` realm for customer identity provider integration
- clients, roles, users, authentication flows, SMTP settings and realm policies

## Local Development

Requirements:

- Docker
- Docker Compose

Start the local test setup:

```bash
docker compose -f docker-compose.test.yml up -d --build
```

Default test credentials:

- Bootstrap admin: `admin` / `admin`
- Configured admin: `superuser` / `My-Super-Secret-Password-No.1`

The configured admin password is temporary. Keycloak will ask for a password
change after login.

## Updating A Running Setup

After changing realm templates or the entrypoint, rebuild and rerun the setup
sidecar:

```bash
docker compose -f docker-compose.test.yml up -d --build --force-recreate keycloak-setup
```

To inspect logs:

```bash
docker compose -f docker-compose.test.yml logs -f keycloak-setup
```

## Bootstrap Flow

The initial setup needs the temporary Keycloak bootstrap admin to create the
deployment client and configure its service account.

On later runs, the bootstrap admin is disabled by the managed `master` realm
configuration. The entrypoint therefore checks the credentials before importing:

1. Try authenticating with the deployment client.
2. If that works, skip the bootstrap import and apply all realm updates directly.
3. If the deployment client does not exist yet, try the bootstrap admin.
4. If the bootstrap admin works, apply `master/bootstrap-master.yml` first.
5. If both credentials are rejected, fail fast with a credential-focused log message.

This avoids waiting through the default `120s` `keycloak-config-cli` availability
timeout when the system is already configured.

## Configuration Layout

- `master/bootstrap-master.yml`: minimal first-run setup for the deployment client
- `realms/master/realm.yml.j2`: managed master realm configuration
- `realms/staff/realm.yml.j2`: staff realm configuration
- `realms/customer/realm.yml.j2`: customer realm configuration
- `realms/*/authentication-flows/`: reusable authentication flow definitions
- `realms/customer/idps/`: identity provider metadata and attribute mappings
- `build.py`: renders Jinja templates into `.generated/dev` and `.generated/prod`
- `entrypoint.sh`: applies generated configs in the container

The Docker build runs `build.py` and copies the generated files into `/configs`.
At runtime, `ENVIRONMENT=development` uses `/configs/dev`; `ENVIRONMENT=production`
uses `/configs/prod`.

## Building The Setup Image

```bash
docker build -t keycloak-egov-plugins-setup .
```

## Important Environment Variables

- `ENVIRONMENT`: `development`, `dev`, `production` or `prod`
- `KEYCLOAK_URL`: internal Keycloak URL, for example `http://keycloak:8080`
- `HOSTNAME`: external application hostname used in realm/client configuration
- `KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME`
- `KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD`
- `KEYCLOAK_DEPLOYMENT_CLIENT_NAME`
- `KEYCLOAK_DEPLOYMENT_CLIENT_SECRET`
- `KEYCLOAK_ADMIN_USERNAME`
- `KEYCLOAK_ADMIN_PASSWORD`
- `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`
- `SMTP_FROM`, `SMTP_FROM_DISPLAY`
- `BACKEND_CLIENT_SECRET`

The deployment client secret must stay stable between runs. If it changes in an
already configured system, the setup sidecar cannot authenticate with the existing
deployment client until the secret is updated in Keycloak.

## Validation

Check the Compose rendering:

```bash
docker compose -f docker-compose.test.yml config
```

Check the entrypoint syntax:

```bash
bash -n entrypoint.sh
```

Run the template rendering locally:

```bash
python3 -m pip install -r requirements.txt
python3 build.py
```
