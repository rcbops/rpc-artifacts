#!/opt/ansible-runtime/bin/python
#
# Copyright 2017, Rackspace US, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# (c) 2017, Jean-Philippe Evrard <jean-philippe.evrard@rackspace.co.uk>

# Be the single source of truth for finding the artifact version with the static file modification.
import sys

import yaml


# Default lookups when no extra items are passed in.
FILE_NAME = '/opt/rpc-openstack/etc/openstack_deploy/group_vars/all/release.yml'
LOOKUP_KEY = 'rpc_release'


def main():
    """Lookup a specific key in a YAML file and return its value."""
    if len(sys.argv) == 3:
        file_name = sys.argv[1]
        lookup_key = sys.argv[2]
    else:
        file_name = FILE_NAME
        lookup_key = LOOKUP_KEY

    with open(file_name) as f:
        data = yaml.safe_load(f.read())

    try:
        return data[lookup_key]
    except KeyError:
        raise SystemExit('failed')


if __name__ == '__main__':
    print(main())
