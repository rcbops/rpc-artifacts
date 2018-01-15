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

# Figure out where this script is being run from
export SCRIPT_PATH="$(readlink -f $(dirname ${0}))"

# Source our functions
source ${SCRIPT_PATH}/../functions.sh

# As python artifacts are built after apt artifacts,
# they should be used if they are available.
if apt_artifacts_available; then
  export ENABLE_ARTIFACTS_APT="yes"
fi

## Main ----------------------------------------------------------------------
# Run basic setup
source ${SCRIPT_PATH}/../setup/artifact-setup.sh

# Set override vars for the artifact build
echo "repo_build_wheel_selective: no" >> ${OA_OVERRIDES}
echo "repo_build_venv_selective: no" >> ${OA_OVERRIDES}

# Set the galera client version number
set_galera_client_version

# Bootstrap the AIO configuration
cd /opt/openstack-ansible
bash -c "/opt/openstack-ansible/scripts/bootstrap-aio.sh"

# Prepare to run the playbooks
cd /opt/openstack-ansible/playbooks

# Ensure the correct dir structure exists
mkdir -p /etc/openstack_deploy/conf.d

# Ensure the files and directories have mutable permissions
find /etc/openstack_deploy/ -type d -exec chmod 0755 {} \;
find /etc/openstack_deploy/ -type f -exec chmod 0644 {} \;

# If the apt artifacts are not available, then this is likely
# a PR test which is not going to upload anything, so the
# artifacts we build do not need to be strictly set to use
# the RPC-O apt repo.
if [[ "${ENABLE_ARTIFACTS_APT}" == "yes" ]]; then
    # The python artifacts are not available at this point, so we need to
    # force the use of the upstream constraints for the pip_install role
    # to execute properly when the apt source configuration playbook
    # is executed.
    if ! python_artifacts_available; then
        # As there are is not pre-build constraints file available
        # we will need to use those from upstream.
        OSA_SHA=$(pushd ${OA_DIR} >/dev/null; git rev-parse HEAD; popd >/dev/null)
        REQUIREMENTS_SHA=$(awk '/requirements_git_install_branch:/ {print $2}' ${OA_DIR}/playbooks/defaults/repo_packages/openstack_services.yml)
        OSA_PIN_URL="https://raw.githubusercontent.com/openstack/openstack-ansible/${OSA_SHA}/global-requirement-pins.txt"
        REQ_PIN_URL="https://raw.githubusercontent.com/openstack/requirements/${REQUIREMENTS_SHA}/upper-constraints.txt"
        sed -i "s|pip_install_upper_constraints: .*|pip_install_upper_constraints: ${OSA_PIN_URL} --constraint ${REQ_PIN_URL}|" /opt/rpc-openstack/playbooks/configure-apt-sources.yml

        # As there is no get-pip.py artifact available from rpc-repo
        # we set the var to ensure that it uses the default upstream
        # URL.
        echo "s|pip_upstream_url: .*|pip_upstream_url: https://bootstrap.pypa.io/get-pip.py|" /opt/rpc-openstack/playbooks/configure-apt-sources.yml
    fi

    # The host must only have the base Ubuntu repository configured.
    # All updates (security and otherwise) must come from the RPC-O apt artifacting.
    # This is also being done to ensure that the python artifacts are built using
    # the same sources as the container artifacts will use.
    openstack-ansible /opt/rpc-openstack/playbooks/configure-apt-sources.yml \
                      -e "host_ubuntu_repo=http://mirror.rackspace.com/ubuntu" \
                      ${ANSIBLE_PARAMETERS}
fi

# Setup the repo container and build the artifacts
openstack-ansible setup-hosts.yml \
                  -e container_group=repo_all \
                  ${ANSIBLE_PARAMETERS}

openstack-ansible repo-install.yml \
                  ${ANSIBLE_PARAMETERS}


# Figure out when it is safe to automatically replace artifacts
if [[ "$(echo ${PUSH_TO_MIRROR} | tr [a-z] [A-Z])" == "YES" ]]; then

  if python_artifacts_available; then
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

# If REPLACE_ARTIFACTS is YES then set PUSH_TO_MIRROR to YES
if [[ "$(echo ${REPLACE_ARTIFACTS} | tr [a-z] [A-Z])" == "YES" ]]; then
  export PUSH_TO_MIRROR="YES"
fi

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

    # Basic host/mirror inventory
    envsubst < ${SCRIPT_PATH}/../inventory > /opt/inventory

    # Upload the artifacts to rpc-repo
    REPO_CONTAINER_NAME=$(lxc-ls -1 '.*_repo_' | head -n1)
    REPO_RELEASE_NAME=$(ls -1 /openstack/${REPO_CONTAINER_NAME}/repo/os-releases/*/ | head -n1)
    openstack-ansible -i /opt/inventory \
                      ${SCRIPT_PATH}/upload-python-artifacts.yml \
                      -e repo_container_name=${REPO_CONTAINER_NAME} \
                      -e repo_release_name=${REPO_RELEASE_NAME} \
                      ${ANSIBLE_PARAMETERS}
  fi
else
  echo "Skipping upload to rpc-repo as the PUSH_TO_MIRROR env var is not set to 'YES'."
fi
