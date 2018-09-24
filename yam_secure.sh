#!/bin/bash

#+----------------------------------------------------------------------------+
#+ YAM Server Secure
#+----------------------------------------------------------------------------+
#+ Author:      Jon Leverrier (jon@youandme.digital)
#+ Copyright:   2018 You & Me Digital SARL
#+ GitHub:      https://github.com/jonleverrier/yam-server-configurator
#+ Issues:      https://github.com/jonleverrier/yam-server-configurator/issues
#+ License:     GPL v3.0
#+ OS:          Ubuntu 16.0.4, 18.04
#+ Release:     1.0.0
#+----------------------------------------------------------------------------+

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

# Load secure server function
secureServer() {
    if ask "Are you sure you want to setup root and sudo user with keys?"; then
        read -p "Enter a sudo user  : " USER_SUDO
        read -s -p "Enter a sudo password  : " USER_SUDO_PASSWORD
        echo
        read -p "Paste SSH Keys  : " KEY_SSH_PUBLIC
        echo '------------------------------------------------------------------------'
        echo 'Securing server'
        echo '------------------------------------------------------------------------'

        # Check to see if whois is installed on the server
        echo "${COLOUR_WHITE}>> checking to see if package whois is installed...${COLOUR_RESTORE}"
        if [ $(dpkg-query -W -f='${Status}' whois 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
            apt-get install -y whois;
        else
            echo "Done. The whois package is already installed."
        fi

        # Setting up new sudo user
        echo "${COLOUR_WHITE}>> setting up new sudo user and password for user ${USER_SUDO}...${COLOUR_RESTORE}"

        if id "$USER_SUDO" >/dev/null 2>&1; then
              echo "The user already exists. Skipping..."
        else
            # Setting up skeleton directory
            # if the user has setup a server first, the skeleton directory
            # will be setup. if a user runs the secureServer function first,
            # the skeleton directory wont be setup. check to see if it exists
            # or not...
            if [ -d "/etc/skel/logs" ]; then
                echo "skeleton directory already setup. skipping..."
            else
                mkdir -p /etc/skel/tmp
                mkdir -p /etc/skel/logs
                mkdir -p /etc/skel/logs/nginx
                mkdir -p /etc/skel/public
            fi

            # Create new user including home directory
            adduser --disabled-password --gecos "" ${USER_SUDO}
            # Add user to sudo user group
            usermod -aG sudo ${USER_SUDO}
            # Generate and set password
            PASSWORD=$(mkpasswd ${USER_SUDO_PASSWORD})
            usermod --password ${PASSWORD} ${USER_SUDO}
        fi

        # Adds sudo user to sudoers file to stop password prompt
        echo "${COLOUR_WHITE}>> adding user ${USER_SUDO} to sudoers file...${COLOUR_RESTORE}"
        if [ -d "/etc/sudoers.d/${USER_SUDO}" ]; then
            echo "user already added to sudoers file. skipping..."
        else
            cat > /etc/sudoers.d/${USER_SUDO} << EOF
# Generated by the YAM server configurator
# Do not edit as you may loose your changes
# If you have found a bug, please email ${YAM_EMAIL_BUG}

# User rules for ${USER_SUDO}
${USER_SUDO} ALL=(ALL) NOPASSWD:ALL
EOF
        echo "Done."
        fi

        # Setup Bash For User
        echo "${COLOUR_WHITE}>> setting up bash for user ${USER_SUDO}...${COLOUR_RESTORE}"
        chsh -s /bin/bash ${USER_SUDO}
        echo "Done."

        # disable bash history
        echo 'set +o history' >> ~/.bashrc

        # Add keys to root and user folders
        echo "${COLOUR_WHITE}>> setting up keys for user root and ${USER_SUDO}...${COLOUR_RESTORE}"
        cat > /root/.ssh/authorized_keys << EOF
$KEY_SSH_PUBLIC
EOF
        if [ -f "/home/$USER_SUDO/.ssh" ]; then
            echo "A .ssh folder already exists in the home folder for ${USER_SUDO}. Skipping..."
        else
            mkdir -p /home/${USER_SUDO}/.ssh
            cp /root/.ssh/authorized_keys /home/${USER_SUDO}/.ssh/authorized_keys
            echo "Done."

            # Create The Server SSH Key
            yes y |ssh-keygen -f /home/${USER_SUDO}/.ssh/id_rsa -q -t rsa -N '' >/dev/null
            chmod 700 /home/${USER_SUDO}/.ssh/id_rsa
            chmod 600 /home/${USER_SUDO}/.ssh/authorized_keys
        fi

        # Setup Site Directory Permissions
        echo "${COLOUR_WHITE}>> adjusting user permissions...${COLOUR_RESTORE}"
        chown -R ${USER_SUDO}:${USER_SUDO} /home/${USER_SUDO}
        chmod -R 755 /home/${USER_SUDO}
        chown root:root /home/${USER_SUDO}
        echo "Done."



    else
        break
    fi
}

# Load disable SSH password function
securePasswordsAllDisable () {
    if ask "Are you sure you want to disable SSH password authentication?"; then
        echo "${COLOUR_WHITE}>> removing SSH password authentication...${COLOUR_RESTORE}"
        sed -i "s/PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config
        sed -i "s/PubkeyAuthentication no/PubkeyAuthentication yes/" /etc/ssh/sshd_config
        sed -i "s/ChallengeResponseAuthentication yes/ChallengeResponseAuthentication no/" /etc/ssh/sshd_config
        ssh-keygen -A
        service ssh restart
        echo "Done."
    else
        break
    fi
}

# Load enable SSH password function
securePasswordsAllEnable () {
    if ask "Are you sure you want to enable SSH password authentication?"; then
        echo "${COLOUR_WHITE}>> enabling SSH password authentication...${COLOUR_RESTORE}"
        sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config
        sed -i "s/PubkeyAuthentication yes/PubkeyAuthentication no/" /etc/ssh/sshd_config
        sed -i "s/ChallengeResponseAuthentication no/ChallengeResponseAuthentication yes/" /etc/ssh/sshd_config
        ssh-keygen -A
        service ssh restart
        echo "Done."
    else
        break
    fi
}

# Load enable root login
securePasswordsRootEnable () {
    if ask "Are you sure you want to enable root login?"; then
        echo "${COLOUR_WHITE}>> enabling SSH root password authentication...${COLOUR_RESTORE}"
        sed -i "s/PermitRootLogin no/PermitRootLogin yes/" /etc/ssh/sshd_config
        ssh-keygen -A
        service ssh restart
        echo "Done."
    else
        break
    fi
}

# Load disable root login
securePasswordsRootDisable () {
    if ask "Are you sure you want to disable root login?"; then
        echo "${COLOUR_WHITE}>> removing SSH root password authentication...${COLOUR_RESTORE}"
        sed -i "s/PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
        ssh-keygen -A
        service ssh restart
        echo "Done."
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
echo 'YAM_SECURE.SH'


echo ''
echo 'What can I help you with today?'
echo ''
passwordOptions=(
    "Setup sudo and root user with keys"
    "Disable password login"
    "Enable password login"
    "Disable root login"
    "Enable root login"
    "Quit"
)
select option in "${passwordOptions[@]}"; do
    case "$REPLY" in
        1) secureServer ;;
        2) securePasswordsAllDisable ;;
        3) securePasswordsAllEnable ;;
        4) securePasswordsRootDisable ;;
        5) securePasswordsRootEnable ;;
        6) break ;;
    esac
done
