import csv
import json
import os
from uuid import uuid4
from typing import Any

import yaml


def get_folders_in_dir(dir_path: str) -> list[tuple[str, str]]:
    # Check if directory exists
    if not os.path.exists(dir_path):
        return []
    return [(f.name, f.path) for f in os.scandir(dir_path) if f.is_dir()]


def get_files_in_dir(dir_path: str) -> list[tuple[str, str]]:
    # Check if directory exists
    if not os.path.exists(dir_path):
        return []
    return [(f.name, f.path) for f in os.scandir(dir_path) if f.is_file()]


def load_csv(file_path: str) -> list[dict[str, str]]:
    # Check if file exists
    if not os.path.exists(file_path):
        return []

    # Load CSV file and return list of dictionaries
    with open(file_path, 'r', encoding='UTF-8') as f:
        reader = csv.DictReader(f, delimiter=',', quotechar='"')
        return [row for row in reader]


def load_yaml(file_path: str) -> dict[str, Any]:
    # Check if file exists
    if not os.path.exists(file_path):
        return {}

    # Load YAML file and return dictionary
    with open(file_path, 'r', encoding='UTF-8') as f:
        return yaml.safe_load(f)


def load_json(file_path: str) -> dict[str, Any]:
    # Check if file exists
    if not os.path.exists(file_path):
        return {}

    # Load JSON file and return dictionary
    with open(file_path, 'r', encoding='UTF-8') as f:
        return json.load(f)


def flatten_auth_flow(auth_flow: dict[str, Any], is_top_level=True) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    authenticator_configs = []

    priority_counter = 0
    authentication_executions = []
    for step in auth_flow['steps']:
        if 'alias' in step:
            authentication_executions.append({
                'authenticatorFlow': True,
                'requirement': step.get('requirement', 'REQUIRED'),
                'priority': priority_counter * 10,  # TODO
                'autheticatorFlow': True,
                'flowAlias': step['alias'],
                'userSetupAllowed': False
            })
        else:
            authentication_executions.append({
                "authenticator": step['auth'],
                "authenticatorFlow": False,
                "requirement": step.get('requirement', 'REQUIRED'),
                "priority": priority_counter * 10,  # TODO
                "autheticatorFlow": False,
                "userSetupAllowed": False,
            })
        priority_counter += 1

        if 'authenticatorConfig' in step:
            authenticator_configs.append(step['authenticatorConfig'])
            authentication_executions[-1]['authenticatorConfig'] = step['authenticatorConfig']

    res = [{
        'id': str(uuid4()),
        'alias': auth_flow['alias'],
        'description': auth_flow.get('description', ''),
        'providerId': 'basic-flow',
        'topLevel': is_top_level,
        'builtIn': False,
        'authenticationExecutions': authentication_executions
    }]

    for step in auth_flow['steps']:
        if 'alias' not in step:
            continue

        sub, sub2 = flatten_auth_flow(step, is_top_level=False)

        res.extend(sub)
        authenticator_configs.extend(sub2)

    return res, authenticator_configs
