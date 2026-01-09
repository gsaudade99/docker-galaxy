#!/bin/bash
set -euo pipefail

# Basic defaults so set -u does not choke when running outside the normal entrypoint.
GALAXY_HOME=${GALAXY_HOME:-/galaxy}
GALAXY_ROOT_DIR=${GALAXY_ROOT_DIR:-$GALAXY_HOME}
export GALAXY_VIRTUAL_ENV=${GALAXY_VIRTUAL_ENV:-/galaxy_venv}
export PATH="${GALAXY_VIRTUAL_ENV}/bin:${PATH}"
export GALAXY_SKIP_REQUIREMENTS_INSTALL=1
export GALAXY_SKIP_COMMON_STARTUP=1
export GALAXY_SKIP_CLIENT_BUILD=1
export GALAXY_CONFIG_FILE=${GALAXY_CONFIG_FILE:-/etc/galaxy/galaxy.yml}
# Never create conda envs during tool install; rely on cached containers only.
export GALAXY_CONFIG_CONDA_AUTO_INSTALL=False
export GALAXY_CONFIG_CONDA_AUTO_INIT=False
# Keep managed configs inside the image, not /export.
export GALAXY_CONFIG_MANAGED_CONFIG_DIR=/galaxy/database/config
export GALAXY_CONFIG_INTEGRATED_TOOL_PANEL_CONFIG=/galaxy/integrated_tool_panel.xml
export GALAXY_CONFIG_FILE_PATH=/galaxy/database/files
export GALAXY_CONFIG_NEW_FILE_PATH=/galaxy/database/tmp
export GALAXY_CONFIG_TEMPLATE_CACHE_PATH=/galaxy/database/compiled_templates
export GALAXY_CONFIG_CITATION_CACHE_DATA_DIR=/galaxy/database/citations/data
export GALAXY_CONFIG_JOB_WORKING_DIRECTORY=/galaxy/database/job_working_directory
mkdir -p "${GALAXY_CONFIG_MANAGED_CONFIG_DIR}"
mkdir -p "${GALAXY_CONFIG_FILE_PATH}" "${GALAXY_CONFIG_NEW_FILE_PATH}" \
         "${GALAXY_CONFIG_TEMPLATE_CACHE_PATH}" "${GALAXY_CONFIG_CITATION_CACHE_DATA_DIR}" \
         "${GALAXY_CONFIG_JOB_WORKING_DIRECTORY}"
chown -R galaxy:galaxy "${GALAXY_CONFIG_MANAGED_CONFIG_DIR}" "${GALAXY_CONFIG_FILE_PATH}" \
    "${GALAXY_CONFIG_NEW_FILE_PATH}" "${GALAXY_CONFIG_TEMPLATE_CACHE_PATH}" \
    "${GALAXY_CONFIG_CITATION_CACHE_DATA_DIR}" "${GALAXY_CONFIG_JOB_WORKING_DIRECTORY}"
if [ ! -f "${GALAXY_CONFIG_INTEGRATED_TOOL_PANEL_CONFIG}" ]; then
    cp -f /galaxy/config/integrated_tool_panel.xml.sample "${GALAXY_CONFIG_INTEGRATED_TOOL_PANEL_CONFIG}" 2>/dev/null || touch "${GALAXY_CONFIG_INTEGRATED_TOOL_PANEL_CONFIG}"
fi

# Enable Test Tool Shed for flavour installs.
export GALAXY_CONFIG_TOOL_SHEDS_CONFIG_FILE="${GALAXY_CONFIG_TOOL_SHEDS_CONFIG_FILE:-$GALAXY_HOME/tool_sheds_conf.xml}"

# Ensure shed-tools is available.
. /tool_deps/_conda/etc/profile.d/conda.sh
conda activate base

cd "${GALAXY_ROOT_DIR}"
INSTALL_TOOLS_VERBOSE="${INSTALL_TOOLS_VERBOSE:-false}"
wait_args=("-v")
access_log="-"
startup_log="/tmp/install_tools_startup.log"
startup_redirect=""
if ! [[ "${INSTALL_TOOLS_VERBOSE}" =~ ^([Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss])$ ]]; then
    wait_args=()
    access_log="/dev/null"
    startup_redirect=">> ${startup_log} 2>&1"
fi

# If supervisord is already running we assume Galaxy is up (normal runtime).
if pgrep "supervisord" >/dev/null; then
    echo "System is up and running. Installing tools against the running Galaxy (port 80)."
    PORT=80
    started_locally=false
else
    PORT=8080
    started_locally=true
    install_log='galaxy_install.log'

    echo "Starting PostgreSQL for tool installation"
    PG_VER="${PG_VERSION:-15}"
    PG_DATA="${PG_DATA_DIR_DEFAULT:-/var/lib/postgresql/${PG_VER}/main/}"
    sudo -u postgres /usr/lib/postgresql/${PG_VER}/bin/pg_ctl -D "$PG_DATA" -l /tmp/pg_install.log -o "-k /var/run/postgresql" start
    until pg_isready -h /var/run/postgresql -U galaxy >/dev/null 2>&1; do
        echo "Waiting for PostgreSQL..."
        sleep 1
    done
    # Ensure supervisord is running so gravity-managed services can start.
    if ! pgrep "supervisord" >/dev/null; then
        supervisord -c /etc/supervisor/supervisord.conf
        sleep 2
    fi

    echo "Starting Galaxy for tool installation"
    export GALAXY_CONFIG_GALAXY_INFRASTRUCTURE_URL="http://localhost:${PORT}"
    export GRAVITY_MANAGE_TUSD=False
    export GALAXY_CONFIG_TUS_UPLOAD_ENABLED=False
    export GRAVITY_MANAGE_GX_IT_PROXY=False
    # Prefer env overrides instead of mutating config files.
    export GALAXY_CONFIG_OVERRIDE__galaxy_infrastructure_url="http://localhost:${PORT}"
    # Keep container resolvers simple (no CVMFS) for the install run; do not overwrite runtime config.
    container_conf_target="$(mktemp /tmp/container_resolvers_conf.install.XXXX.yml)"
    cat > "${container_conf_target}" <<'EOF'
- type: explicit
- type: cached_mulled_singularity
  cache_directory: "/export/container_cache/singularity/mulled"
- type: mulled
  namespace: "biocontainers"
- type: build_mulled
  namespace: local
EOF
    chown galaxy:galaxy "${container_conf_target}" || true
    chmod 644 "${container_conf_target}" || true
    export GALAXY_CONFIG_CONTAINER_RESOLVERS_CONFIG_FILE="${container_conf_target}"
    sudo -E -H -u galaxy -- bash -c "
        unset SUDO_UID SUDO_GID SUDO_COMMAND SUDO_USER
        . /galaxy_venv/bin/activate
        GALAXY_SKIP_REQUIREMENTS_INSTALL=1 GALAXY_SKIP_COMMON_STARTUP=1 GALAXY_SKIP_CLIENT_BUILD=1 GALAXY_NO_VENV=1 \
        GALAXY_CONFIG_GALAXY_INFRASTRUCTURE_URL=http://localhost:${PORT} \
        PYTHONPATH=lib GALAXY_CONFIG_FILE=/etc/galaxy/galaxy.yml \
        gunicorn 'galaxy.webapps.galaxy.fast_factory:factory()' \
            --timeout 300 --pythonpath lib -k galaxy.webapps.galaxy.workers.Worker \
            -b 127.0.0.1:${PORT} --workers=1 --config python:galaxy.web_stack.gunicorn_config --preload \
            --pid galaxy_install.pid --error-logfile ${install_log} --access-logfile ${access_log} ${startup_redirect} &
        echo \$! > /tmp/galaxy_install_wrapper.pid
    "

    galaxy-wait -g "http://localhost:${PORT}" "${wait_args[@]}" --timeout 900
fi

# Ensure admin user exists (needed for shed-tools with fakekey).
if [[ -n "${GALAXY_DEFAULT_ADMIN_USER:-}" ]]; then
    echo "Creating admin user ${GALAXY_DEFAULT_ADMIN_USER} (if missing)"
    . "${GALAXY_VIRTUAL_ENV}/bin/activate"
    python /usr/local/bin/create_galaxy_user.py \
        --user "${GALAXY_DEFAULT_ADMIN_EMAIL}" \
        --password "${GALAXY_DEFAULT_ADMIN_PASSWORD}" \
        -c "${GALAXY_CONFIG_FILE}" \
        --username "${GALAXY_DEFAULT_ADMIN_USER}" \
        --key "${GALAXY_DEFAULT_ADMIN_KEY}"
    deactivate
fi

echo "Installing tools from $1"
INSTALL_TOOL_DEPS="${INSTALL_TOOL_DEPENDENCIES:-false}"
if [[ "${INSTALL_TOOL_DEPS}" =~ ^([Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss])$ ]]; then
    echo "Installing tool dependencies as well (INSTALL_TOOL_DEPENDENCIES=${INSTALL_TOOL_DEPS})"
    shed-tools install -g "http://localhost:${PORT}" -a fakekey -t "$1" --install-tool-dependencies
else
    echo "Skipping tool and resolver dependencies (INSTALL_TOOL_DEPENDENCIES=${INSTALL_TOOL_DEPS})"
    shed-tools install -g "http://localhost:${PORT}" -a fakekey -t "$1" \
        --skip-install-resolver-dependencies \
        --skip-install-repository-dependencies
fi

if $started_locally; then
    echo "Shutting down temporary Galaxy/PostgreSQL used for tool install"
    if [ -f /tmp/galaxy_install_wrapper.pid ]; then
        kill "$(cat /tmp/galaxy_install_wrapper.pid)" 2>/dev/null || true
        rm -f /tmp/galaxy_install_wrapper.pid
    fi
    sudo -E -H -u galaxy kill "$(cat galaxy_install.pid)" 2>/dev/null || true
    rm -f galaxy_install.pid "$install_log"
    PG_VER="${PG_VERSION:-15}"
    PG_DATA="${PG_DATA_DIR_DEFAULT:-/var/lib/postgresql/${PG_VER}/main/}"
    sudo -u postgres /usr/lib/postgresql/${PG_VER}/bin/pg_ctl -D "$PG_DATA" stop
fi
