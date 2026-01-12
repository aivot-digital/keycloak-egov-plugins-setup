import os
import pathlib
from os.path import join as join_path

from jinja2 import Environment, FileSystemLoader

from utils import load_csv, load_json, load_yaml, get_folders_in_dir, get_files_in_dir, flatten_auth_flow

# ------------------------------------------------
# Constants
# ------------------------------------------------

ENVIRONMENT_VAR = 'ENVIRONMENT'
DEV_ENVIRONMENT_VALUE = 'development'

REALMS_DIR = './realms'
ADDITIONAL_CLIENT_SCOPES_CSV = 'additional-client-scopes.csv'
ADDITIONAL_IDPS_DIR = 'idps'
ADDITIONAL_IDP_META_JSON = 'meta.json'
ADDITIONAL_IDP_ATTRIBUTES_CSV = 'attributes.csv'
ADDITIONAL_AUTHENTICATION_FLOWS_DIR = 'authentication-flows'

GENERATED_DIR = './.generated'

# ------------------------------------------------
# Determine environment
# ------------------------------------------------

is_dev_environment = os.getenv(ENVIRONMENT_VAR) == DEV_ENVIRONMENT_VALUE

# ------------------------------------------------
# Determine realms
# ------------------------------------------------

realms = []

for realm, realm_path in get_folders_in_dir(REALMS_DIR):
    def get_realm_path(*paths: str) -> str:
        return join_path(realm_path, *paths)


    additional_client_scopes = load_csv(get_realm_path(ADDITIONAL_CLIENT_SCOPES_CSV))

    additional_idps = []
    for idp_dir_name, idp_dir_path in get_folders_in_dir(get_realm_path(ADDITIONAL_IDPS_DIR)):
        idp_meta = load_json(join_path(idp_dir_path, ADDITIONAL_IDP_META_JSON))
        idp_attributes = load_csv(join_path(idp_dir_path, ADDITIONAL_IDP_ATTRIBUTES_CSV))

        additional_idps.append({
            **idp_meta,
            'attributes': idp_attributes
        })

    additional_authentication_flows = []
    additional_authenticator_configs = []
    for flow_name, flow_path in get_files_in_dir(get_realm_path(ADDITIONAL_AUTHENTICATION_FLOWS_DIR)):
        flow_yaml = load_yaml(flow_path)
        flattened_flow, flattened_authenticator_configs = flatten_auth_flow(flow_yaml)
        additional_authentication_flows.extend(flattened_flow)
        additional_authenticator_configs.extend(flattened_authenticator_configs)

    realms.append({
        'name': realm,
        'additional_client_scopes': additional_client_scopes,
        'additional_idps': additional_idps,
        'additional_authentication_flows': additional_authentication_flows,
        'additional_authenticator_configs': additional_authenticator_configs,
    })

# ------------------------------------------------
# Prepare output directory
# ------------------------------------------------

pathlib.Path(GENERATED_DIR).mkdir(parents=True, exist_ok=True)

# ------------------------------------------------
# Generate realms
# ------------------------------------------------

for realm in realms:
    config = {
        'idps': realm['additional_idps'],
        'stork': realm['additional_client_scopes'],
        'flows': realm['additional_authentication_flows'],
        'additional_authenticator_configs': realm['additional_authenticator_configs'],
        'is_dev': is_dev_environment,
        'is_prod': not is_dev_environment,
    }

    templates = Environment(loader=FileSystemLoader('./realms/' + realm['name']))

    template = templates.get_template('realm.yml.j2')
    output = template.render(**config)

    with open(join_path(GENERATED_DIR, realm['name'] + '.yml'), 'w', encoding='UTF-8') as f:
        f.write(output)
