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

# We want the role downloads to be done via git
# This ensures that there is no race condition with the artifacts-git job
export ANSIBLE_ROLE_FETCH_MODE="git-clone"

export SCRIPT_PATH="$(readlink -f $(dirname ${0}))"

## Main ----------------------------------------------------------------------

# Ensure no remnants (not necessary if ephemeral host, but useful for dev purposes
rm -f /opt/list

# Run basic setup
source ${SCRIPT_PATH}/../setup/artifact-setup.sh

# Set the galera client version number
GALERA_CLIENT_VERSION=$(${SCRIPT_PATH}/../derive-artifact-version.py /etc/ansible/roles/galera_client/defaults/main.yml galera_client_major_version || echo "10.1")
if ! grep -q '^galera_client_major_version' /etc/openstack_deploy/user_artifact_variables.yml; then
  echo "galera_client_major_version: ${GALERA_CLIENT_VERSION}" | tee -a /etc/openstack_deploy/user_artifact_variables.yml
else
  sed -i "s|^galera_client_major_version.*|galera_client_major_version: ${GALERA_CLIENT_VERSION}|" /etc/openstack_deploy/user_artifact_variables.yml
fi

# Bootstrap Ansible
# This script is sourced to ensure that the common
# functions and vars are available.
cd /opt/openstack-ansible

# Bootstrap the AIO configuration
bash -c "/opt/openstack-ansible/scripts/bootstrap-aio.sh"

# Remove all host group allocations to ensure
# that no containers are created in the inventory.
find /etc/openstack_deploy/conf.d/ -type f -exec rm -f {} \;

# Ensure the correct dir structure exists
mkdir -p /etc/openstack_deploy/conf.d

# Ensure the files and directories have mutable permissions
find /etc/openstack_deploy/ -type d -exec chmod 0755 {} \;
find /etc/openstack_deploy/ -type f -exec chmod 0644 {} \;

# Figure out when it is safe to automatically replace artifacts
if [[ "$(echo ${PUSH_TO_MIRROR} | tr [a-z] [A-Z])" == "YES" ]]; then

  if container_artifacts_available; then
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

# Set override vars for the artifact build
cd ${SCRIPT_PATH}/../

# If we have no pre-built python artifacts available, the whole
# container build process will fail as it is unable to find the
# right artifacts to use. To ensure that we can still do a PR test
# when there are no python artifacts, we need to override a few
# things.
if ! python_artifacts_available; then
    # As there are no wheels available for this release, we will
    # need to enable developer_mode for the role install.
    echo "developer_mode: yes" >> ${OA_OVERRIDES}

    # As there are is not pre-build constraints file available
    # we will need to use those from upstream.
    OSA_SHA=$(pushd ${OA_DIR} >/dev/null; git rev-parse HEAD; popd >/dev/null)
    REQUIREMENTS_SHA=$(awk '/requirements_git_install_branch:/ {print $2}' ${OA_DIR}/playbooks/defaults/repo_packages/openstack_services.yml)
    OSA_PIN_URL="https://raw.githubusercontent.com/openstack/openstack-ansible/${OSA_SHA}/global-requirement-pins.txt"
    REQ_PIN_URL="https://raw.githubusercontent.com/openstack/requirements/${REQUIREMENTS_SHA}/upper-constraints.txt"
    echo "pip_install_upper_constraints: ${OSA_PIN_URL} --constraint ${REQ_PIN_URL}" >> ${OA_OVERRIDES}

    # As there is no get-pip.py artifact available from rpc-repo
    # we set the var to ensure that it uses the default upstream
    # URL.
    echo "pip_upstream_url: https://bootstrap.pypa.io/get-pip.py" >> ${OA_OVERRIDES}

    # As there is no repo server in this build, and rpc-repo
    # has no packages available, ensure that the lock down
    # is disabled.
    echo "pip_lock_to_internal_repo: no" >> ${OA_OVERRIDES}
fi

# Run playbooks
cd /opt/openstack-ansible/playbooks

# If the apt artifacts are not available, then this is likely
# a PR test which is not going to upload anything, so the
# artifacts we build do not need to be strictly set to use
# the RPC-O apt repo.

# The host must only have the base Ubuntu repository configured.
# All updates (security and otherwise) must come from the RPC-O apt artifacting.
# The host sources are modified to ensure that when the containers are prepared
# they have our mirror included as the default. This happens because in the
# lxc_hosts role the host apt sources are copied into the container cache.
openstack-ansible /opt/rpc-openstack/playbooks/configure-apt-sources.yml \
                  -e "host_ubuntu_repo=http://mirror.rackspace.com/ubuntu" \
                  ${ANSIBLE_PARAMETERS}

# Setup the host
openstack-ansible setup-hosts.yml --limit "lxc_hosts,hosts"

# Move back to SCRIPT_PATH dir
cd ${SCRIPT_PATH}/../

# Build the base container
openstack-ansible containers/artifact-build-chroot.yml \
                  -e role_name=pip_install \
                  -e image_name=default \
                  ${ANSIBLE_PARAMETERS}

# Build the list of roles to build containers for
role_list=""
role_list="${role_list} kibana logstash memcached_server os_cinder"
role_list="${role_list} os_glance os_heat os_horizon os_ironic os_keystone os_neutron"
role_list="${role_list} os_nova os_swift os_tempest rabbitmq_server repo_server"
role_list="${role_list} rsyslog_server"

# Build all the containers
for cnt in ${role_list}; do
  openstack-ansible containers/artifact-build-chroot.yml \
                    -e role_name=${cnt} \
                    ${ANSIBLE_PARAMETERS}
done

# If there are no python artifacts, then the containers built are unlikely
# to be idempotent, so skip this test.
if python_artifacts_available; then
    # test one container build contents
    openstack-ansible containers/test-built-container.yml
    openstack-ansible containers/test-built-container-idempotency-test.yml | tee /tmp/output.txt; grep -q 'changed=0.*failed=0' /tmp/output.txt && { echo 'Idempotence test: pass';  } || { echo 'Idempotence test: fail' && exit 1; }
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

    # Ship it!
    openstack-ansible containers/artifact-upload.yml -i /opt/inventory -v

    # test the uploaded metadata: fetching the metadata file, fetching a
    # container, and checking integrity of the downloaded artifact.
    openstack-ansible containers/test-uploaded-container-metadata.yml -v
  fi
else
  echo "Skipping upload to rpc-repo as the PUSH_TO_MIRROR env var is not set to 'YES'."
fi
