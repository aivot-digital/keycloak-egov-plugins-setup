import json
import os
import csv
import pathlib
from typing import Any

from jinja2 import Environment, FileSystemLoader

templates = Environment(loader=FileSystemLoader('./templates'))

generated_dir = pathlib.Path('./.generated')
generated_dir.mkdir(parents=True, exist_ok=True)

def load_csv(file_path: str) -> list[dict[str, str]]:
    with open(file_path, 'r', encoding='UTF-8') as f:
        reader = csv.DictReader(f, delimiter=',', quotechar='"')
        return [row for row in reader]

idp_dirs = [f.path for f in os.scandir('./data/idps') if f.is_dir()]
ipds = []
for idp_dir in idp_dirs:
    with open(os.path.join(idp_dir, 'meta.json'), 'r', encoding='UTF-8') as f:
        idp = json.load(f)
    idp['attributes'] = load_csv(os.path.join(idp_dir, 'attributes.csv'))
    ipds.append(idp)

stork = load_csv('./data/stork.csv')

def write_output(filename, content):
    with open(generated_dir / filename, 'w', encoding='UTF-8') as f:
        f.write(content)

config = {
    'idps': ipds,
    'stork': stork,
}

def build_customer(templates: Environment, config: dict[str, Any]) -> str:
    template = templates.get_template('customer.yml.j2')
    output = template.render(**config)
    return output

def build_staff(templates: Environment, config: dict[str, Any]) -> str:
    template = templates.get_template('staff.yml.j2')
    output = template.render(**config)
    return output

write_output('staff.yml', build_staff(templates, config))
write_output('customer.yml', build_customer(templates, config))
