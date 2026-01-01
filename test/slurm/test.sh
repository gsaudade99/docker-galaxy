#!/usr/bin/env bash

set -euo pipefail
set -x
# Test that jobs run successfully on an external slurm cluster

# We use a temporary directory as an export dir that will hold the shared data between
# galaxy and slurm:
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT=`mktemp --directory -p /var/tmp`
chmod 777 "$EXPORT"
GALAXY_IMAGE="${GALAXY_IMAGE:-galaxy:test}"
# Ensure leftover containers from previous runs don't conflict.
docker rm -f slurm galaxy-slurm-test >/dev/null 2>&1 || true
# We build the slurm image
docker build -t slurm "$SCRIPT_DIR"
# We fire up a slurm node (with hostname slurm)
docker run -d --rm -v "$EXPORT":/export -v /sys/fs/cgroup:/sys/fs/cgroup:rw --name slurm \
           --hostname slurm \
           slurm
# We start galaxy (without the internal slurm, but with a modified job_conf.xml)
# and link it to the slurm container (so that galaxy resolves the slurm container's hostname)
docker run -d --rm -e "NONUSE=slurmd,slurmctld" \
   --link slurm --name galaxy-slurm-test -h galaxy \
   -p 80:80 -v "$EXPORT":/export "${GALAXY_IMAGE}"
# We wait for the creation of the /galaxy/config/ if it does not exist yet
sleep 180s
# We restart galaxy
docker stop galaxy-slurm-test || true
for i in $(seq 1 30); do
    if ! docker ps -a --format '{{.Names}}' | grep -qx galaxy-slurm-test; then
        break
    fi
    sleep 1s
done

# We copy the job_conf.xml to the $EXPORT folder
docker run --rm -v "$EXPORT":/export -v "$SCRIPT_DIR":/workspace busybox sh -c \
  "mkdir -p /export/galaxy/config && cp /workspace/job_conf.xml /export/galaxy/config/job_conf.xml && chown 1450:1450 /export/galaxy/config/job_conf.xml"

docker run -d --rm -e "NONUSE=slurmd,slurmctld" \
   --link slurm --name galaxy-slurm-test -h galaxy \
   -p 80:80 -v "$EXPORT":/export "${GALAXY_IMAGE}"
# Let's submit a job from the galaxy container and check it runs in the slurm container
sleep 60s
for i in $(seq 1 30); do
    if docker exec galaxy-slurm-test scontrol ping 2>/dev/null | grep -q "UP"; then
        break
    fi
    sleep 2s
done
docker exec galaxy-slurm-test scontrol ping | grep -q "UP"
docker exec galaxy-slurm-test su - galaxy -c 'srun hostname' | grep slurm
docker exec -i galaxy-slurm-test /bin/sh -s <<'EOF' | grep slurm
set -e
rm -f /export/drmaa.out /export/drmaa.err
DRMAA_LIBRARY_PATH=/usr/lib/slurm-drmaa/lib/libdrmaa.so /galaxy_venv/bin/python - <<'PY'
import drmaa

with drmaa.Session() as session:
    jt = session.createJobTemplate()
    jt.remoteCommand = "/bin/hostname"
    jt.outputPath = ":" + "/export/drmaa.out"
    jt.errorPath = ":" + "/export/drmaa.err"
    jt.nativeSpecification = "-n 1"
    jobid = session.runJob(jt)
    session.deleteJobTemplate(jt)
    session.wait(jobid, drmaa.Session.TIMEOUT_WAIT_FOREVER)

with open("/export/drmaa.out", "r") as handle:
    print(handle.read().strip())
PY
EOF
docker stop galaxy-slurm-test slurm || true
docker rmi slurm || true
# TODO: Run a galaxy tool and check it runs on the cluster
