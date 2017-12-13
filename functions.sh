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

## Vars ----------------------------------------------------------------------

# Set rpc-repo defaults, for testing by hand
export REPO_HOST=${REPO_HOST:-localhost}
export REPO_USER=${REPO_USER:-root}
export REPO_KEYFILE=${REPO_KEYFILE:-~/.ssh/id_rsa}

export BASE_DIR=${BASE_DIR:-"/opt/rpc-openstack"}
export OA_DIR="/opt/openstack-ansible"
export OA_OVERRIDES='/etc/openstack_deploy/user_osa_variables_overrides.yml'
export RPCD_DIR="${BASE_DIR}"

export HOST_SOURCES_REWRITE=${HOST_SOURCES_REWRITE:-"yes"}
export HOST_UBUNTU_REPO=${HOST_UBUNTU_REPO:-"http://mirror.rackspace.com/ubuntu"}
export HOST_RCBOPS_REPO=${HOST_RCBOPS_REPO:-"http://rpc-repo.rackspace.com"}

# Derive the rpc_release version from the group vars
# NOTE(cloudnull): Assume the scripts path is in the process directorie
#                  otherwise fallback to the legacy path.
export RPC_RELEASE="$(${SCRIPT_PATH}/../derive-artifact-version.py || ${SCRIPT_PATH}/derive-artifact-version.py)"

# Read the OS information
source /etc/os-release
source /etc/lsb-release

## Functions -----------------------------------------------------------------

function apt_artifacts_available {

  CHECK_URL="${HOST_RCBOPS_REPO}/apt-mirror/integrated/dists/${RPC_RELEASE}-${DISTRIB_CODENAME}"

  if curl --output /dev/null --silent --head --fail ${CHECK_URL}; then
    return 0
  else
    return 1
  fi

}

function git_artifacts_available {

  CHECK_URL="${HOST_RCBOPS_REPO}/git-archives/${RPC_RELEASE}/requirements.checksum"

  if curl --output /dev/null --silent --head --fail ${CHECK_URL}; then
    return 0
  else
    return 1
  fi

}

function python_artifacts_available {

  ARCH=$(uname -p)
  CHECK_URL="${HOST_RCBOPS_REPO}/os-releases/${RPC_RELEASE}/${ID}-${VERSION_ID}-${ARCH}/MANIFEST.in"

  if curl --output /dev/null --silent --head --fail ${CHECK_URL}; then
    return 0
  else
    return 1
  fi

}

function container_artifacts_available {

  CHECK_URL="${HOST_RCBOPS_REPO}/meta/1.0/index-system"

  if curl --silent --fail ${CHECK_URL} | grep "^${ID};${DISTRIB_CODENAME};.*${RPC_RELEASE};" > /dev/null; then
    return 0
  else
    return 1
  fi

}

function safe_to_replace_artifacts {

  # This function is used by the artifact pipeline to determine whether it
  # is safe to rebuild artifacts for the current head of the mainline branch.
  # It is only ever safe when the mainline and rc branches are different
  # versions or if there is no rc branch. When this is the case, the function
  # will return 0.

  rc_branch="master-rc"

  if git show origin/${rc_branch} &>/dev/null; then
    rc_branch_version="$(git show origin/${rc_branch}:group_vars/all/release.yml \
                         | awk '/rpc_release/{print $2}' | tr -d '"')"
    if [[ "${rc_branch_version}" == "${RPC_RELEASE}" ]]; then
      return 1
    else
      return 0
    fi
  else
    return 0
  fi
}
