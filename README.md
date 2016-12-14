# RPC-Artifacts: Artifacts preparation.

## Requirements

- Mirrors should be able to talk with ci nodes.
  Public keys of ci nodes in authorized keys of mirrors.
- Aptly needs pgp keys.
  The requirements (generation of keys) are listed in aptly-snapshot-create.yml.
  These keys should be handled appropriately and shared amongst mirror/ci nodes.

## Playbooks info

- ``mirror_install.yml`` ensures a static webserver exists on mirror servers
- ``fetch_other_files.yml`` ensures the "other files" artifacts are stored on mirror servers
- ``aptly-all.yml`` installs aptly, updates aptly internal db with external mirrors,
  drops the deb files for rabbit in the internal repo, create snapshot per version/distro,
  merge snapshots and publish the merged snapshots.

