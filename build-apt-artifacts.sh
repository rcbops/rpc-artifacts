#!/bin/bash
set -e
set -o pipefail

#git clone ${RPC_ARTIFACTS} rpc-artifacts
#cd rpc-artifacts
mkdir -p ~/.ssh/
mkdir -p ${RPC_ARTIFACTS_FOLDER}
mkdir -p ${RPC_ARTIFACTS_PUBLIC_FOLDER}

set +x
cat $REPO_USER_KEY > ~/.ssh/repo.key
chmod 600 ~/.ssh/repo.key
cat $GPG_PRIVATE > ${RPC_ARTIFACTS_FOLDER}/aptly.private.key
cat $GPG_PUBLIC > ${RPC_ARTIFACTS_FOLDER}/aptly.public.key
set -x

grep "${REPO_HOST}" ~/.ssh/known_hosts || echo "${REPO_HOST} $(cat $REPO_HOST_PUBKEY)" >> ~/.ssh/known_hosts
apt-get update
xargs apt-get install -y < bindep.txt
curl https://bootstrap.pypa.io/get-pip.py | python
pip install ansible==2.2

#Append host to [mirrors] group
echo "repo ansible_host=${REPO_HOST} ansible_user=${REPO_USER} ansible_ssh_private_key_file='~/.ssh/repo.key' " >> inventory

ansible-playbook aptly-pre-install.yml ${ANSIBLE_VERBOSITY}
ansible-playbook aptly-all.yml -i inventory ${ANSIBLE_VERBOSITY}
ls -R ${RPC_ARTIFACTS_FOLDER}
