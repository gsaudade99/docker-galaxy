FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV UV_INSTALL_DIR=/usr/local/bin

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    munge \
    python3-psutil supervisor samtools apt-transport-https software-properties-common dirmngr gpg curl sudo gpg-agent && \
    add-apt-repository ppa:ubuntu-hpc/slurm-wlm-24.11 && \
    apt-get update -qq && \
    apt-get install -y slurm-wlm && \
    curl -LsSf https://astral.sh/uv/install.sh | sh && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - && \
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" && \
    apt update && \
    apt install -y docker-ce && \
    cd / && \
    ldconfig && \
    apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && rm -rf ~/.cache/ && \
    adduser --disabled-password --gecos "" galaxy &&\
    mkdir -p /var/log/slurm /tmp/slurm && \
    touch /var/log/slurm/slurmctld.log /var/log/slurm/slurmd.log

ADD configure_slurm.py /usr/local/bin/configure_slurm.py
ADD munge.conf /etc/default/munge
RUN service munge start && service munge stop
ADD startup.sh /usr/bin/startup.sh
ADD supervisor_slurm.conf /etc/supervisor/conf.d/slurm.conf
RUN chmod +x /usr/bin/startup.sh
#RUN locale-gen en_US.UTF-8 && dpkg-reconfigure locales
ENV GALAXY_DIR=/export/galaxy \
    SYMLINK_TARGET=/galaxy \
    SLURM_USER_NAME=galaxy \
    SLURM_UID=1450 \
    SLURM_GID=1450 \
    SLURM_PARTITION_NAME=work \
    SLURM_CLUSTER_NAME=Cluster \
    SLURMD_AUTOSTART=True \
    SLURMCTLD_AUTOSTART=True \
    SLURM_CONF_PATH=/export/slurm.conf \
    MUNGE_KEY_PATH=/export/munge.key

VOLUME ["/export/", "/var/lib/docker"]
CMD ["/usr/bin/startup.sh"]
