#!/bin/sh

set -e

if [ -z "$RAILWAY_VOLUME_MOUNT_PATH" ]; then
    echo "no volume attached, please attach a volume"
    echo "upon attaching a volume let this service rebuild"
    exit 0
fi

if [ -z "$WEB_USERNAME" ]; then
    echo "missing the WEB_USERNAME variable, please add it to continue"
    exit 0
fi

if [ -z "$WEB_PASSWORD" ]; then
    echo "missing the WEB_PASSWORD variable, please add it to continue"
    exit 0
fi

if [ -f "/.filebrowser.json" ]; then
  rm /.filebrowser.json
fi

FILEBROWSER_DATA_PATH=$RAILWAY_VOLUME_MOUNT_PATH/appdata/filebrowser

DATABASE_PATH=$FILEBROWSER_DATA_PATH/filebrowser.db

FILEBROWSER_USERNAME_PATH=$FILEBROWSER_DATA_PATH/username

if [ "$USE_VOLUME_ROOT" == "1" ]; then
    echo "using volume root as storage location"
    FILEBROWSER_STORAGE_PATH=$RAILWAY_VOLUME_MOUNT_PATH
else
    FILEBROWSER_STORAGE_PATH=$RAILWAY_VOLUME_MOUNT_PATH/storage
    if [ ! -d $FILEBROWSER_STORAGE_PATH ]; then
        mkdir $FILEBROWSER_STORAGE_PATH
    fi
fi

if [ -f "$DATABASE_PATH" ]; then
    if [ -f "$FILEBROWSER_USERNAME_PATH" ]; then
        FILEBROWSER_CURRENT_USERNAME=$(cat $FILEBROWSER_USERNAME_PATH)

        if [[ -n "$FILEBROWSER_CURRENT_USERNAME" && "$FILEBROWSER_CURRENT_USERNAME" != "$WEB_USERNAME" ]]; then
            echo "new username was set in the service variables, changing username: $FILEBROWSER_CURRENT_USERNAME -> $WEB_USERNAME"
            filebrowser users update $FILEBROWSER_CURRENT_USERNAME --username $WEB_USERNAME --database $DATABASE_PATH > /dev/null 2>&1
            echo $WEB_USERNAME >| $FILEBROWSER_USERNAME_PATH
            echo "username updated"
        fi
    fi
else
    echo "first start, creating database"
    filebrowser config init --database $DATABASE_PATH

    echo "setting configurations"
    filebrowser config set --address "0.0.0.0" --database $DATABASE_PATH

    echo "adding user"
    filebrowser users add $WEB_USERNAME $WEB_PASSWORD --database $DATABASE_PATH
fi

echo $WEB_USERNAME > $FILEBROWSER_USERNAME_PATH

filebrowser users update $WEB_USERNAME --password $WEB_PASSWORD --database $DATABASE_PATH

filebrowser config set --port 8081 --database $DATABASE_PATH > /dev/null 2>&1
filebrowser config set --root $FILEBROWSER_STORAGE_PATH --database $DATABASE_PATH

/filebrowser version

# Create the .ssh directory and set permissions
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Create the known_hosts file and set permissions
ssh-keyscan github.com >> /root/.ssh/known_hosts
chmod 644 /root/.ssh/known_hosts

# Create the config file and set permissions
echo "Host github.com" > /root/.ssh/config
echo "  IdentityFile ~/.ssh/gh_mirror_key" >> /root/.ssh/config
chmod 600 /root/.ssh/config

# Read the SSH_PRIVATE_KEY secret into /root/.ssh/gh_mirror_key
echo $SSH_PRIVATE_KEY > /root/.ssh/gh_mirror_key
chmod 600 /root/.ssh/gh_mirror_key

# Run the servers
filebrowser --database $DATABASE_PATH &
fossil server --repolist --https /fossils/repos --port 8080
