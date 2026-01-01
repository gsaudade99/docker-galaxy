#!/usr/bin/env bash
set -euo pipefail

repos="${CVMFS_REPOSITORIES:-data.galaxyproject.org singularity.galaxyproject.org}"
repos="${repos//,/ }"

mkdir -p /cvmfs
mkdir -p "${CVMFS_CACHE_BASE:-/var/lib/cvmfs}"
touch /var/log/autofs.log /var/log/cvmfs.log

if [[ ! -f "${CVMFS_CACHE_BASE:-/var/lib/cvmfs}/.configured" ]]; then
    ansible-playbook /ansible/playbook.yml
    touch "${CVMFS_CACHE_BASE:-/var/lib/cvmfs}/.configured"
fi

if command -v service >/dev/null 2>&1; then
    service autofs start || true
else
    autofs -f || true
fi

for repo in $repos; do
    mkdir -p "/cvmfs/$repo"
    ls "/cvmfs/$repo" >/dev/null 2>&1 || true
done

exec "$@"
