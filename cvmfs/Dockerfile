FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ansible \
        ca-certificates \
        curl \
        dirmngr \
        fuse3 \
        git \
        gpg \
        python3 \
        python3-apt \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

COPY ansible/ /ansible/

RUN ansible-galaxy install -r /ansible/requirements.yml -p /ansible/roles \
    && rm -rf /root/.ansible

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bash", "-lc", "tail -F /var/log/autofs.log /var/log/cvmfs.log 2>/dev/null"]
