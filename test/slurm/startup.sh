#!/usr/bin/env bash

# Setup the galaxy user UID/GID and pass control on to supervisor
if id "$SLURM_USER_NAME" >/dev/null 2>&1; then
        echo "user exists"
else
        echo "user does not exist, creating"
        useradd -m -d /var/"$SLURM_USER_NAME" "$SLURM_USER_NAME"
fi
usermod -u $SLURM_UID  $SLURM_USER_NAME
groupmod -g $SLURM_GID $SLURM_USER_NAME
if [ ! -f "$MUNGE_KEY_PATH" ]
  then
    cp /etc/munge/munge.key "$MUNGE_KEY_PATH"
fi

if [ ! -f "$SLURM_CONF_PATH" ]
  then
    mkdir -p /etc/slurm
    python3 /usr/local/bin/configure_slurm.py
    cp /etc/slurm/slurm.conf "$SLURM_CONF_PATH"
    if [ -f /etc/slurm/cgroup.conf ]
      then
        cp /etc/slurm/cgroup.conf "$(dirname "$SLURM_CONF_PATH")/cgroup.conf"
        rm -f /etc/slurm/cgroup.conf
    fi
    rm /etc/slurm/slurm.conf
fi
if [ ! -f "$GALAXY_DIR"/.venv ]
  then
    mkdir -p "$GALAXY_DIR"/.venv
    chown $SLURM_USER_NAME:$SLURM_USER_NAME "$GALAXY_DIR"/.venv
    su $SLURM_USER_NAME -c \
        "GALAXY_DIR=$GALAXY_DIR uv venv \"$GALAXY_DIR\"/.venv && \
        uv pip install --python \"$GALAXY_DIR\"/.venv/bin/python galaxy-lib"
fi
mkdir -p /tmp/slurmd
chown $SLURM_USER_NAME /tmp/slurm /tmp/slurmd
ln -s "$GALAXY_DIR" "$SYMLINK_TARGET"
ln -sf "$SLURM_CONF_PATH" /etc/slurm/slurm.conf
if [ -f "$(dirname "$SLURM_CONF_PATH")/cgroup.conf" ]
  then
    ln -sf "$(dirname "$SLURM_CONF_PATH")/cgroup.conf" /etc/slurm/cgroup.conf
fi
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
