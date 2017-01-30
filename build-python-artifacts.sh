#!/usr/bin/env bash
# Copyright 2014-2017 , Rackspace US, Inc.
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

## Shell Opts ----------------------------------------------------------------

set -e -u -x

## Vars ----------------------------------------------------------------------

export DEPLOY_AIO=yes

## Main ----------------------------------------------------------------------

cd /opt/rpc-openstack
./scripts/bootstrap-ansible.sh
./scripts/bootstrap-aio.sh

## Set override vars for the artifact build
echo "rpc_release: $(/opt/rpc-artifacts/derive-artifact-version.py)" >> /etc/openstack_deploy/user_rpco_variables_overrides.yml
echo "repo_build_wheel_selective: no" >> /etc/openstack_deploy/user_osa_variables_overrides.yml
echo "repo_build_venv_selective: no" >> /etc/openstack_deploy/user_osa_variables_overrides.yml

cd /opt/rpc-openstack/openstack-ansible/playbooks
openstack-ansible setup-hosts.yml -e container_group=repo_all
openstack-ansible repo-install.yml
