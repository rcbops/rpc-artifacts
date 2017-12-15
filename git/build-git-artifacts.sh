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

# To provide flexibility in the jobs, we have the ability to set any
# parameters that will be supplied on the ansible-playbook CLI.
export ANSIBLE_PARAMETERS=${ANSIBLE_PARAMETERS:--v}

# Set this to YES if you want to replace any existing artifacts for the current
# release with those built in this job.
export REPLACE_ARTIFACTS=${REPLACE_ARTIFACTS:-no}

# Set this to YES if you want to push any changes made in this job to rpc-repo.
export PUSH_TO_MIRROR=${PUSH_TO_MIRROR:-no}

# The BASE_DIR needs to be set to ensure that the scripts
# know it and use this checkout appropriately.
export BASE_DIR=${PWD}

export SCRIPT_PATH="$(readlink -f $(dirname ${0}))"

# As git artifacts are built after apt artifacts,
# they should be used if they are available.
export ENABLE_ARTIFACTS_APT="yes"
export ENABLE_ARTIFACTS_PYT="no"

## Main ----------------------------------------------------------------------
# Run basic setup
source ${SCRIPT_PATH}/../setup/artifact-setup.sh

# Basic host/mirror inventory
envsubst < ${SCRIPT_PATH}/../inventory > /opt/inventory

# Set the galera client version number
set_galera_client_version

# Fetch all the git repositories and generate the git artifacts
# The openstack-ansible CLI is used to ensure that the library path is set
#
openstack-ansible -i /opt/inventory \
                  ${SCRIPT_PATH}/openstackgit-update.yml \
                  -e rpc_release=${RPC_RELEASE} \
                  ${ANSIBLE_PARAMETERS}

# Figure out when it is safe to automatically replace artifacts
if [[ "$(echo ${PUSH_TO_MIRROR} | tr [a-z] [A-Z])" == "YES" ]]; then

  if git_artifacts_available; then
    # If there are artifacts for this release already, and it is not
    # safe to replace them, then set PUSH_TO_MIRROR to NO to prevent
    # them from being overwritten.
    if ! safe_to_replace_artifacts; then
      export PUSH_TO_MIRROR="NO"

    # If there are artifacts for this release already, and it is safe
    # to replace them, then set REPLACE_ARTIFACTS to YES to ensure
    # that they do get replaced.
    else
      export REPLACE_ARTIFACTS="YES"
    fi
  fi
fi

# If REPLACE_ARTIFACTS is YES then force PUSH_TO_MIRROR to YES
if [[ "$(echo ${REPLACE_ARTIFACTS} | tr [a-z] [A-Z])" == "YES" ]]; then
  export PUSH_TO_MIRROR="YES"
fi

# Only push to the mirror if PUSH_TO_MIRROR is set to "YES"
#
# This enables PR-based tests which do not change the artifacts
#
if [[ "$(echo ${PUSH_TO_MIRROR} | tr [a-z] [A-Z])" == "YES" ]]; then
    if [ -z ${REPO_USER_KEY+x} ] || [ -z ${REPO_USER+x} ] || [ -z ${REPO_HOST+x} ] || [ -z ${REPO_HOST_PUBKEY+x} ]; then
        echo "Skipping upload to rpc-repo as the REPO_* env vars are not set."
        exit 1
    else

        # Prep the ssh key for uploading to rpc-repo
        mkdir -p ~/.ssh/
        set +x
        REPO_KEYFILE=~/.ssh/repo.key
        cat $REPO_USER_KEY > ${REPO_KEYFILE}
        chmod 600 ${REPO_KEYFILE}
        set -x

        # Ensure that the repo server public key is a known host
        grep "${REPO_HOST}" ~/.ssh/known_hosts || echo "${REPO_HOST} $(cat $REPO_HOST_PUBKEY)" >> ~/.ssh/known_hosts

        # Ensure that the inventory contains all the right
        # information, including the value for REPO_KEYFILE
        envsubst < ${SCRIPT_PATH}/../inventory > /opt/inventory

        # Upload the artifacts to rpc-repo
        openstack-ansible -i /opt/inventory \
                          ${SCRIPT_PATH}/openstackgit-push-to-mirror.yml \
                          -e rpc_release=${RPC_RELEASE} \
                          ${ANSIBLE_PARAMETERS}
    fi
else
    echo "Skipping upload to rpc-repo as the PUSH_TO_MIRROR env var is not set to 'YES'."
fi
