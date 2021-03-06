#!/bin/bash

#+----------------------------------------------------------------------------+
#+ YAM Server Setup
#+----------------------------------------------------------------------------+
#+ Author:      Jon Leverrier (jon@youandme.digital)
#+ Copyright:   2018 You & Me Digital SARL
#+ GitHub:      https://github.com/jonleverrier/yam-server-configurator
#+ Issues:      https://github.com/jonleverrier/yam-server-configurator/issues
#+ License:     GPL v3.0
#+ OS:          Ubuntu 16.0.4, 18.04
#+ Release:     1.1.0
#+----------------------------------------------------------------------------+

# Change these settings below before running the script for the first time
YAM_EMAIL_BUG=$(echo -en 'bugs@youandme.digital')
YAM_EMAIL_SSL=$(echo -en 'jon@youandme.digital')
YAM_DATEFORMAT_TIMEZONE=$(echo -en 'Europe/Paris')

# initial password for protected directories. can be overriden
# after setup
YAM_PASSWORD_GENERIC=$(openssl rand -base64 24)

# S3 backup settings
YAM_SERVER_NAME=$(echo -en 'yam-avalon-ams3-01')

# Colour options
COLOUR_RESTORE=$(echo -en '\033[0m')
COLOUR_RED=$(echo -en '\033[00;31m')
COLOUR_GREEN=$(echo -en '\033[00;32m')
COLOUR_YELLOW=$(echo -en '\033[00;33m')
COLOUR_BLUE=$(echo -en '\033[00;34m')
COLOUR_MAGENTA=$(echo -en '\033[00;35m')
COLOUR_PURPLE=$(echo -en '\033[00;35m')
COLOUR_CYAN=$(echo -en '\033[00;36m')
COLOUR_LIGHTGRAY=$(echo -en '\033[00;37m')
COLOUR_LRED=$(echo -en '\033[01;31m')
COLOUR_LGREEN=$(echo -en '\033[01;32m')
COLOUR_LYELLOW=$(echo -en '\033[01;33m')
COLOUR_LMAGENTA=$(echo -en '\033[01;35m')
COLOUR_LPURPLE=$(echo -en '\033[01;35m')
COLOUR_LCYAN=$(echo -en '\033[01;36m')
COLOUR_WHITE=$(echo -en '\033[01;37m')

# Setup up yes no questions
# taken from https://djm.me/ask
# nothing to edit here...
ask() {
    local prompt default reply

    while true; do

        if [ "${2:-}" = "Y" ]; then
            prompt="Y/n"
            default=Y
        elif [ "${2:-}" = "N" ]; then
            prompt="y/N"
            default=N
        else
            prompt="y/n"
            default=
        fi

        # Ask the question (not using "read -p" as it uses stderr not stdout)
        echo -n "$1 [$prompt] "

        # Read the answer (use /dev/tty in case stdin is redirected from
        # somewhere else)
        read reply </dev/tty

        # Default?
        if [ -z "$reply" ]; then
            reply=$default
        fi

        # Check if the reply is valid
        case "$reply" in
            Y*|y*) return 0 ;;
            N*|n*) return 1 ;;
        esac

    done
}

# check if root user
if [ "${EUID}" != 0 ];
then
    echo '------------------------------------------------------------------------'
    echo 'YAM Manager should be executed as the root user. Please switch to the'
    echo 'root user and try again'
    echo '------------------------------------------------------------------------'
    exit
fi

# Load setup server function
setupServer() {
    if ask "Are you sure you want to setup a new server?"; then
        read -p "Enter a sudo user  : " USER_SUDO
        read -s -p "Enter a sudo password  : " USER_SUDO_PASSWORD
        echo
        read -s -p "Enter a MYSQL password for sudo user  : " PASSWORD_MYSQL_SUDO
        echo
        read -s -p "Enter a MYSQL password for root user  : " PASSWORD_MYSQL_ROOT
        echo
        read -p "Enter domain name for the default website  : " URL_SERVER_DEFAULT
        read -p "Enter domain name for phpMyAdmin  : " URL_SERVER_PMA
        echo '------------------------------------------------------------------------'
        echo 'Setting up a new Ubuntu server'
        echo '------------------------------------------------------------------------'
        echo 'This will install a LEMP stack plus core packages'
        echo ''

        # Adjusting server settings ...
        echo "${COLOUR_WHITE}>> Adjusting server settings...${COLOUR_RESTORE}"

        # Setting timezone
        ln -sf /usr/share/zoneinfo/${YAM_DATEFORMAT_TIMEZONE} /etc/localtime

        # Setting up skeleton directory
        mkdir -p /etc/skel/tmp
        mkdir -p /etc/skel/logs
        mkdir -p /etc/skel/logs/nginx
        mkdir -p /etc/skel/public

        # Privacy tweaks
        sed -i "s/enabled=1/enabled=0/" /etc/default/apport
        systemctl stop apport.service
        systemctl disable apport.service
        systemctl mask apport.service
        apt-get remove -y popularity-contest

        # Install auditing system
        apt-get install -y auditd
        cat > /etc/audit/rules.d/audit.rules << EOF
## First rule - delete all
-D

## Increase the buffers to survive stress events.
## Make this bigger for busy systems
-b 8192

## This determine how long to wait in burst of events
--backlog_wait_time 0

## Set failure mode to syslog
-f 1

## Watch files
-w /etc/hosts -p wa -k file_change_hosts
-w /etc/host.conf -p wa -k file_change_hostconf
-w /etc/nginx/nginx.conf -p wa -k file_change_nginxconf
-w /etc/host.conf -p wa -k file_change_hostconf
-w /etc/php/7.1/fpm/php.ini -p wa -k file_change_phpini
-w /etc/fail2ban/jail.local -p wa -k file_change_jaillocal
-w /etc/ssh/sshd_config -p wa -k file_change_sshdconfig

## Watch directories
-w /etc/sudoers.d/ -p rwa -k directory_sudoers
-w /etc/cron.d/ -p rwa -k directory_cron
-w /etc/nginx/conf.d/ -p rwa -k directory_nginxconf
-w /etc/ssh/ -p rwa -k directory_ssh

## Monitor changes and executions within /tmp
-w /tmp/ -p wa -k file_write_tmp
-w /tmp/ -p x -k file_exec_tmp

## Monitor administrator access to /home directories
-a always,exit -F dir=/home/ -F uid=0 -C auid!=obj_uid -k user_admin_home
EOF
        service auditd restart

        # Upgrade system and base packages
        echo "${COLOUR_WHITE}>> Configuring packages...${COLOUR_RESTORE}"
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -q -y -u  -o Dpkg::Options::="--force-confdef" --allow-downgrades --allow-remove-essential --allow-change-held-packages --allow-change-held-packages --allow-unauthenticated;

        # Install packages
        apt-get update
        add-apt-repository -y ppa:ondrej/php
        add-apt-repository -y ppa:certbot/certbot
        apt-get -y --allow-downgrades --allow-remove-essential --allow-change-held-packages install software-properties-common apache2-utils whois htop zip unzip s3cmd nmap
        apt-get clean
        apt-get purge -y snapd
        curl -sSL https://agent.digitalocean.com/install.sh | sh

        # Install yam utilities
        wget -N https://raw.githubusercontent.com/jonleverrier/yam-server-configurator/master/yam_backup_local.sh
        wget -N https://raw.githubusercontent.com/jonleverrier/yam-server-configurator/master/yam_backup_s3.sh
        wget -N https://raw.githubusercontent.com/jonleverrier/yam-server-configurator/master/yam_backup_system.sh
        wget -N https://raw.githubusercontent.com/jonleverrier/yam-server-configurator/master/yam_sync_s3.sh
        wget -N https://raw.githubusercontent.com/jonleverrier/yam-server-configurator/master/yam_manage.sh
        wget -N https://raw.githubusercontent.com/jonleverrier/yam-server-configurator/master/yam_secure.sh
        wget -N https://raw.githubusercontent.com/jonleverrier/yam-server-configurator/master/yam_update.sh

        # lock down files to root user only
        chmod -R 700 /usr/local/bin/yam_backup_local.sh
        chmod -R 700 /usr/local/bin/yam_backup_s3.sh
        chmod -R 700 /usr/local/bin/yam_backup_system.sh
        chmod -R 700 /usr/local/bin/yam_sync_s3.sh
        chmod -R 700 /usr/local/bin/yam_setup.sh
        chmod -R 700 /usr/local/bin/yam_manage.sh
        chmod -R 700 /usr/local/bin/yam_secure.sh
        chmod -R 700 /usr/local/bin/yam_update.sh

        echo "${COLOUR_WHITE}>> Setting up user...${COLOUR_RESTORE}"

        # Adding a sudo user and setting password
        adduser --disabled-password --gecos "" ${USER_SUDO}
        adduser ${USER_SUDO} sudo
        PASSWORD=$(mkpasswd ${USER_SUDO_PASSWORD})
        usermod --password ${PASSWORD} ${USER_SUDO}

        # disable bash history
        echo 'set +o history' >> ~/.bashrc

        # adds sudo user to sudoers file to stop password prompt
        cat > /etc/sudoers.d/${USER_SUDO} << EOF
# Generated by the YAM server configurator
# Do not edit as you may loose your changes
# If you have found a bug, please email ${YAM_EMAIL_BUG}

# User rules for ${USER_SUDO}
${USER_SUDO} ALL=(ALL) NOPASSWD:ALL
EOF

        # Install SSL
        echo "${COLOUR_WHITE}>> Installing SSL...${COLOUR_RESTORE}"
        apt-get install -y python-certbot-nginx

        # Configure SSL
        certbot -n --nginx certonly --agree-tos --email ${YAM_EMAIL_SSL} -d ${URL_SERVER_DEFAULT} -d ${URL_SERVER_PMA} || { echo 'Problems connecting to Certbot. Please try again.' ; exit 1; }

        # Install NGINX
        echo "${COLOUR_WHITE}>> Installing NGINX...${COLOUR_RESTORE}"
        apt-get install -y --allow-downgrades --allow-remove-essential --allow-change-held-packages nginx

        # Configure NGINX
        ufw allow 'Nginx Full'
        ufw delete allow 'Nginx HTTP'
        ufw delete allow 'Nginx HTTPS'

        # Disable The Default Nginx Site
        rm -rf /etc/nginx/sites-available/
        rm -rf /etc/nginx/sites-enabled/

        # setup log rotation
        cat > /etc/logrotate.d/${USER_SUDO} << EOF
/home/${USER_SUDO}/logs/nginx/*.log {
    daily
    missingok
    rotate 7
    compress
    size 5M
    notifempty
    create 0640 www-data www-data
    sharedscripts
}
EOF

        # Backup the original nginx.conf file
        cp /etc/nginx/nginx.conf{,.bak}

        # Replace default nginx.conf file
        cat > /etc/nginx/nginx.conf << EOF
# Generated by the YAM server configurator
# Do not edit as you may loose your changes
# If you have found a bug, please email ${YAM_EMAIL_BUG}

user www-data;
# work processes = the amount of cores the server has
worker_processes 1;
pid /run/nginx.pid;

events {
    use epoll;
    #in the terminal type "ulimit -n" to find out the number of worker connections
    worker_connections 1024;
}

http {

    ##
    # Basic Settings
    ##

    # copies data between one FD and other from within the kernel
    # faster then read() + write()
    sendfile on;

    # send headers in one peace, its better then sending them one by one
    tcp_nopush on;

    # don't buffer data sent, good for small data bursts in real time
    tcp_nodelay on;

    types_hash_max_size 2048;

    # hide what version of NGINX the server is running
    server_tokens off;

    server_names_hash_bucket_size 512;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ##
    # Buffers
    ##

    client_body_buffer_size 128K;
    client_header_buffer_size 1k;
    client_max_body_size 256m;
    large_client_header_buffers 4 8k;
    client_body_temp_path /tmp/client_body_temp;

    ##
    # Timeouts
    ##

    client_body_timeout 3000;
    client_header_timeout 3000;
    keepalive_timeout 3000;
    send_timeout 3000;

    ##
    # SSL Settings
    ##

    ssl_protocols TLSv1 TLSv1.1 TLSv1.2; # Dropping SSLv3, ref: POODLE
    ssl_prefer_server_ciphers on;

    ##
    # Logging Settings
    ##

    # to boost I/O on HDD we can disable access logs
    access_log off;

    # default error log
    error_log /var/log/nginx/error.log;

    ##
    # Gzip Settings
    ##

    gzip on;
    gzip_vary on;
    gzip_comp_level 6;
    gzip_min_length  256;
    gzip_disable "msie6";
    gzip_proxied expired no-cache no-store private auth;

    gzip_types
    application/atom+xml
    application/javascript
    application/json
    application/ld+json
    application/manifest+json
    application/rss+xml
    application/vnd.geo+json
    application/vnd.ms-fontobject
    application/x-font-ttf
    application/x-web-app-manifest+json
    application/xhtml+xml
    application/xml
    font/opentype
    image/bmp
    image/svg+xml
    image/x-icon
    text/cache-manifest
    text/css
    text/plain
    text/vcard
    text/vnd.rim.location.xloc
    text/vtt
    text/x-component
    text/x-cross-domain-policy;

    ##
    # Virtual Host Configs
    ##

    include /etc/nginx/default_server.conf;
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/main_extra.conf;
}
EOF

        # Added if statement here to prevent the file being overwritten
        # if setup has already been run
        if [ -f /etc/nginx/main_extra.conf ]; then
            echo "${COLOUR_CYAN}-- main_extra.conf already exists. Skipping...${COLOUR_RESTORE}"
        else
            cat > /etc/nginx/main_extra.conf << EOF
# Generated by the YAM server configurator
EOF
        fi

        # Add default_server.conf
        cat > /etc/nginx/default_server.conf << EOF
# Generated by the YAM server configurator
# Do not edit as you may loose your changes
# If you have found a bug, please email ${YAM_EMAIL_BUG}

# this file generates an error 404 if the server_name is not found under https
# it also defines the custom error pages used on the server

# /nginx/default_server.conf

server {
    listen	80 default_server;
    listen	[::]:80 default_server;

    # stop favicon generating 404
    location = /favicon.ico {
        log_not_found off;
    }

    include /etc/nginx/default_error_messages.conf;

    location / {
        return 404;
    }

}
EOF

        cat > /etc/nginx/default_error_messages.conf << EOF
# Generated by the YAM server configurator
# Do not edit as you may loose your changes
# If you have found a bug, please email ${YAM_EMAIL_BUG}

# /nginx/default_error_messages.conf

error_page 401 /401.html;
location = /401.html {
    root /var/www/errors;
    internal;
}

error_page 403 /403.html;
location = /403.html {
    root /var/www/errors;
    internal;
}

error_page 404 /404.html;
location = /404.html {
    root /var/www/errors;
    internal;
}

error_page 500 /500.html;
location = /500.html {
    root /var/www/errors;
    internal;
}

error_page 501 /501.html;
location = /501.html {
    root /var/www/errors;
    internal;
}

error_page 502 /502.html;
location = /502.html {
    root /var/www/errors;
    internal;
}

error_page 503 /503.html;
location = /503.html {
    root /var/www/errors;
    internal;
}
EOF
        # Adding default conf file for default website
        cat > /etc/nginx/conf.d/_default.conf << EOF
# Generated by the YAM server configurator
# Do not edit as you may loose your changes
# If you have found a bug, please email ${YAM_EMAIL_BUG}

# /nginx/conf.d/_default.conf

# dev url https
server {
    server_name ${URL_SERVER_DEFAULT};
    include /etc/nginx/conf.d/_default.d/main.conf;
    include /etc/nginx/default_error_messages.conf;

    listen [::]:443 http2 ssl;
    listen 443 http2 ssl;
    ssl_certificate /etc/letsencrypt/live/${URL_SERVER_DEFAULT}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${URL_SERVER_DEFAULT}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

}

# dev url redirect http to https
server {
    server_name ${URL_SERVER_DEFAULT};
    return 301 https://\$host\$request_uri;

    listen 80;
    listen [::]:80;

}

EOF

        # Adding default conf file for phpMyAdmin website
        cat > /etc/nginx/conf.d/phpmyadmin.conf << EOF
# Generated by the YAM server configurator
# Do not edit as you may loose your changes
# If you have found a bug, please email ${YAM_EMAIL_BUG}

# /nginx/conf.d/phpmyadmin.conf

# dev url https
server {
    server_name ${URL_SERVER_PMA};
    include /etc/nginx/conf.d/phpmyadmin.d/main.conf;
    include /etc/nginx/default_error_messages.conf;

    listen [::]:443 http2 ssl;
    listen 443 http2 ssl;
    ssl_certificate /etc/letsencrypt/live/${URL_SERVER_DEFAULT}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${URL_SERVER_DEFAULT}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

}

# dev url redirect http to https
server {
    server_name ${URL_SERVER_PMA};
    return 301 https://\$host\$request_uri;

    listen 80;
    listen [::]:80;
}
EOF
        # Adding conf file and directory for default website
        mkdir -p /etc/nginx/conf.d/_default.d
        cat > /etc/nginx/conf.d/_default.d/main.conf << EOF
# Generated by the YAM server configurator
# Do not edit as you may loose your changes
# If you have found a bug, please email ${YAM_EMAIL_BUG}

# /nginx/conf.d/_default.d/main.conf

# custom headers file loads here if included
include /etc/nginx/custom.d/_default.d/_default.location.header.*.conf;

# custom body file loads here if included
include /etc/nginx/custom.d/_default.d/_default.location.body.*.conf;

# stop favicon generating 404
location = /favicon.ico {
    log_not_found off;
}

# custom cache file loads here if included
include /etc/nginx/custom.d/_default.d/_default.location.footer.*.conf;

# as this is the default website, non existant sub domain names will
# redirect to this domain, so serve them an error 404
location / {
    return 404;
}
EOF

        # Adding conf file and directory for phpMyAdmin website
        mkdir -p /etc/nginx/conf.d/phpmyadmin.d
        cat > /etc/nginx/conf.d/phpmyadmin.d/main.conf << EOF
# Generated by the YAM server configurator
# Do not edit as you may loose your changes
# If you have found a bug, please email ${YAM_EMAIL_BUG}

# /nginx/conf.d/phpmyadmin.d/main.conf

error_log           /home/${USER_SUDO}/logs/nginx/phpmyadmin_error.log;

# custom headers file loads here if included
include /etc/nginx/custom.d/phpmyadmin.d/phpmyadmin.location.header.*.conf;

# location of web root
root /home/${USER_SUDO}/public/phpmyadmin;
index index.php index.htm index.html;

# setup php to use FPM
location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/run/php/php7.1-fpm-phpmyadmin.sock;
}

# custom body file loads here if included
include /etc/nginx/custom.d/phpmyadmin.d/phpmyadmin.location.body.*.conf;

# prevent access to hidden files
location ~ /\. {
    deny all;
}

# stop favicon generating 404
location = /favicon.ico {
    log_not_found off;
}

# redirect to phpmyadmin folder
location = / {
    return 301 http://\$host/phpmyadmin;
}

# add password directory
location /phpmyadmin {
    auth_basic "Private";
    auth_basic_user_file /home/${USER_SUDO}/.htpasswd;
}

# custom cache file loads here if included
include /etc/nginx/custom.d/phpmyadmin.d/phpmyadmin.location.footer.*.conf;
EOF
        # Adding custom conf directory for default website
        mkdir -p /etc/nginx/custom.d/_default.d
        cat > /etc/nginx/custom.d/_default.d/readme.txt << EOF
In this directory you can add custom rewrite rules in the follwing format.

_default.location.header.*.conf
_default.location.body.*.conf
_default.location.footer.*.conf

Don't forget to reload NGINX from the terminal using:
systemctl reload nginx
EOF
        # Adding custom conf directory for default website
        mkdir -p /etc/nginx/custom.d/phpmyadmin.d
        cat > /etc/nginx/custom.d/phpmyadmin.d/readme.txt << EOF
In this directory you can add custom rewrite rules in the follwing format.

phpmyadmin.location.header.*.conf
phpmyadmin.location.body.*.conf
phpmyadmin.location.footer.*.conf

Don't forget to reload NGINX from the terminal using:
systemctl reload nginx
EOF
        # Adding default error pages
        mkdir -p /var/www/errors
        cat > /var/www/errors/401.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
<!-- Simple HttpErrorPages | MIT License | https://github.com/AndiDittrich/HttpErrorPages -->
<meta charset="utf-8" /><meta http-equiv="X-UA-Compatible" content="IE=edge" /><meta name="viewport" content="width=device-width, initial-scale=1" />
<title>We've got some trouble | 401 - Unauthorized</title>
<style type="text/css">/*! normalize.css v5.0.0 | MIT License | github.com/necolas/normalize.css */html{font-family:sans-serif;line-height:1.15;-ms-text-size-adjust:100%;-webkit-text-size-adjust:100%}body{margin:0}article,aside,footer,header,nav,section{display:block}h1{font-size:2em;margin:.67em 0}figcaption,figure,main{display:block}figure{margin:1em 40px}hr{box-sizing:content-box;height:0;overflow:visible}pre{font-family:monospace,monospace;font-size:1em}a{background-color:transparent;-webkit-text-decoration-skip:objects}a:active,a:hover{outline-width:0}abbr[title]{border-bottom:none;text-decoration:underline;text-decoration:underline dotted}b,strong{font-weight:inherit}b,strong{font-weight:bolder}code,kbd,samp{font-family:monospace,monospace;font-size:1em}dfn{font-style:italic}mark{background-color:#ff0;color:#000}small{font-size:80%}sub,sup{font-size:75%;line-height:0;position:relative;vertical-align:baseline}sub{bottom:-.25em}sup{top:-.5em}audio,video{display:inline-block}audio:not([controls]){display:none;height:0}img{border-style:none}svg:not(:root){overflow:hidden}button,input,optgroup,select,textarea{font-family:sans-serif;font-size:100%;line-height:1.15;margin:0}button,input{overflow:visible}button,select{text-transform:none}[type=reset],[type=submit],button,html [type=button]{-webkit-appearance:button}[type=button]::-moz-focus-inner,[type=reset]::-moz-focus-inner,[type=submit]::-moz-focus-inner,button::-moz-focus-inner{border-style:none;padding:0}[type=button]:-moz-focusring,[type=reset]:-moz-focusring,[type=submit]:-moz-focusring,button:-moz-focusring{outline:1px dotted ButtonText}fieldset{border:1px solid silver;margin:0 2px;padding:.35em .625em .75em}legend{box-sizing:border-box;color:inherit;display:table;max-width:100%;padding:0;white-space:normal}progress{display:inline-block;vertical-align:baseline}textarea{overflow:auto}[type=checkbox],[type=radio]{box-sizing:border-box;padding:0}[type=number]::-webkit-inner-spin-button,[type=number]::-webkit-outer-spin-button{height:auto}[type=search]{-webkit-appearance:textfield;outline-offset:-2px}[type=search]::-webkit-search-cancel-button,[type=search]::-webkit-search-decoration{-webkit-appearance:none}::-webkit-file-upload-button{-webkit-appearance:button;font:inherit}details,menu{display:block}summary{display:list-item}canvas{display:inline-block}template{display:none}[hidden]{display:none}/*! Simple HttpErrorPages | MIT X11 License | https://github.com/AndiDittrich/HttpErrorPages */body,html{width:100%;height:100%;background-color:#21232a}body{color:#fff;text-align:center;text-shadow:0 2px 4px rgba(0,0,0,.5);padding:0;min-height:100%;-webkit-box-shadow:inset 0 0 100px rgba(0,0,0,.8);box-shadow:inset 0 0 100px rgba(0,0,0,.8);display:table;font-family:"Open Sans",Arial,sans-serif}h1{font-family:inherit;font-weight:500;line-height:1.1;color:inherit;font-size:36px}h1 small{font-size:68%;font-weight:400;line-height:1;color:#777}a{text-decoration:none;color:#fff;font-size:inherit;border-bottom:dotted 1px #707070}.lead{color:silver;font-size:21px;line-height:1.4}.cover{display:table-cell;vertical-align:middle;padding:0 20px}footer{position:fixed;width:100%;height:40px;left:0;bottom:0;color:#a0a0a0;font-size:14px}</style>
</head>
<body>
<div class="cover"><h1>Unauthorized <small>Error 401</small></h1><p class="lead">The requested page requires authentication.</p></div>
</body>
</html>
EOF

        cat > /var/www/errors/403.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
<!-- Simple HttpErrorPages | MIT License | https://github.com/AndiDittrich/HttpErrorPages -->
<meta charset="utf-8" /><meta http-equiv="X-UA-Compatible" content="IE=edge" /><meta name="viewport" content="width=device-width, initial-scale=1" />
<title>We've got some trouble | 403 - Access Denied</title>
<style type="text/css">/*! normalize.css v5.0.0 | MIT License | github.com/necolas/normalize.css */html{font-family:sans-serif;line-height:1.15;-ms-text-size-adjust:100%;-webkit-text-size-adjust:100%}body{margin:0}article,aside,footer,header,nav,section{display:block}h1{font-size:2em;margin:.67em 0}figcaption,figure,main{display:block}figure{margin:1em 40px}hr{box-sizing:content-box;height:0;overflow:visible}pre{font-family:monospace,monospace;font-size:1em}a{background-color:transparent;-webkit-text-decoration-skip:objects}a:active,a:hover{outline-width:0}abbr[title]{border-bottom:none;text-decoration:underline;text-decoration:underline dotted}b,strong{font-weight:inherit}b,strong{font-weight:bolder}code,kbd,samp{font-family:monospace,monospace;font-size:1em}dfn{font-style:italic}mark{background-color:#ff0;color:#000}small{font-size:80%}sub,sup{font-size:75%;line-height:0;position:relative;vertical-align:baseline}sub{bottom:-.25em}sup{top:-.5em}audio,video{display:inline-block}audio:not([controls]){display:none;height:0}img{border-style:none}svg:not(:root){overflow:hidden}button,input,optgroup,select,textarea{font-family:sans-serif;font-size:100%;line-height:1.15;margin:0}button,input{overflow:visible}button,select{text-transform:none}[type=reset],[type=submit],button,html [type=button]{-webkit-appearance:button}[type=button]::-moz-focus-inner,[type=reset]::-moz-focus-inner,[type=submit]::-moz-focus-inner,button::-moz-focus-inner{border-style:none;padding:0}[type=button]:-moz-focusring,[type=reset]:-moz-focusring,[type=submit]:-moz-focusring,button:-moz-focusring{outline:1px dotted ButtonText}fieldset{border:1px solid silver;margin:0 2px;padding:.35em .625em .75em}legend{box-sizing:border-box;color:inherit;display:table;max-width:100%;padding:0;white-space:normal}progress{display:inline-block;vertical-align:baseline}textarea{overflow:auto}[type=checkbox],[type=radio]{box-sizing:border-box;padding:0}[type=number]::-webkit-inner-spin-button,[type=number]::-webkit-outer-spin-button{height:auto}[type=search]{-webkit-appearance:textfield;outline-offset:-2px}[type=search]::-webkit-search-cancel-button,[type=search]::-webkit-search-decoration{-webkit-appearance:none}::-webkit-file-upload-button{-webkit-appearance:button;font:inherit}details,menu{display:block}summary{display:list-item}canvas{display:inline-block}template{display:none}[hidden]{display:none}/*! Simple HttpErrorPages | MIT X11 License | https://github.com/AndiDittrich/HttpErrorPages */body,html{width:100%;height:100%;background-color:#21232a}body{color:#fff;text-align:center;text-shadow:0 2px 4px rgba(0,0,0,.5);padding:0;min-height:100%;-webkit-box-shadow:inset 0 0 100px rgba(0,0,0,.8);box-shadow:inset 0 0 100px rgba(0,0,0,.8);display:table;font-family:"Open Sans",Arial,sans-serif}h1{font-family:inherit;font-weight:500;line-height:1.1;color:inherit;font-size:36px}h1 small{font-size:68%;font-weight:400;line-height:1;color:#777}a{text-decoration:none;color:#fff;font-size:inherit;border-bottom:dotted 1px #707070}.lead{color:silver;font-size:21px;line-height:1.4}.cover{display:table-cell;vertical-align:middle;padding:0 20px}footer{position:fixed;width:100%;height:40px;left:0;bottom:0;color:#a0a0a0;font-size:14px}</style>
</head>
<body>
<div class="cover"><h1>Access Denied <small>Error 403</small></h1><p class="lead">The requested page requires an authentication.</p></div>

</body>
</html>
EOF

        cat > /var/www/errors/404.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
<!-- Simple HttpErrorPages | MIT License | https://github.com/AndiDittrich/HttpErrorPages -->
<meta charset="utf-8" /><meta http-equiv="X-UA-Compatible" content="IE=edge" /><meta name="viewport" content="width=device-width, initial-scale=1" />
<title>We've got some trouble | 404 - Resource not found</title>
<style type="text/css">/*! normalize.css v5.0.0 | MIT License | github.com/necolas/normalize.css */html{font-family:sans-serif;line-height:1.15;-ms-text-size-adjust:100%;-webkit-text-size-adjust:100%}body{margin:0}article,aside,footer,header,nav,section{display:block}h1{font-size:2em;margin:.67em 0}figcaption,figure,main{display:block}figure{margin:1em 40px}hr{box-sizing:content-box;height:0;overflow:visible}pre{font-family:monospace,monospace;font-size:1em}a{background-color:transparent;-webkit-text-decoration-skip:objects}a:active,a:hover{outline-width:0}abbr[title]{border-bottom:none;text-decoration:underline;text-decoration:underline dotted}b,strong{font-weight:inherit}b,strong{font-weight:bolder}code,kbd,samp{font-family:monospace,monospace;font-size:1em}dfn{font-style:italic}mark{background-color:#ff0;color:#000}small{font-size:80%}sub,sup{font-size:75%;line-height:0;position:relative;vertical-align:baseline}sub{bottom:-.25em}sup{top:-.5em}audio,video{display:inline-block}audio:not([controls]){display:none;height:0}img{border-style:none}svg:not(:root){overflow:hidden}button,input,optgroup,select,textarea{font-family:sans-serif;font-size:100%;line-height:1.15;margin:0}button,input{overflow:visible}button,select{text-transform:none}[type=reset],[type=submit],button,html [type=button]{-webkit-appearance:button}[type=button]::-moz-focus-inner,[type=reset]::-moz-focus-inner,[type=submit]::-moz-focus-inner,button::-moz-focus-inner{border-style:none;padding:0}[type=button]:-moz-focusring,[type=reset]:-moz-focusring,[type=submit]:-moz-focusring,button:-moz-focusring{outline:1px dotted ButtonText}fieldset{border:1px solid silver;margin:0 2px;padding:.35em .625em .75em}legend{box-sizing:border-box;color:inherit;display:table;max-width:100%;padding:0;white-space:normal}progress{display:inline-block;vertical-align:baseline}textarea{overflow:auto}[type=checkbox],[type=radio]{box-sizing:border-box;padding:0}[type=number]::-webkit-inner-spin-button,[type=number]::-webkit-outer-spin-button{height:auto}[type=search]{-webkit-appearance:textfield;outline-offset:-2px}[type=search]::-webkit-search-cancel-button,[type=search]::-webkit-search-decoration{-webkit-appearance:none}::-webkit-file-upload-button{-webkit-appearance:button;font:inherit}details,menu{display:block}summary{display:list-item}canvas{display:inline-block}template{display:none}[hidden]{display:none}/*! Simple HttpErrorPages | MIT X11 License | https://github.com/AndiDittrich/HttpErrorPages */body,html{width:100%;height:100%;background-color:#21232a}body{color:#fff;text-align:center;text-shadow:0 2px 4px rgba(0,0,0,.5);padding:0;min-height:100%;-webkit-box-shadow:inset 0 0 100px rgba(0,0,0,.8);box-shadow:inset 0 0 100px rgba(0,0,0,.8);display:table;font-family:"Open Sans",Arial,sans-serif}h1{font-family:inherit;font-weight:500;line-height:1.1;color:inherit;font-size:36px}h1 small{font-size:68%;font-weight:400;line-height:1;color:#777}a{text-decoration:none;color:#fff;font-size:inherit;border-bottom:dotted 1px #707070}.lead{color:silver;font-size:21px;line-height:1.4}.cover{display:table-cell;vertical-align:middle;padding:0 20px}footer{position:fixed;width:100%;height:40px;left:0;bottom:0;color:#a0a0a0;font-size:14px}</style>
</head>
<body>
<div class="cover"><h1>Page not found <small>Error 404</small></h1><p class="lead">The requested page could not be found but may be available again in the future.</p></div>
</body>
</html>
EOF

        cat > /var/www/errors/500.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
<!-- Simple HttpErrorPages | MIT License | https://github.com/AndiDittrich/HttpErrorPages -->
<meta charset="utf-8" /><meta http-equiv="X-UA-Compatible" content="IE=edge" /><meta name="viewport" content="width=device-width, initial-scale=1" />
<title>We've got some trouble | 500 - Webservice currently unavailable</title>
<style type="text/css">/*! normalize.css v5.0.0 | MIT License | github.com/necolas/normalize.css */html{font-family:sans-serif;line-height:1.15;-ms-text-size-adjust:100%;-webkit-text-size-adjust:100%}body{margin:0}article,aside,footer,header,nav,section{display:block}h1{font-size:2em;margin:.67em 0}figcaption,figure,main{display:block}figure{margin:1em 40px}hr{box-sizing:content-box;height:0;overflow:visible}pre{font-family:monospace,monospace;font-size:1em}a{background-color:transparent;-webkit-text-decoration-skip:objects}a:active,a:hover{outline-width:0}abbr[title]{border-bottom:none;text-decoration:underline;text-decoration:underline dotted}b,strong{font-weight:inherit}b,strong{font-weight:bolder}code,kbd,samp{font-family:monospace,monospace;font-size:1em}dfn{font-style:italic}mark{background-color:#ff0;color:#000}small{font-size:80%}sub,sup{font-size:75%;line-height:0;position:relative;vertical-align:baseline}sub{bottom:-.25em}sup{top:-.5em}audio,video{display:inline-block}audio:not([controls]){display:none;height:0}img{border-style:none}svg:not(:root){overflow:hidden}button,input,optgroup,select,textarea{font-family:sans-serif;font-size:100%;line-height:1.15;margin:0}button,input{overflow:visible}button,select{text-transform:none}[type=reset],[type=submit],button,html [type=button]{-webkit-appearance:button}[type=button]::-moz-focus-inner,[type=reset]::-moz-focus-inner,[type=submit]::-moz-focus-inner,button::-moz-focus-inner{border-style:none;padding:0}[type=button]:-moz-focusring,[type=reset]:-moz-focusring,[type=submit]:-moz-focusring,button:-moz-focusring{outline:1px dotted ButtonText}fieldset{border:1px solid silver;margin:0 2px;padding:.35em .625em .75em}legend{box-sizing:border-box;color:inherit;display:table;max-width:100%;padding:0;white-space:normal}progress{display:inline-block;vertical-align:baseline}textarea{overflow:auto}[type=checkbox],[type=radio]{box-sizing:border-box;padding:0}[type=number]::-webkit-inner-spin-button,[type=number]::-webkit-outer-spin-button{height:auto}[type=search]{-webkit-appearance:textfield;outline-offset:-2px}[type=search]::-webkit-search-cancel-button,[type=search]::-webkit-search-decoration{-webkit-appearance:none}::-webkit-file-upload-button{-webkit-appearance:button;font:inherit}details,menu{display:block}summary{display:list-item}canvas{display:inline-block}template{display:none}[hidden]{display:none}/*! Simple HttpErrorPages | MIT X11 License | https://github.com/AndiDittrich/HttpErrorPages */body,html{width:100%;height:100%;background-color:#21232a}body{color:#fff;text-align:center;text-shadow:0 2px 4px rgba(0,0,0,.5);padding:0;min-height:100%;-webkit-box-shadow:inset 0 0 100px rgba(0,0,0,.8);box-shadow:inset 0 0 100px rgba(0,0,0,.8);display:table;font-family:"Open Sans",Arial,sans-serif}h1{font-family:inherit;font-weight:500;line-height:1.1;color:inherit;font-size:36px}h1 small{font-size:68%;font-weight:400;line-height:1;color:#777}a{text-decoration:none;color:#fff;font-size:inherit;border-bottom:dotted 1px #707070}.lead{color:silver;font-size:21px;line-height:1.4}.cover{display:table-cell;vertical-align:middle;padding:0 20px}footer{position:fixed;width:100%;height:40px;left:0;bottom:0;color:#a0a0a0;font-size:14px}</style>
</head>
<body>
<div class="cover"><h1>Website currently unavailable <small>Error 500</small></h1><p class="lead">We are currently experiencing technical problems.<br />Please check back shortly.</p></div>
</body>
</html>
EOF

        cat > /var/www/errors/501.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
<!-- Simple HttpErrorPages | MIT License | https://github.com/AndiDittrich/HttpErrorPages -->
<meta charset="utf-8" /><meta http-equiv="X-UA-Compatible" content="IE=edge" /><meta name="viewport" content="width=device-width, initial-scale=1" />
<title>We've got some trouble | 501 - Not Implemented</title>
<style type="text/css">/*! normalize.css v5.0.0 | MIT License | github.com/necolas/normalize.css */html{font-family:sans-serif;line-height:1.15;-ms-text-size-adjust:100%;-webkit-text-size-adjust:100%}body{margin:0}article,aside,footer,header,nav,section{display:block}h1{font-size:2em;margin:.67em 0}figcaption,figure,main{display:block}figure{margin:1em 40px}hr{box-sizing:content-box;height:0;overflow:visible}pre{font-family:monospace,monospace;font-size:1em}a{background-color:transparent;-webkit-text-decoration-skip:objects}a:active,a:hover{outline-width:0}abbr[title]{border-bottom:none;text-decoration:underline;text-decoration:underline dotted}b,strong{font-weight:inherit}b,strong{font-weight:bolder}code,kbd,samp{font-family:monospace,monospace;font-size:1em}dfn{font-style:italic}mark{background-color:#ff0;color:#000}small{font-size:80%}sub,sup{font-size:75%;line-height:0;position:relative;vertical-align:baseline}sub{bottom:-.25em}sup{top:-.5em}audio,video{display:inline-block}audio:not([controls]){display:none;height:0}img{border-style:none}svg:not(:root){overflow:hidden}button,input,optgroup,select,textarea{font-family:sans-serif;font-size:100%;line-height:1.15;margin:0}button,input{overflow:visible}button,select{text-transform:none}[type=reset],[type=submit],button,html [type=button]{-webkit-appearance:button}[type=button]::-moz-focus-inner,[type=reset]::-moz-focus-inner,[type=submit]::-moz-focus-inner,button::-moz-focus-inner{border-style:none;padding:0}[type=button]:-moz-focusring,[type=reset]:-moz-focusring,[type=submit]:-moz-focusring,button:-moz-focusring{outline:1px dotted ButtonText}fieldset{border:1px solid silver;margin:0 2px;padding:.35em .625em .75em}legend{box-sizing:border-box;color:inherit;display:table;max-width:100%;padding:0;white-space:normal}progress{display:inline-block;vertical-align:baseline}textarea{overflow:auto}[type=checkbox],[type=radio]{box-sizing:border-box;padding:0}[type=number]::-webkit-inner-spin-button,[type=number]::-webkit-outer-spin-button{height:auto}[type=search]{-webkit-appearance:textfield;outline-offset:-2px}[type=search]::-webkit-search-cancel-button,[type=search]::-webkit-search-decoration{-webkit-appearance:none}::-webkit-file-upload-button{-webkit-appearance:button;font:inherit}details,menu{display:block}summary{display:list-item}canvas{display:inline-block}template{display:none}[hidden]{display:none}/*! Simple HttpErrorPages | MIT X11 License | https://github.com/AndiDittrich/HttpErrorPages */body,html{width:100%;height:100%;background-color:#21232a}body{color:#fff;text-align:center;text-shadow:0 2px 4px rgba(0,0,0,.5);padding:0;min-height:100%;-webkit-box-shadow:inset 0 0 100px rgba(0,0,0,.8);box-shadow:inset 0 0 100px rgba(0,0,0,.8);display:table;font-family:"Open Sans",Arial,sans-serif}h1{font-family:inherit;font-weight:500;line-height:1.1;color:inherit;font-size:36px}h1 small{font-size:68%;font-weight:400;line-height:1;color:#777}a{text-decoration:none;color:#fff;font-size:inherit;border-bottom:dotted 1px #707070}.lead{color:silver;font-size:21px;line-height:1.4}.cover{display:table-cell;vertical-align:middle;padding:0 20px}footer{position:fixed;width:100%;height:40px;left:0;bottom:0;color:#a0a0a0;font-size:14px}</style>
</head>
<body>
<div class="cover"><h1>Not Implemented <small>Error 501</small></h1><p class="lead">The Webserver cannot recognize the request method.</p></div>

</body>
</html>
EOF

        cat > /var/www/errors/502.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
<!-- Simple HttpErrorPages | MIT License | https://github.com/AndiDittrich/HttpErrorPages -->
<meta charset="utf-8" /><meta http-equiv="X-UA-Compatible" content="IE=edge" /><meta name="viewport" content="width=device-width, initial-scale=1" />
<title>We've got some trouble | 502 - Webservice currently unavailable</title>
<style type="text/css">/*! normalize.css v5.0.0 | MIT License | github.com/necolas/normalize.css */html{font-family:sans-serif;line-height:1.15;-ms-text-size-adjust:100%;-webkit-text-size-adjust:100%}body{margin:0}article,aside,footer,header,nav,section{display:block}h1{font-size:2em;margin:.67em 0}figcaption,figure,main{display:block}figure{margin:1em 40px}hr{box-sizing:content-box;height:0;overflow:visible}pre{font-family:monospace,monospace;font-size:1em}a{background-color:transparent;-webkit-text-decoration-skip:objects}a:active,a:hover{outline-width:0}abbr[title]{border-bottom:none;text-decoration:underline;text-decoration:underline dotted}b,strong{font-weight:inherit}b,strong{font-weight:bolder}code,kbd,samp{font-family:monospace,monospace;font-size:1em}dfn{font-style:italic}mark{background-color:#ff0;color:#000}small{font-size:80%}sub,sup{font-size:75%;line-height:0;position:relative;vertical-align:baseline}sub{bottom:-.25em}sup{top:-.5em}audio,video{display:inline-block}audio:not([controls]){display:none;height:0}img{border-style:none}svg:not(:root){overflow:hidden}button,input,optgroup,select,textarea{font-family:sans-serif;font-size:100%;line-height:1.15;margin:0}button,input{overflow:visible}button,select{text-transform:none}[type=reset],[type=submit],button,html [type=button]{-webkit-appearance:button}[type=button]::-moz-focus-inner,[type=reset]::-moz-focus-inner,[type=submit]::-moz-focus-inner,button::-moz-focus-inner{border-style:none;padding:0}[type=button]:-moz-focusring,[type=reset]:-moz-focusring,[type=submit]:-moz-focusring,button:-moz-focusring{outline:1px dotted ButtonText}fieldset{border:1px solid silver;margin:0 2px;padding:.35em .625em .75em}legend{box-sizing:border-box;color:inherit;display:table;max-width:100%;padding:0;white-space:normal}progress{display:inline-block;vertical-align:baseline}textarea{overflow:auto}[type=checkbox],[type=radio]{box-sizing:border-box;padding:0}[type=number]::-webkit-inner-spin-button,[type=number]::-webkit-outer-spin-button{height:auto}[type=search]{-webkit-appearance:textfield;outline-offset:-2px}[type=search]::-webkit-search-cancel-button,[type=search]::-webkit-search-decoration{-webkit-appearance:none}::-webkit-file-upload-button{-webkit-appearance:button;font:inherit}details,menu{display:block}summary{display:list-item}canvas{display:inline-block}template{display:none}[hidden]{display:none}/*! Simple HttpErrorPages | MIT X11 License | https://github.com/AndiDittrich/HttpErrorPages */body,html{width:100%;height:100%;background-color:#21232a}body{color:#fff;text-align:center;text-shadow:0 2px 4px rgba(0,0,0,.5);padding:0;min-height:100%;-webkit-box-shadow:inset 0 0 100px rgba(0,0,0,.8);box-shadow:inset 0 0 100px rgba(0,0,0,.8);display:table;font-family:"Open Sans",Arial,sans-serif}h1{font-family:inherit;font-weight:500;line-height:1.1;color:inherit;font-size:36px}h1 small{font-size:68%;font-weight:400;line-height:1;color:#777}a{text-decoration:none;color:#fff;font-size:inherit;border-bottom:dotted 1px #707070}.lead{color:silver;font-size:21px;line-height:1.4}.cover{display:table-cell;vertical-align:middle;padding:0 20px}footer{position:fixed;width:100%;height:40px;left:0;bottom:0;color:#a0a0a0;font-size:14px}</style>
</head>
<body>
<div class="cover"><h1>Website currently unavailable <small>Error 502</small></h1><p class="lead">We are currently experiencing technical problems.<br />Please check back shortly.</p></div>
</body>
</html>
EOF

        cat > /var/www/errors/503.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
<!-- Simple HttpErrorPages | MIT License | https://github.com/AndiDittrich/HttpErrorPages -->
<meta charset="utf-8" /><meta http-equiv="X-UA-Compatible" content="IE=edge" /><meta name="viewport" content="width=device-width, initial-scale=1" />
<title>We've got some trouble | 503 - Webservice currently unavailable</title>
<style type="text/css">/*! normalize.css v5.0.0 | MIT License | github.com/necolas/normalize.css */html{font-family:sans-serif;line-height:1.15;-ms-text-size-adjust:100%;-webkit-text-size-adjust:100%}body{margin:0}article,aside,footer,header,nav,section{display:block}h1{font-size:2em;margin:.67em 0}figcaption,figure,main{display:block}figure{margin:1em 40px}hr{box-sizing:content-box;height:0;overflow:visible}pre{font-family:monospace,monospace;font-size:1em}a{background-color:transparent;-webkit-text-decoration-skip:objects}a:active,a:hover{outline-width:0}abbr[title]{border-bottom:none;text-decoration:underline;text-decoration:underline dotted}b,strong{font-weight:inherit}b,strong{font-weight:bolder}code,kbd,samp{font-family:monospace,monospace;font-size:1em}dfn{font-style:italic}mark{background-color:#ff0;color:#000}small{font-size:80%}sub,sup{font-size:75%;line-height:0;position:relative;vertical-align:baseline}sub{bottom:-.25em}sup{top:-.5em}audio,video{display:inline-block}audio:not([controls]){display:none;height:0}img{border-style:none}svg:not(:root){overflow:hidden}button,input,optgroup,select,textarea{font-family:sans-serif;font-size:100%;line-height:1.15;margin:0}button,input{overflow:visible}button,select{text-transform:none}[type=reset],[type=submit],button,html [type=button]{-webkit-appearance:button}[type=button]::-moz-focus-inner,[type=reset]::-moz-focus-inner,[type=submit]::-moz-focus-inner,button::-moz-focus-inner{border-style:none;padding:0}[type=button]:-moz-focusring,[type=reset]:-moz-focusring,[type=submit]:-moz-focusring,button:-moz-focusring{outline:1px dotted ButtonText}fieldset{border:1px solid silver;margin:0 2px;padding:.35em .625em .75em}legend{box-sizing:border-box;color:inherit;display:table;max-width:100%;padding:0;white-space:normal}progress{display:inline-block;vertical-align:baseline}textarea{overflow:auto}[type=checkbox],[type=radio]{box-sizing:border-box;padding:0}[type=number]::-webkit-inner-spin-button,[type=number]::-webkit-outer-spin-button{height:auto}[type=search]{-webkit-appearance:textfield;outline-offset:-2px}[type=search]::-webkit-search-cancel-button,[type=search]::-webkit-search-decoration{-webkit-appearance:none}::-webkit-file-upload-button{-webkit-appearance:button;font:inherit}details,menu{display:block}summary{display:list-item}canvas{display:inline-block}template{display:none}[hidden]{display:none}/*! Simple HttpErrorPages | MIT X11 License | https://github.com/AndiDittrich/HttpErrorPages */body,html{width:100%;height:100%;background-color:#21232a}body{color:#fff;text-align:center;text-shadow:0 2px 4px rgba(0,0,0,.5);padding:0;min-height:100%;-webkit-box-shadow:inset 0 0 100px rgba(0,0,0,.8);box-shadow:inset 0 0 100px rgba(0,0,0,.8);display:table;font-family:"Open Sans",Arial,sans-serif}h1{font-family:inherit;font-weight:500;line-height:1.1;color:inherit;font-size:36px}h1 small{font-size:68%;font-weight:400;line-height:1;color:#777}a{text-decoration:none;color:#fff;font-size:inherit;border-bottom:dotted 1px #707070}.lead{color:silver;font-size:21px;line-height:1.4}.cover{display:table-cell;vertical-align:middle;padding:0 20px}footer{position:fixed;width:100%;height:40px;left:0;bottom:0;color:#a0a0a0;font-size:14px}</style>
</head>
<body>
<div class="cover"><h1>Website currently unavailable <small>Error 503</small></h1><p class="lead">We are currently experiencing technical problems.<br />Please check back shortly.</p></div>

</body>
</html>
EOF
        systemctl reload nginx

        # Install MYSQL
        echo "${COLOUR_WHITE}>> Installing MariaDB...${COLOUR_RESTORE}"
        apt-get install -y --allow-downgrades --allow-remove-essential --allow-change-held-packages mariadb-server

        # Configure MYSQL
        # Do a manual mysql_secure_installation
        mysql --user=root --password=$PASSWORD_MYSQL_ROOT << EOF
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${PASSWORD_MYSQL_ROOT}');
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';

CREATE USER '${USER_SUDO}'@'localhost' IDENTIFIED BY '${PASSWORD_MYSQL_SUDO}';
GRANT ALL PRIVILEGES ON *.* TO '${USER_SUDO}'@'localhost' WITH GRANT OPTION;

FLUSH PRIVILEGES;
EOF
        # Set mysql time zone so it matches php
        mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -u root mysql
        sed -i "/\[mysqld\]/a default_time_zone = Europe\/Paris" /etc/mysql/mariadb.conf.d/50-server.cnf

        # Install PHP7.1
        echo "${COLOUR_WHITE}>> installing PHP7.1...${COLOUR_RESTORE}"
        apt-get install -y php7.1 php7.1-fpm php7.1-cli php7.1-curl php7.1-common php7.1-mbstring php7.1-gd php7.1-intl php7.1-xml php7.1-mysql php7.1-mcrypt php7.1-zip php-imagick

        # Configure PHP.7.1
        # First backup original php.ini file
        cp /etc/php/7.1/fpm/php.ini /etc/php/7.1/fpm/php.ini.bak

        # Make changes to php.ini
        # These changes may be overwritten, so they're also included on a user level
        sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php/7.1/fpm/php.ini
        sed -i "s/memory_limit = .*/memory_limit = 256M/" /etc/php/7.1/fpm/php.ini
        sed -i "s/;date.timezone.*/date.timezone = Europe\/Paris/" /etc/php/7.1/fpm/php.ini
        sed -i "s/upload_max_filesize = .*/upload_max_filesize = 100M/" /etc/php/7.1/fpm/php.ini
        sed -i "s/post_max_size = .*/post_max_size = 100M/" /etc/php/7.1/fpm/php.ini
        sed -i "s/default_socket_timeout = .*/default_socket_timeout = 120/" /etc/php/7.1/fpm/php.ini
        sed -i "s/;session.cookie_secure =/session.cookie_secure = 1/" /etc/php/7.1/fpm/php.ini
        sed -i "s/session.cookie_httponly =/session.cookie_httponly = 1/" /etc/php/7.1/fpm/php.ini
        sed -i 's#;session.save_path = "/var/lib/php/sessions"#session.save_path = "/var/lib/php/sessions"#' /etc/php/7.1/fpm/php.ini

        # Delete default www.conf file
        rm -rf /etc/php/7.1/fpm/pool.d/www.conf

        # Add php pools for default website and phpmyadmin
        if [ -f /etc/php/7.1/fpm/pool.d/phpmyadmin.conf ]; then
            echo "${COLOUR_CYAN}-- pool configuration for phpmyadmin already exists. Skipping...${COLOUR_RESTORE}"
        else
            cat > /etc/php/7.1/fpm/pool.d/phpmyadmin.conf << EOF
[phpmyadmin]
user = ${USER_SUDO}
group = ${USER_SUDO}
listen = /var/run/php/php7.1-fpm-phpmyadmin.sock
listen.owner = www-data
listen.group = www-data
php_admin_value[disable_functions] = exec,passthru,shell_exec,system
pm = ondemand
pm.max_children = 20
pm.process_idle_timeout = 10s
pm.max_requests = 200
chdir = /
php_value[date.timezone] = ${YAM_DATEFORMAT_TIMEZONE}
php_value[cgi.fix_pathinfo] = 0
php_value[memory_limit] = 256M
php_value[upload_max_filesize] = 100M
php_value[default_socket_timeout] = 120
php_value[session.cookie_secure] = 1
php_value[session.cookie_httponly] = 1

EOF
        fi

        systemctl restart php7.1-fpm

        # Installing phpMyAdmin
        echo "${COLOUR_WHITE}>> Installing phpMyAdmin...${COLOUR_RESTORE}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get -y install phpmyadmin

        # Configuring phpMyAdmin
        touch /home/${USER_SUDO}/logs/nginx/phpmyadmin_error.log
        mkdir -p /home/${USER_SUDO}/public/phpmyadmin

        # Stop phpmyadmin from being backedup
        touch /home/${USER_SUDO}/public/phpmyadmin/.nobackup

        # Set permissions on phpmyadmin folders to prevent errors
        chown -R ${USER_SUDO}:${USER_SUDO} /var/lib/phpmyadmin
        chown -R ${USER_SUDO}:${USER_SUDO} /etc/phpmyadmin
        chown -R ${USER_SUDO}:${USER_SUDO} /usr/share/phpmyadmin

        # Password protect phpmyadmin directory
        htpasswd -b -c /home/${USER_SUDO}/.htpasswd phpmyadmin ${YAM_PASSWORD_GENERIC}

        # Add user folder and create a system link to the public folder
        chown root:root /home/${USER_SUDO}
        chown -R ${USER_SUDO}:${USER_SUDO} /home/${USER_SUDO}/public
        chmod -R 755 /home/${USER_SUDO}
        chmod -R 755 /home/${USER_SUDO}/public
        sudo ln -s /usr/share/phpmyadmin /home/${USER_SUDO}/public/phpmyadmin

        # Install firewall
        echo "${COLOUR_WHITE}>> Installing firewall...${COLOUR_RESTORE}"
        apt-get install -y fail2ban

        cat > /etc/fail2ban/action.d/ufw.conf << EOF
[Definition]
actionstart =
actionstop =
actioncheck =
actionban = ufw insert 1 deny from <ip> to any
actionunban = ufw delete deny from <ip> to any
EOF
        cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
banaction = ufw
bantime = 86400
findtime = 3600
maxretry = 3

[ssh]
enabled = true
port = ssh
filter = sshd
action = ufw
logpath = /var/log/auth.log
maxretry = 3

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
action = ufw
EOF
        fail2ban-client reload

        ufw allow OpenSSH
        ufw --force enable

        echo "${COLOUR_WHITE}>> Setting up backup${COLOUR_RESTORE}"
        # Adding log files
        touch /var/log/cron.log

        cat > /etc/cron.d/backup_server_local << EOF
30 2    * * *   root    /usr/local/bin/yam_backup_system.sh >> /var/log/cron.log 2>&1

EOF
        cat > /etc/cron.d/backup_server_s3_nginx << EOF
30 3    * * *   root    /usr/local/bin/yam_sync_s3.sh /var/backups/nginx/ /servers/backups/${YAM_SERVER_NAME}/var/backups/nginx/ >> /var/log/cron.log 2>&1

EOF

        cat > /etc/cron.d/backup_server_s3_letsencrypt << EOF
30 3    * * *   root    /usr/local/bin/yam_sync_s3.sh /var/backups/letsencrypt/ /servers/backups/${YAM_SERVER_NAME}/var/backups/letsencrypt/ >> /var/log/cron.log 2>&1

EOF

        cat > /etc/cron.d/backup_server_s3_mysql << EOF
30 3    * * *   root    /usr/local/bin/yam_sync_s3.sh /var/backups/mysql/ /servers/backups/${YAM_SERVER_NAME}/var/backups/mysql/ >> /var/log/cron.log 2>&1

EOF

        cat > /etc/cron.d/backup_server_s3_ssh << EOF
30 3    * * *   root    /usr/local/bin/yam_sync_s3.sh /var/backups/ssh/ /servers/backups/${YAM_SERVER_NAME}/var/backups/ssh/ >> /var/log/cron.log 2>&1

EOF

        cat > /etc/cron.d/backup_server_s3_cron << EOF
30 3    * * *   root    /usr/local/bin/yam_sync_s3.sh /var/backups/cron/ /servers/backups/${YAM_SERVER_NAME}/var/backups/cron/ >> /var/log/cron.log 2>&1

EOF

        cat > /etc/cron.d/backup_local_${USER_SUDO} << EOF
30 2    * * *   root    /usr/local/bin/yam_backup_local.sh ${USER_SUDO} >> /var/log/cron.log 2>&1

EOF

        cat > /etc/cron.d/backup_s3_${USER_SUDO} << EOF
* 3    * * *   root    /usr/local/bin/yam_backup_s3.sh ${USER_SUDO} ${YAM_SERVER_NAME} >> /var/log/cron.log 2>&1

EOF

        echo "${COLOUR_WHITE}Setup complete.${COLOUR_RESTORE}"

    else
        break
    fi
}

# Display menu

echo ''
echo ' .----------------.  .----------------.  .----------------.'
echo '| .--------------. || .--------------. || .--------------. |'
echo '| |  ____  ____  | || |      __      | || | ____    ____ | |'
echo '| | |_  _||_  _| | || |     /  \     | || ||_   \  /   _|| |'
echo '| |   \ \  / /   | || |    / /\ \    | || |  |   \/   |  | |'
echo '| |    \ \/ /    | || |   / ____ \   | || |  | |\  /| |  | |'
echo '| |    _|  |_    | || | _/ /    \ \_ | || | _| |_\/_| |_ | |'
echo '| |   |______|   | || ||____|  |____|| || ||_____||_____|| |'
echo '| |              | || |              | || |              | |'
echo '| .--------------. || .--------------. || .--------------. |'
echo ' .----------------.  .----------------.  .----------------. '
echo ''
echo 'YAM_SETUP.SH'


echo ''
echo 'What can I help you with today?'
echo ''
options=(
    "Setup a fresh Ubuntu server"
    "Quit"
)

select option in "${options[@]}"; do
    case "$REPLY" in
        1) setupServer ;;
        2) break ;;
    esac
done
