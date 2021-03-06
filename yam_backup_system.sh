#!/bin/bash

#+----------------------------------------------------------------------------+
#+ YAM Backup System
#+----------------------------------------------------------------------------+
#+ Author:      Jon Leverrier (jon@youandme.digital)
#+ Copyright:   2018 You & Me Digital SARL
#+ GitHub:      https://github.com/jonleverrier/yam-server-configurator
#+ Issues:      https://github.com/jonleverrier/yam-server-configurator/issues
#+ License:     GPL v3.0
#+ OS:          Ubuntu 16.0.4, 18.04
#+ Release:     1.1.0
#+----------------------------------------------------------------------------+

# To be used with cron, or run manually from the command line.

# Example usage;
# /bin/bash yam_backup_system.sh

# DEFAULT VARIABLES
YAM_DATEFORMAT_FULL=`date '+%Y-%m-%d'`
YAM_BACKUP_DURATION='+6'

# COLOURS
COLOUR_RESTORE=$(echo -en '\033[0m')
COLOUR_CYAN=$(echo -en '\033[00;36m')
COLOUR_WHITE=$(echo -en '\033[01;37m')

echo "------------------------------------------------------------------------"
echo "Starting backup process for system"
echo "------------------------------------------------------------------------"
echo ""

echo `date +"%Y-%m-%d %T"`
# if backup folder exists skip, else add folder
if [ -d "/var/backups/nginx" ]; then
    echo "System - Backup folder already exists for /var/backups/nginx"
else
    # make backup dir for user
    mkdir -p /var/backups/nginx
fi

# if backup folder exists skip, else add folder
if [ -d "/var/backups/letsencrypt" ]; then
    echo "System - Backup folder already exists for /var/backups/letsencrypt"
else
    # make backup dir for user
    mkdir -p /var/backups/letsencrypt
fi

# if backup folder exists skip, else add folder
if [ -d "/var/backups/mysql" ]; then
    echo "System - Backup folder already exists for /var/backups/mysql"
else
    # make backup dir for user
    mkdir -p /var/backups/mysql
fi

# if backup folder exists skip, else add folder
if [ -d "/var/backups/ssh" ]; then
    echo "System - Backup folder already exists for /var/backups/ssh"
else
    # make backup dir for user
    mkdir -p /var/backups/ssh
fi

# if backup folder exists skip, else add folder
if [ -d "/var/backups/cron" ]; then
    echo "System - Backup folder already exists for /var/backups/cron"
else
    # make backup dir for user
    mkdir -p /var/backups/cron
fi

# tar nginx folder...
echo ""
echo `date +"%Y-%m-%d %T"`
echo "${COLOUR_CYAN}System - Compressing nginx conf folder ${COLOUR_RESTORE}"
tar -czf /var/backups/nginx/nginxconf-${YAM_DATEFORMAT_FULL}.tar.gz /etc/nginx

# tar letsencrypt folder...
echo ""
echo `date +"%Y-%m-%d %T"`
echo "${COLOUR_CYAN}System - Compressing letsencrypt folder ${COLOUR_RESTORE}"
tar -czf /var/backups/letsencrypt/letsencrypt-${YAM_DATEFORMAT_FULL}.tar.gz /etc/letsencrypt

# tar mysql folder...
echo ""
echo `date +"%Y-%m-%d %T"`
echo "${COLOUR_CYAN}System - Compressing mysql folder ${COLOUR_RESTORE}"
tar -czf /var/backups/mysql/mysql-${YAM_DATEFORMAT_FULL}.tar.gz /var/lib/mysql

# tar ssh folder...
echo ""
echo `date +"%Y-%m-%d %T"`
echo "${COLOUR_CYAN}System - Compressing ssh folder ${COLOUR_RESTORE}"
tar -czf /var/backups/ssh/ssh-${YAM_DATEFORMAT_FULL}.tar.gz /etc/ssh

# tar ssh folder...
echo ""
echo `date +"%Y-%m-%d %T"`
echo "${COLOUR_CYAN}System - Compressing cron folder ${COLOUR_RESTORE}"
tar -czf /var/backups/cron/cron-${YAM_DATEFORMAT_FULL}.tar.gz /etc/cron.d

# delete old backups...
echo ""
echo `date +"%Y-%m-%d %T"`
echo "${COLOUR_CYAN}System - Checking for old backups to delete ${COLOUR_RESTORE}"
if [ -d "/var/backups/nginx/" ]; then
    find /var/backups/nginx/* -daystart -mtime ${YAM_BACKUP_DURATION} -exec rm {} \;
fi

if [ -d "/var/backups/letsencrypt/" ]; then
    find /var/backups/letsencrypt/* -daystart -mtime ${YAM_BACKUP_DURATION} -exec rm {} \;
fi

if [ -d "/var/backups/mysql/" ]; then
    find /var/backups/mysql/* -daystart -mtime ${YAM_BACKUP_DURATION} -exec rm {} \;
fi

if [ -d "/var/backups/ssh/" ]; then
    find /var/backups/ssh/* -daystart -mtime ${YAM_BACKUP_DURATION} -exec rm {} \;
fi

if [ -d "/var/backups/cron/" ]; then
    find /var/backups/cron/* -daystart -mtime ${YAM_BACKUP_DURATION} -exec rm {} \;
fi

echo "${COLOUR_WHITE}System backup complete. ${COLOUR_RESTORE}"
