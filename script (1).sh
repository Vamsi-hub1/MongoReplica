#!/bin/bash

# Alright tring to create  MongoDB replica set.
# Maybe it still has some issues

# Variables
MONGO_VERSION="5.0"   # This is the version I picked as mentioned in the mail
RS_NAME="rs0"
MONGO_PORTS=("27017" "27018" "27019")
MONGO_DIR="/data/mongodb"  # Where I decided to keep MongoDB data files
CACHE_SIZE="1GB"      # WiredTiger thing

# Make sure we are root - I think this is necessary
if [[ $EUID -ne 0 ]]; then
    echo "Umm... You need to be root to run this. Try sudo." 
    exit 1
fi

# Installing wget because I might need it for something... maybe?
echo "Installing wget just in case it's missing..."
yum install -y wget

# Adding MongoDB repository - found this online
echo "Adding MongoDB repo for version $MONGO_VERSION..."
cat <<EOL > /etc/yum.repos.d/mongodb-org-$MONGO_VERSION.repo
[mongodb-org-$MONGO_VERSION]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/$MONGO_VERSION/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-$MONGO_VERSION.asc
EOL

# Installing MongoDB - hope this works without errors!
echo "Installing MongoDB stuff..."
yum install -y mongodb-org-$MONGO_VERSION mongodb-org-server-$MONGO_VERSION \
mongodb-org-shell-$MONGO_VERSION mongodb-org-mongos-$MONGO_VERSION \
mongodb-org-tools-$MONGO_VERSION

# Making directories for MongoDB data - needed for each port
echo "Creating data directories... fingers crossed!"
for PORT in "${MONGO_PORTS[@]}"; do
    mkdir -p $MONGO_DIR/rs_$PORT
    echo "Made directory $MONGO_DIR/rs_$PORT - looks good so far."
done

# Creating config files for each MongoDB instance
echo "Time to make some config files..."
for PORT in "${MONGO_PORTS[@]}"; do
cat <<EOL > /etc/mongod_$PORT.conf
storage:
  dbPath: $MONGO_DIR/rs_$PORT  # data directory
  journal:
    enabled: true  # journaling because it's recommended
  engine: wiredTiger
  wiredTiger:
    engineConfig:
      cacheSizeGB: 1  # I think this is enough

net:
  bindIp: 127.0.0.1  # only local access for now
  port: $PORT

security:
  javascriptEnabled: false  # I don't think we need this

replication:
  replSetName: $RS_NAME
EOL
    echo "Config file created for port $PORT -> /etc/mongod_$PORT.conf"
done

# Starting MongoDB instances - hope they actually start!
echo "Starting MongoDB instances... wish me luck!"
for PORT in "${MONGO_PORTS[@]}"; do
    mongod --config /etc/mongod_$PORT.conf --fork --logpath /var/log/mongodb_$PORT.log
    if [[ $? -eq 0 ]]; then
        echo "MongoDB started on port $PORT!"
    else
        echo "Uh-oh... Something went wrong with port $PORT. Check logs maybe?"
    fi
done

# Pausing here to let MongoDB settle down a bit
echo "Waiting for MongoDB to settle... just in case."
sleep 5

# Setting up the replica set
echo "Initializing replica set (rs.initiate)... hope it works!"
mongo --port ${MONGO_PORTS[0]} <<EOF
rs.initiate({
  _id: "$RS_NAME",
  members: [
    { _id: 0, host: "127.0.0.1:${MONGO_PORTS[0]}" },
    { _id: 1, host: "127.0.0.1:${MONGO_PORTS[1]}" },
    { _id: 2, host: "127.0.0.1:${MONGO_PORTS[2]}", arbiterOnly: true }
  ]
});
EOF

# Checking the replica set status - no idea what to expect!
echo "Checking replica set status..."
mongo --port ${MONGO_PORTS[0]} --eval "rs.status()" || echo "Replica set status check failed. Uh-oh."

# Final message - if everything worked, that is
echo "Done! I think the MongoDB replica set is up."
