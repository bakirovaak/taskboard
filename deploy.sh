#!/bin/sh

set -e

APP_NAME="TaskBoard"
APP_DIR=$(pwd)
REPOSITORY_URL="https://github.com/bakirovaak/taskboard"
DB_NAME="taskboard"
DB_USER="taskboard"
DB_PASSWORD="taskboard_password"
APP_HOST="0.0.0.0"
APP_PORT=8000
VENV_DIR="$APP_DIR/.venv"

error_exit() {
    echo "[ERROR] $1" >&2
    exit 1
}

check_cmd() {
    command -v "$1" >/dev/null 2>&1
}

if check_cmd apt-get; then
    PKGS_TO_INSTALL=""
    check_cmd git || PKGS_TO_INSTALL="$PKGS_TO_INSTALL git"
    check_cmd python3 || PKGS_TO_INSTALL="$PKGS_TO_INSTALL python3 python3-venv"
    check_cmd pip3 || PKGS_TO_INSTALL="$PKGS_TO_INSTALL python3-pip"
    check_cmd psql || PKGS_TO_INSTALL="$PKGS_TO_INSTALL postgresql postgresql-contrib"
    check_cmd curl || PKGS_TO_INSTALL="$PKGS_TO_INSTALL curl"

    if [ -n "$PKGS_TO_INSTALL" ]; then
        sudo apt-get update >/dev/null 2>&1 && sudo apt-get install -y $PKGS_TO_INSTALL >/dev/null 2>&1 || error_exit "Failed to install system packages."
    fi
else
    for cmd in git python3 pip3 psql curl; do
        check_cmd "$cmd" || error_exit "Required command '$cmd' is not installed."
    done
fi

if [ ! -f "$APP_DIR/requirements.txt" ]; then
    if [ ! -d "$APP_DIR/.git" ]; then
        git clone "$REPOSITORY_URL" temp_repo >/dev/null 2>&1 || error_exit "Failed to clone repository."
        cp -a temp_repo/. "$APP_DIR/"
        rm -rf temp_repo
    fi
fi

if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR" || error_exit "Failed to create virtual environment."
fi

. "$VENV_DIR/bin/activate" || error_exit "Failed to activate virtual environment."

pip install --upgrade pip >/dev/null 2>&1 || true
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt >/dev/null 2>&1 || error_exit "Failed to install Python dependencies."
else
    error_exit "requirements.txt file not found."
fi

if check_cmd systemctl; then
    sudo systemctl start postgresql >/dev/null 2>&1 || true
elif check_cmd service; then
    sudo service postgresql start >/dev/null 2>&1 || true
fi

sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';" >/dev/null 2>&1 || \
    error_exit "Failed to create PostgreSQL user."

sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" >/dev/null 2>&1 || \
    error_exit "Failed to create PostgreSQL database."

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" >/dev/null 2>&1

export DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME"

fuser -k ${APP_PORT}/tcp >/dev/null 2>&1 || true

uvicorn main:app --host "$APP_HOST" --port "$APP_PORT" > uvicorn.log 2>&1 &
sleep 3

HEALTH_URL="http://localhost:${APP_PORT}/api/health"
MAX_RETRIES=5
RETRY_COUNT=0
SUCCESS=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" || echo "000")
    if [ "$HTTP_STATUS" = "200" ]; then
        SUCCESS=1
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 2
done

if [ $SUCCESS -eq 1 ]; then
    echo "Application deployed successfully."
    echo "Application is available at: http://localhost:${APP_PORT}"
    exit 0
else
    cat uvicorn.log
    error_exit "Healthcheck failed with status code $HTTP_STATUS."
fi
