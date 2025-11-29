#!/bin/sh

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

# Run the server
fossil server --repolist --https /fossils/repos --port 8080
