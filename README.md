# yam-server-configurator
Setup an Ubutnu 16.04.4 x64 VPS from Digital Ocean. Host and manage multiple MODX websites running on a LEMP stack.

Designed to be used on a fresh server with nothing else installed apart from Ubutnu.

## yam_setup.sh

To run the setup script, you will need to login to your server as the root user via SSH. Once you're logged in, type the following into the command line:

```
cd /usr/local/bin
wget -N https://raw.githubusercontent.com/jonleverrier/yam-server-configurator/master/yam_setup.sh
```

At this point you will want to customise the variables at the top of the script before running it. Type the following into the command line to edit the script:
```
nano /usr/local/bin/yam_setup.sh
```

Then once you are done, type the following command to load the script:
```
/bin/bash yam_setup.sh
```
You will then be prompted to choose from the following options:
1. Setup a fresh Ubuntu server
2. Quit

If you choose to setup a fresh server, the script will installs and configure NGINX, MariaDB, PHP7.1 FPM, Certbot (Let's Encrypt), PhpMyAdmin, Fail2Ban with UFW, php-imagick, htop, zip, unzip, Digital Ocean agent, s3cmd, nmap and additional YAM scripts.

The script also configures root and sudo users, time zone for server and mysql, skeleton directory, log rotation, ssl auto renewal, UFW, default error pages, local backup of core system folders, local backup of user web folders, S3 backup of core system folders, sessions, securing MODX and S3 backup of user web folders.

## yam_secure.sh

When you are finished with setup, you can logout and login as your new sudo user. To run the script, you will need to `su` before running it. Type the following to load the script:

```
/bin/bash yam_secure.sh
```
You will then be prompted to choose from the following options:
1. Setup sudo user
2. Disable password login
3. Enable password login
4. Disable root login
5. Enable root login
6. Quit

## yam_manage.sh

Like yam_setup.sh, customise the variables at the top of the yam_manage.sh script before running.

Once you're ready, type the following to load the script:

```
/bin/bash yam_manage.sh
```
You will then be prompted to choose from the following options:
1. Inject a MODX website from an external source
2. Package MODX website for injection
3. Add new development website
4. Add new development website with Basesite
5. Copy development website
6. Map domain to website
7. Add user to password directory
8. Toggle password directory
9. Delete user
10. Delete website

## Utility Scripts

Make sure you check these files for variables that may need customising.

Whilst yam_setup.sh installs Amazon s3cmd, you'll have to run s3cmd setup yourself before using the utility scripts. It's very quick todo, hence not adding it to the build script.

### yam_backup_local.sh

To be used with cron, or run manually from the command line.

Example usage; backup websites that live in /home/jamesbond/:
```
/bin/bash yam_backup_local.sh jamesbond
```

This scripts presumes yam_setup.sh setup your server. Therefore your user directory is organised like the following;
```
/home/user/public/website1
/home/user/public/website2
/home/user/public/website3
```

### yam_backup_s3.sh

Example usage:
```
/bin/bash yam_backup_s3.sh user s3_server_folder_name
```
There is also a global variable `PATH_BACKUP` that can be edited to build any
S3 URL.

### yam_backup_system.sh

To be used with cron, or run manually from the command line.

Example usage;
```
/bin/bash yam_backup_system.sh
```

### yam_sync_s3.sh
Example usage:
```
/bin/bash yam_sync_s3.sh /local/path/ /s3/path/
```
