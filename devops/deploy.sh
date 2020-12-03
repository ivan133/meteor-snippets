#!/bin/bash

# Hello there!
# This is deploy script we use to pull
# web application repository from GitHub
#
# This script does:
# - move files
# - build meteor
# - test nginx configuration files
# - no down-time restart

restart=false
isMeteor=false
isPassenger=false
isStatic=false
isHelp=false
reload=false
build=false
debug=false
appusername="appuser"
nginxusername="www-data"

while getopts ":h?brmpsnd" opt; do
  case "$opt" in
  h|\?) isHelp=true;;
  b) build=true;;
  r) restart=true;;
  m) isMeteor=true;;
  p) isPassenger=true;;
  s) isStatic=true;;
  n) reload=true;;
  d) debug=true;;
  esac
done

if [ ! -z "$2" ]; then
  name=$2
fi

if [ ! -z "$3" ]; then
  appusername=$3
fi

if [ ! -z "$4" ]; then
  nginxusername=$4
fi

if [ "$debug" = true ]; then
  echo "isHelp: $isHelp;"
  echo "restart: $restart;"
  echo "isMeteor: $isMeteor;"
  echo "isPassenger: $isPassenger;"
  echo "isStatic: $isStatic;"
  echo "reload: $reload;"
  echo "appusername: $appusername;"
  echo "name: $name;"
  echo "nginxusername: $nginxusername;"
  echo "build: $build;"
  exit 1
fi

# HELP DOCS
if [ "$isHelp" = true ]; then
  echo "Pull source and nginx config from GitHub"
  echo "then build app, move files in the right place, and restart if instructed"
  echo ""
  echo "Usage: "
  echo "./deploy.sh -[args] repo [username] [nginxuser]"
  echo ""
  echo ""
  echo "-h          - Show this help and exit"
  echo "-b          - Build, install dependencies & move files around"
  echo "-r          - Restart server after deployment"
  echo "-m          - Build meteor app"
  echo "-p          - Force Phusion Passenger deployment scenario"
  echo "-s          - Force static website deployment scenario"
  echo "-n          - Reload Nginx __configuration__ without downtime"
  echo "-d          - Debug this script arguments and exit"
  echo "repo        - Name of web app repository and working directory"
  echo "[username]  - Username of an \"application user\" owned app files and used to spawn a process, default: \`appuser\`"
  echo "[nginxuser] - Username used to spawn a process and access files by Nginx, default: \`www-data\`"
  echo ""
  echo "EXAMPLES:"
  echo "Deploy static website:"
  echo "$ ./deploy -bs site-html"
  echo ""
  echo "Build and deploy Meteor app spawned by Phusion Passenger:"
  echo "$ ./deploy -bmpr meteor-app"
  echo ""
  echo "Build and deploy Node.js spawned by Phusion Passenger:"
  echo "$ ./deploy -bpr nodejs-app"
  echo ""
  echo "Update Nginx configuration only, or other non-codebase files"
  echo "This command will only sync Git repository and silently reload Nginx config"
  echo "$ ./deploy -n myapp"
  echo ""
  echo "ONLY sync Git repository and place files into right places"
  echo "$ ./deploy - myapp"
  echo ""
  exit 1
fi

# CHECK IF WORKING DIRECTORY EXISTS
if [ -z "$name" ] || [ ! -d "./$name" ]; then
  echo "No project with name \"$name\" found"
  echo "Start with cloning your new project from GitHub"
  echo "git clone [path-to-repository], use"
  echo "$ ./deploy.sh -h"
  echo "to get help"
  exit 1
fi

# GO TO WORKING DIRECTORY
echo "[ 1.0. ] Going to ./$name"
cd "./$name"
echo "[ 1.1. ] Sync with Git"
git pull || { echo "Can not sync Git repo; Please, fix issues before running deploy!" ; exit 1; }
# WISH TO USE SPECIFIC SSH-KEY FOR GIT?
# UNDATE ARGUMENTS AND UNCOMMENT LINE BELOW
# ssh-agent bash -c 'ssh-add /full/path/to/.ssh/privkey; git pull'

# MOVE/UPDATE nginx.conf OF THE WEB APP
if [ -f "./nginx.conf" ]; then
  echo "[ *.*. ] nginx.conf found! Copy to the nginx directory"
  cp ./nginx.conf "/etc/nginx/sites-available/$name.conf"
  ln -s "/etc/nginx/sites-available/$name.conf" "/etc/nginx/sites-enabled/$name.conf"

  echo "[ *.*. ] Nginx configuration: Ensure permissions and ownership"
  chown "$nginxusername":"$nginxusername" "/etc/nginx/sites-available/$name.conf" "/etc/nginx/sites-enabled/$name.conf"
  chmod 644 "/etc/nginx/sites-available/$name.conf" "/etc/nginx/sites-enabled/$name.conf"

  # TEST NEW NGINX CONFIGURATION FILE
  # TERMINATE THE SCRIPT IF CONFIG HAS ERRORS
  service nginx configtest || { echo "nginx.conf has errors. Deploy process terminated." ; exit 1; }
  echo "[ *.*. ] nginx.conf successfully updated and tested, no errors found!"
fi

echo "[ 2.0. ] Ensure /var/www/$name"
mkdir -p "/var/www/$name"

# BUILD
if [ "$build" = true ]; then
  # BUILD METEOR APP
  if [ "$isMeteor" = true ]; then
    # CHECK FOR .meteor DIRECTORY
    if [ ! -d "./.meteor" ]; then
      echo "[ *.*. ] Script started with \`-m\` flag requires \`./.meteor\` directory!"
      echo "[ *.*. ] To build Meteor.js application and follow Meteor deployment scenario"
      exit 1
    fi

    echo "[ 2.1. ] Running Meteor.js deployment scenario! Building meteor app to ../$name-build"
    # Install NPM dependencies
    echo "[ 2.2. ] Installing NPM dependencies in working meteor app directory"
    su -s /bin/bash -c "cd /home/$appusername/$name && meteor npm ci" - "$appusername"

    echo "[ 2.3. ] Building meteor app to ../$name-build"
    su -s /bin/bash -c "cd /home/$appusername/$name && METEOR_DISABLE_OPTIMISTIC_CACHING=1 meteor build ../$name-build --directory" - "$appusername"

    echo "[ 2.4. ] Meteor app successfully build! Going to ../$name-build/bundle"
    cd "../$name-build/bundle"

    echo "[ 2.5. ] Move static Meteor files to /public directory"
    mkdir -p ./public
    cp ./programs/web.browser/*.css ./public/
    cp ./programs/web.browser/*.js ./public/
    cp ./programs/web.browser.legacy/*.css ./public/
    cp ./programs/web.browser.legacy/*.js ./public/
    rsync -qauh ./programs/web.browser/app/ ./public
    rsync -qauh ./programs/web.browser.legacy/app/ ./public
    rsync -qauh ./programs/web.browser/packages/ ./public
    rsync -qauh ./programs/web.browser.legacy/packages/ ./public

    echo "[ 2.6. ] Ensure /var/www/$name/programs/web.browser/"
    mkdir -p "/var/www/$name/programs/web.browser/"
  fi

  # SET PERMISSIONS
  echo "[ 3.0. ] Ensure permissions and ownership in working directory"
  chmod -R 744 ./
  chmod 755 ./
  chown -R "$appusername":"$appusername" ./

  echo "[ 3.1. ] Copy files to /var/www/$name"
  rsync -qauh ./ "/var/www/$name" --exclude=".git" --exclude=".gitattributes" --exclude="nginx.conf"  --exclude="mongod.conf"

  if [ "$isMeteor" = true ]; then
    echo "[ *.*. ] Going to /var/www/$name/programs/server"
    cd "/var/www/$name/programs/server"
    echo "[ *.*. ] Installing Meteor's NPM dependencies"
    su -s /bin/bash -c "cd /var/www/$name/programs/server && npm install --production" - "$appusername"
  fi

  # CHECK FOR package.json
  # AND INSTALL DEPENDENCIES
  echo "[ 4.0. ] Going to /var/www/$name"
  cd "/var/www/$name"
  if [ -f "./package.json" ]; then
    echo "[ 4.1. ] \`packages.json\` detected! Installing NPM dependencies"
    su -s /bin/bash -c "cd /var/www/$name && npm ci --production" - "$appusername"
  fi

  # GO TO "HOME" DIRECTORY
  echo "[ 5.0. ] Going to application user \"home\" (/home/$appusername)"
  cd "/home/$appusername"

  # SET PERMISSIONS
  echo "[ 5.1. ] Ensure permissions and ownership after installing dependencies"
  chown -R "$appusername":"$appusername" "/var/www/$name"
  chmod -R 744 "/var/www/$name"
  chmod 755 "/var/www/$name"

  # CHECK IF public DIRECTORY EXISTS
  # ENSURE PERMISSIONS AND OWNERSHIP
  if [ -d "/var/www/$name/public" ]; then
    echo "[ 5.2. ] Set 755 permissions for static assets in /var/www/$name/public/"
    chmod -R 755 "/var/www/$name/public"
    echo "[ 5.3. ] Set Nginx's user $nginxusername as owner of static assets in /var/www/$name/public"
    chown -R "$nginxusername":"$nginxusername" "/var/www/$name/public"
  fi
fi

# RESTART PASSENGER APP ONLY
if [ "$restart" = true ]; then
  if [ "$isPassenger" = true ]; then
    echo "[ 6.0. ] RESTARTING PASSENGER"
    passenger-config restart-app "/var/www/$name"
    passenger-status -v
    echo "[ 6.1. ] DISPLAY PASSENGER LOGS"
    tail -n 100 /var/log/nginx/error.log
  else
    if [ "$isStatic" = true ]; then
      echo "[ 6.0. ] RESTARTING NGINX"
      service nginx stop
      service nginx start
      service nginx status
      echo "[ 6.1. ] DISPLAY NGINX LOGS"
      tail -n 100 /var/log/nginx/error.log
    fi
  fi
else
  if [ "$reload" = true ]; then
    echo "[ 6.0. ] RELOADING NGINX WITHOUT DOWNLIME"
    service nginx reload
    echo "[ 6.1. ] DISPLAY NGINX LOGS"
    tail -n 100 /var/log/nginx/error.log
  fi
fi

echo "===============[$name: deployed]==============="
