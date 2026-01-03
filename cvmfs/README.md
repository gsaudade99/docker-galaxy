# CVMFS sidecar for Galaxy

This container provides a full CVMFS client (no cvmfsexec) and is intended to be used as an optional sidecar for the
Galaxy container in `galaxy/docker-compose.yaml`.

## What it does

- Installs and configures the CVMFS client using the `galaxyproject.cvmfs` Ansible role.
- Enables the Galaxy CVMFS repositories (including `data.galaxyproject.org` and
  `singularity.galaxyproject.org`).
- Starts autofs and warms the mount points so the CVMFS mounts are shared to the Galaxy container.

## Build

From the repository root:

```bash
docker build -t galaxy-cvmfs ./cvmfs
```

## Usage with docker-compose

The `galaxy/docker-compose.yaml` file contains an optional `cvmfs` service (profile: `cvmfs`).
Start both containers with:

```bash
cd galaxy
CVMFS_MOUNT_DIR=/cvmfs EXPORT_DIR=./export docker compose --profile cvmfs up
```

Notes:
- The sidecar runs privileged so the CVMFS mount can be propagated to the host.
- The `/cvmfs` mount is shared between the sidecar and the Galaxy container.
- The CVMFS cache is stored in `${EXPORT_DIR}/cvmfs-cache` to keep it persistent.

## Basic check

Once running, verify the mount from the Galaxy container:

```bash
docker exec -it galaxy-server ls /cvmfs/data.galaxyproject.org/byhand
```

If the directory lists, CVMFS is mounted.

## Environment variables

- `CVMFS_REPOSITORIES`: Space- or comma-separated list of repositories to warm up.
  Default: `data.galaxyproject.org singularity.galaxyproject.org`
- `CVMFS_CACHE_BASE`: Cache directory inside the sidecar. Default: `/var/lib/cvmfs`
