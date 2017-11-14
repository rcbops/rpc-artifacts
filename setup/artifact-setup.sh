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
# The derive-artifact-version.py script expects the git clone to
# be at /opt/rpc-openstack, so we link the current folder there.
if [[ "${PWD}" != "/opt/rpc-openstack" ]]; then
  ln -sfn ${PWD} /opt/rpc-openstack
fi

# Install RPC-OpenStack
pushd /opt/rpc-openstack
  OSA_RELEASE="${OSA_RELEASE:-stable/pike}" ./scripts/install.sh
popd

cp ${SCRIPT_PATH}/../user_*.yml /etc/openstack_deploy/

# Set the python interpreter for consistency
if ! grep -q '^ansible_python_interpreter' /etc/openstack_deploy/user_artifact_variables.yml; then
  echo 'ansible_python_interpreter: "/usr/bin/python2"' | tee -a /etc/openstack_deploy/user_artifact_variables.yml
fi

# Source our functions
source ${SCRIPT_PATH}/../functions.sh
