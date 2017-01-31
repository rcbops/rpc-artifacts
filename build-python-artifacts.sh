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

# bootstrap Ansible and the AIO config
cd /opt/rpc-openstack
./scripts/bootstrap-ansible.sh
./scripts/bootstrap-aio.sh

# Set override vars for the artifact build
echo "rpc_release: $(/opt/rpc-artifacts/derive-artifact-version.py)" >> /etc/openstack_deploy/user_rpco_variables_overrides.yml
echo "repo_build_wheel_selective: no" >> /etc/openstack_deploy/user_osa_variables_overrides.yml
echo "repo_build_venv_selective: no" >> /etc/openstack_deploy/user_osa_variables_overrides.yml

# Setup the repo container and build the artifacts
cd /opt/rpc-openstack/openstack-ansible/playbooks
openstack-ansible setup-hosts.yml -e container_group=repo_all
openstack-ansible repo-install.yml

if [ -z ${REPO_USER_KEY+x} ] || [ -z ${REPO_HOST+x} ] || [ -z ${REPO_HOST_PUBKEY+x} ] || [ -z ${REPO_USER+x} ]; then
  echo "Skipping upload to rpc-repo as the required env vars are not set."
else
  # Prep the ssh key for uploading to rpc-repo
  mkdir -p ~/.ssh/
  set +x
  cat $REPO_USER_KEY > ~/.ssh/repo.key
  chmod 600 ~/.ssh/repo.key
  grep "${REPO_HOST}" ~/.ssh/known_hosts || echo "${REPO_HOST} $(cat $REPO_HOST_PUBKEY)" >> ~/.ssh/known_hosts
  set -x
  #Append host to [mirrors] group
  echo "repo ansible_host=${REPO_HOST} ansible_user=${REPO_USER} ansible_ssh_private_key_file='~/.ssh/repo.key' " >> /opt/rpc-artifacts/inventory

  # Upload the artifacts to rpc-repo
  cd /opt/rpc-artifacts
  openstack-ansible -i inventory upload-python-artifacts.yml -vvv -e repo_container_name=$(lxc-ls '.*_repo_' '|' head -n1)
fi
