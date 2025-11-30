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

FILEBROWSER_STORAGE_PATH=$RAILWAY_VOLUME_MOUNT_PATH

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

filebrowser version

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

mkdir -p /data/fossils

# create the user based on WEB_USERNAME if it doesn't exist
echo "id output: $(id $WEB_USERNAME)"
if id "$WEB_USERNAME" >/dev/null 2>&1; then
    echo "$WEB_USERNAME exists"
    usermod -aG root $WEB_USERNAME
else
    # add user with root permissions
    useradd -m -s /bin/sh $WEB_USERNAME
    usermod -aG root $WEB_USERNAME
fi

chown -R $WEB_USERNAME:$WEB_USERNAME /data/fossils
ADMIN_REPO_NAME="admin.fossil"
ADMIN_REPO="/data/fossils/$ADMIN_REPO_NAME"
LOGIN_GROUP="G"
if [ ! -f "$ADMIN_REPO" ]; then
  echo "Creating new $ADMIN_REPO"
  fossil init --admin-user "$WEB_USERNAME" "$ADMIN_REPO"
  fossil user password "$WEB_USERNAME" "$WEB_PASSWORD" -R "$ADMIN_REPO"
else
  echo "Repository '$ADMIN_REPO' already exists. Making sure password is correct, skipping initialization."
  fossil user password "$WEB_USERNAME" "$WEB_PASSWORD" -R "$ADMIN_REPO"
fi

INITIALIZED=false

# check if the ADMIN_REPO is part of a login group
ADMIN_LOGIN_GROUP=$(fossil login-group -R "$ADMIN_REPO")
echo "ADMIN_LOGIN_GROUP: $ADMIN_LOGIN_GROUP"
# Output will say something like 'Not currently a part of any login-group' if it's not part of a login group
# if not starts with Not currently
if [[ ! "$ADMIN_LOGIN_GROUP" =~ ^"Not currently" ]]; then
  echo "Repository '$ADMIN_REPO' is already part of a login group. Leaving to remake."
  fossil login-group leave -R "$ADMIN_REPO"
  fossil sqlite3 -R "$ADMIN_REPO" "DELETE FROM config WHERE name LIKE 'login-group%';"
  fossil sqlite3 -R "$ADMIN_REPO" "DELETE FROM config WHERE name LIKE 'peer-%';"
fi

cd /data/fossils
# loop over repos in /data/fossils and set the password to WEB_PASSWORD and make sure WEB_USERNAME exists as a user
for REPO in /data/fossils/*.fossil; do
  if [ ! -f "$REPO" ]; then
    echo "Repository '$REPO' does not exist. Skipping."
    continue
  fi

  if [ "$REPO" == "$ADMIN_REPO" ]; then
    continue
  fi

#   fossil login-group leave -R "$REPO"
#   fossil sqlite3 -R "$REPO" "DELETE FROM config WHERE name LIKE 'login-group%';"
#   fossil sqlite3 -R "$REPO" "DELETE FROM config WHERE name LIKE 'peer-%';"


  REPO_NAME=$(basename "$REPO")
  fossil user password $WEB_USERNAME "$WEB_PASSWORD" -R "$REPO_NAME"
  echo "$REPO"
  if [ "$INITIALIZED" = false ]; then
    echo "Joining $REPO to new login group $LOGIN_GROUP"
    fossil login-group join --name "$LOGIN_GROUP" -R "$REPO_NAME" "$ADMIN_REPO_NAME"
    INITIALIZED=true
  else
    echo "Joining repo to existing login group"
    fossil login-group join -R "$REPO_NAME" "$ADMIN_REPO_NAME"
  fi
done

echo ":::::::::::Login group of admin repo:::::::::::\n\n\n $(fossil login-group -R "$ADMIN_REPO")"

# Run the servers
# if SERVER_TYPE has a value
if [ -z "SERVER_TYPE" ]; then
    if [ "$SERVER_TYPE" == 0 ]; then
        filebrowser --database $DATABASE_PATH &
        fossil server --repolist --https /data/fossils --port 8080
    fi

    if [ "$SERVER_TYPE" == 1 ]; then
        fossil server --repolist --https /data/fossils --port 8080
    fi

    if [ "$SERVER_TYPE" == 2 ]; then
        filebrowser --database $DATABASE_PATH
    fi
else
    echo "SERVER_TYPE is not set, defaulting to 0"
    filebrowser --database $DATABASE_PATH &
    fossil server --repolist --https /data/fossils --port 8080
fi