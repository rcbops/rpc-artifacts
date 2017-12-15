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
export SCRIPT_PATH="$(readlink -f $(dirname ${0}))"

## Main ----------------------------------------------------------------------

# The artifact scripts expect rpc-openstack to be checked
# out at /opt/rpc-openstack, so we need to make sure that
# it is there. The folder the script may be run from could
# be another folder (as it is in jenkins), so we check
# whether the folder has 'rpc-openstack' in the name. If it
# does, we symlink it. If not, then we clone and replace
# the artifacts-building submodule with the current working
# directory. This enables testing using the artifacts repo
# on its own.
if [[ "${PWD}" != "/opt/rpc-openstack" ]] && [[ "${PWD}" =~ "rpc-openstack" ]]; then
  ln -sfn ${PWD} /opt/rpc-openstack
else
  git clone https://github.com/rcbops/rpc-openstack.git /opt/rpc-openstack
  rm -rf /opt/rpc-openstack/scripts/artifacts-building
  ln -sfn ${PWD} /opt/rpc-openstack/scripts/artifacts-building
fi

# Install RPC-OpenStack
pushd /opt/rpc-openstack
  OSA_RELEASE="${OSA_RELEASE:-stable/pike}" ./scripts/install.sh
popd

# Source our functions
source ${SCRIPT_PATH}/../functions.sh

# Bootstrap Ansible using OSA
# We give it an a-r-r file which does not exist as the RPC-O install
# process has already downloaded the roles.
pushd /opt/openstack-ansible
  bash -c "ANSIBLE_ROLE_FILE='/tmp/does-not-exist' scripts/bootstrap-ansible.sh"
popd

# Copy the extra-var override file over
cp ${SCRIPT_PATH}/../user_*.yml /etc/openstack_deploy/

if apt_artifacts_available; then
  # Prevent the AIO bootstrap from re-implementing
  # the updates, backports and UCA sources.
  export BOOTSTRAP_OPTS='{ "bootstrap_host_apt_distribution_suffix_list": [], "uca_enable": "False" }'
fi
