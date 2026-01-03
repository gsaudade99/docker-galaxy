#!/usr/bin/env bash

echo "Test that jobs run successfully on an external gridengine cluster"

docker build --target sge_master --tag sge_master .
docker build --target sge_bioblend_test --tag sge_bioblend_test .

# start master
# We use a temporary directory as an export dir that will hold the shared data between
# galaxy and gridengine:
EXPORT=`mktemp --directory`
chmod 777 ${EXPORT}
docker run -d --rm --hostname sgemaster --name sgemaster -v ${EXPORT}:/export -v $PWD/master_script.sh:/usr/local/bin/master_script.sh sge_master /usr/local/bin/master_script.sh
# wait for sge master
sleep 10

# start galaxy
GALAXY_CONTAINER=${GALAXY_CONTAINER:-quay.io/bgruening/galaxy}
EPHEMERIS_IMAGE=${EPHEMERIS_IMAGE:-quay.io/biocontainers/ephemeris:0.10.11--pyhdfd78af_0}
GALAXY_WAIT_TIMEOUT=${GALAXY_WAIT_TIMEOUT:-600}
GALAXY_CONTAINER_NAME=galaxytest
GALAXY_CONTAINER_HOSTNAME=galaxytest
GALAXY_ROOT_DIR=/galaxy

docker run -d --rm \
           -e SGE_ROOT=/var/lib/gridengine \
           --link sgemaster:sgemaster \
           --name ${GALAXY_CONTAINER_NAME} \
           --hostname ${GALAXY_CONTAINER_HOSTNAME} \
           -p 20080:80 -e NONUSE="condor" \
           -v $PWD/job_conf.xml.sge:/etc/galaxy/job_conf.xml \
           -v ${EXPORT}:/export \
           -v $PWD/outputhostname:$GALAXY_ROOT_DIR/tools/outputhostname \
           -v $PWD/outputhostname.tool.xml:$GALAXY_ROOT_DIR/outputhostname.tool.xml \
           -v $PWD/setup_tool.sh:$GALAXY_ROOT_DIR/setup_tool.sh \
           -v $PWD/tool_conf.xml:$GALAXY_ROOT_DIR/tool_conf.xml \
           -v $PWD/act_qmaster:/var/lib/gridengine/default/common/act_qmaster \
           ${GALAXY_CONTAINER} \
           $GALAXY_ROOT_DIR/setup_tool.sh
echo "Wait 30sec"
sleep 30

echo "show logs from ${GALAXY_CONTAINER_NAME}"
docker logs ${GALAXY_CONTAINER_NAME}

# Add host setting galaxytest to sgemaster
echo "Get host info from ${GALAXY_CONTAINER_HOSTNAME}"
SGECLIENT=$(docker exec ${GALAXY_CONTAINER_NAME} cat /etc/hosts | grep ${GALAXY_CONTAINER_HOSTNAME})
echo "Add host info to sgemaster"
docker exec sgemaster bash -c "echo ${SGECLIENT} >> /etc/hosts ; /etc/init.d/gridengine-master restart"
echo "Output /etc/hosts on sgemaster"
docker exec sgemaster cat /etc/hosts

# Add gridengine client host
echo "Add submit host ${GALAXY_CONTAINER_HOSTNAME}"
docker exec sgemaster bash -c "qconf -as ${GALAXY_CONTAINER_HOSTNAME}"
echo "Waiting for Galaxy to become ready"
if ! docker run --rm --link ${GALAXY_CONTAINER_NAME}:galaxytest \
    ${EPHEMERIS_IMAGE} galaxy-wait -g http://galaxytest --timeout ${GALAXY_WAIT_TIMEOUT}; then
    echo "Galaxy did not become ready within ${GALAXY_WAIT_TIMEOUT}s."
    docker logs ${GALAXY_CONTAINER_NAME} || true
    exit 1
fi

echo "Exec test"
docker run --rm --link galaxytest:galaxytest -v $PWD/test_outputhostname.py:/work/test_outputhostname.py sge_bioblend_test python /work/test_outputhostname.py > out
grep sgemaster out
RET=$?

# remove container
docker stop sgemaster || true
docker stop galaxytest || true

# Remove images 
docker rmi sge_master
docker rmi sge_bioblend_test

if [ $RET -ne 0 ]; then
    echo "Grid Engine test failed"
    exit $RET
fi
