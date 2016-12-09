# RPC-Artifacts: Artifacts preparation.

## Requirements

- Mirrors should be able to talk with ci nodes. Public keys of ci nodes in authorized keys of mirrors.
- Aptly needs pgp keys. The requirements (generation of keys) are listed in aptly-snapshot-create.yml. These keys should be handled appropriately and shared amongst mirror/ci nodes
- Aptly and rabbitmq roles need to be present on the aptly_cache node:

    Git clone the aptly role in the proper folder, branch rax.

    ``
    cd /etc/ansible/roles/ && git clone https://github.com/evrardjp/ansible-role-aptly.git -b rax infOpen.aptly
    ``

## Playbooks info

- ``mirror_install.yml`` ensures a static webserver exists on mirror servers
- ``fetch_other_files.yml`` ensures the "other files" artifacts are stored on mirror servers
- ``aptly-install-and-mirror.yml`` is to be run frequently, to always have the db of packages up to date. This can be requiring a massive amount of storage. This could be run anywhere, but one cache should be used (for example by storing always on the same location, and attaching this storage appropriately). You can customize what to mirror by editing the artifacts-vars.yml. the do_update forces an update of the mirrors.
- ``aptly-snapshot-create.yml`` is to run when tagging a release. This creates an immutable snapshot of the package list. That's the basis of the frozen release. Skip a snapshot by listing it to ``aptly_dont_snapshot_list`` in ``aptly-skip-vars.yml``
- ``aptly-snapshot-merge-and-publish.yml`` is to run when tagging a release, after the snapshot create. This publishes to a local file, into a prefixed folder.
- ``aptly-sync-to-mirror.yml`` is run when tagging a release, after the publish. It publishes to the mirrors, to the appropriate artifact folder, by rsyncing.

## How to release

1. Use aptly-snapshot-create.yml to create a snapshot for your release version. If you have linked your playbook to your osa inventory, it's gonna auto consume the variables openstack_release.
(You may want to change the target node). Else just give ``-e openstack_release=whatever`` in the CLI.

1. When your snapshots are ready, at the end of the playbook, there is gonna be a list of all the snapshot taken.

1. Release into your repo by running the next playbook: ``aptly-snapshot-merge-and-publish.yml``. You may want to filter snapshots you don't want, by using the exclude lists in ``aptly-skip-vars.yml``.
``ansible-playbook -e openstack_release=whatever (or openstack-ansible) aptly-snapshot-merge-and-publish.yml``
