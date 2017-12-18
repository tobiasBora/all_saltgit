#!/usr/bin/env bash
set -e

# This script is useful to automatically bootstrap a server.  You will
# need to confirm at each step if you want to run the givent action or
# not.

NOSSH=false
PROMPT=true
while getopts sy option
do
 case "${option}"
 in
     s) NOSSH=true;;
     y) PROMPT=false;;
 esac
done

# ======================================
# === Connecting to the server if needed
# ======================================
if [ "$NOSSH" = false ] ; then
    echo "Welcome in the bootstrap_saltgit_server script !"
    echo "This script is useful to bootstrap any server."
    echo "It will install if needed salt, and configure it"
    echo "by creating an empty repository (and the associated"
    echo "hook files) so that you can push to it your configuration."
    echo "The installation will be guided, and you will be prompted"
    echo "to confirm all major steps. Use the 'y' option if you want"
    echo "to use the default options when available."
    echo ""
    echo "Are you right now on the server ?[y/N] "
    read -r -p "(If you answer 'N', the script will use ssh to run it on the server)" response
    case "$response" in
	[yY][eE][sS]|[yY])
            echo "All right, then let's install it locally!"
            ;;
	*)
            echo "Nice, then please give me the ssh string to use to connect"
	    echo "to the server."
	    echo "E.g: myuser@myserver.com"
	    echo "NB: the user must be root, or be able to use 'sudo'"
	    read -r -p "sshstring > " serverstring
	    serveraddr=$(echo "${serverstring}" | grep -o '.*@.*' | sed 's/^.*@\(.*\)/\1/')
	    if [[ "$serveraddr" == "" ]] ; then
		echo "I was not able to find the url/ip of the server"
		echo "Could you please provide it to me?"
		read -r -p "hostname > " serveraddr
		echo "Server url: ${serveraddr}"
	    fi
	    echo "Please, provide the port (use '22' if you don't know):"
	    read -r -p "port > " port
	    echo "The file will be copied and run on the server. Please note"
	    echo "that you may need to type your password twice."
	    scp -P "${port}" "./bootstrap_saltgit_server.sh" "${serverstring}:/tmp"
	    echo "Now I will run the script on the server side..."
	    ssh -t -p "${port}" "${serverstring}" port="${port}" serverstring="${serverstring}" serveraddr="${serveraddr}" '/tmp/bootstrap_saltgit_server.sh -s'
	    exit $?
            ;;
    esac
fi

if [[ $UID -eq 0 ]] ; then
    SUDO=""
else
    SUDO="sudo"
fi

cd /tmp

echo "Great, now let's proceed to the installation."

# ==============================
# === Installing rsync, ca-certificates and sudo
# ==============================
# Trying to detect the package manager
declare -A osInfo;
osInfo[/etc/redhat-release]="yum install"
osInfo[/etc/arch-release]="pacman -S"
osInfo[/etc/gentoo-release]="emerge"
osInfo[/etc/SuSE-release]="zypper install"
osInfo[/etc/debian_version]="apt-get install"
packageManager="apt-get install"
for f in ${!osInfo[@]}
do
    if [[ -f $f ]];then
        packageManager="${osInfo[$f]}"
    fi
done

echo "Do you want to install 'rsync', 'ca-certificates' and 'sudo' using the following command:"
echo "# $SUDO ${packageManager} rsync ca-certificates sudo"
read -r -p "? [Y/n] " response
case "$response" in
    [nN][oO]|[nN])
	echo "Continuing without installing rsync."
        ;;
    *)
        echo "Let's install rsync!"
	$SUDO $packageManager rsync ca-certificates sudo
        ;;
esac

# ==============================
# === Installing rsync, ca-certificates and sudo
# ==============================

echo "Do you want to install salt (master & client) using the following command:"
echo "# wget -O bootstrap-salt.sh https://bootstrap.saltstack.com"
echo "# sh bootstrap-salt.sh -M"
read -r -p "Install? [Y/n] " response
case "$response" in
    [nN][oO]|[nN])
	echo "Continuing without installation."
        ;;
    *)
        echo "Let's install salt!"
	wget -O bootstrap-salt.sh https://bootstrap.saltstack.com
	$SUDO sh bootstrap-salt.sh -M
        ;;
esac

# ==============================
# === Configuring master
# ==============================
read -r -p "Do you want to configure the master? [Y/n] " response
case "$response" in
    [nN][oO]|[nN])
	echo "As you want, but make sure that the /etc/salt/master.d/*.conf"
	echo "files are enabled in the configuration."
        ;;
    *)
	echo "Now, I'll configure the master by enabling the *.conf files..."
	if [[ -f /etc/salt/master ]]; then
	    $SUDO sed -i 's@^#default_include: master.d/\*.conf$@default_include: master.d/\*.conf@' /etc/salt/master
	    if ! grep -o '^default_include: master.d/\*.conf' /etc/salt/master ; then
		echo "default_include: master.d/*.conf" | $SUDO tee -a /etc/salt/master
	    fi
	    echo "Done."
	else
	    echo "default_include: master.d/*.conf" | $SUDO tee -a /etc/salt/master
	    echo "Done, but something weird happened: the file /etc/salt/master"
	    echo "didn't exists..."
	    echo "Please make sure that you installed the salt master correctly."
	fi
	;;
esac

# ==============================
# === Configuring the minion
# ==============================
echo "I will now configure the minion to point to the master"
echo "by adding 'master: localhost' in the file /etc/salt/minion."
read -r -p "Are you ok? [Y/n] " response
case "$response" in
    [nN][oO]|[nN])
        echo "As you wish, but make sure that the minion is connected to"
	echo "the master."
        ;;
    *)
	if [[ -f /etc/salt/minion ]]; then
	    $SUDO sed -i 's/^#master:.*$/master: localhost/' /etc/salt/minion
	    if ! grep -o '^master: localhost' /etc/salt/minion ; then
		echo 'master: localhost' | $SUDO tee -a /etc/salt/minion
	    fi
	    echo "Done."
	else
	    echo 'master: localhost' | $SUDO tee -a /etc/salt/minion
	fi
        ;;
esac


# ===========================================
# === Minion ID
# ===========================================
read -r -p "Do you want to set the minion ID ? [y/N] " response
case "$response" in
    [yY][eE][sS]|[yY])
	read -r -p "Then could you please give me the new id? " newid
	if [[ -f /etc/salt/minion ]]; then
	    $SUDO sed -i "s/^\(#\|\)id:.*/id: ${newid}/" /etc/salt/minion
	    if ! grep -o "^id: ${newid}" /etc/salt/minion ; then
		echo "id: ${newid}" | $SUDO tee -a /etc/salt/minion
	    fi
	else
	    echo "id: ${newid}" | $SUDO tee -a /etc/salt/minion
	fi
	echo "Done."
        ;;
    *)
	echo "Ok, I'll keep the default ID then!"
        ;;
esac



# ===================================
# === Starting the master and minion
# ===================================
echo "I'll now enable and start the minion and master by running"
echo "# systemctl enable salt-master"
echo "# systemctl restart salt-master"
echo "# systemctl enable salt-minion"
echo "# systemctl restart salt-minion"
read -r -p "Are you ok? [Y/n] " response
case "$response" in
    [nN][oO]|[nN])
        echo "As you wish, but make sure that to run the minion and the master"
        ;;
    *)
	$SUDO systemctl enable salt-master
	$SUDO systemctl restart salt-master
	$SUDO systemctl enable salt-minion
	$SUDO systemctl restart salt-minion
	echo "Done."
	;;
esac

# ===========================================
# === Exchanging keys
# ===========================================
echo "Here are keys available to the server:"
$SUDO salt-key -L
echo "(if no key is visible, then wait around 10s and continue)"
read -r -p "Would you like to accept all these keys with 'salt-key -L'? [Y/n] " response
case "$response" in
    [nN][oO]|[nN])
	echo "As you wish, but make sure that the server accepted the minion keys."
        ;;
    *)
	echo "I'll accept the following keys:"
	$SUDO salt-key -L
	echo ""
	$SUDO salt-key -A
	echo "Here is the new state:"
	$SUDO salt-key -L
	echo "If you don't see the minion id here, then a problem occured."
	echo "Try to fix it before continuing, by making sure that "
	echo "# salt-key -L"
	echo "returns the good ids."
        ;;
esac


# ===========================================
# === Creating git user
# ===========================================
echo "What is the name of the user that will own the git repo?"
echo "(this user may not exist)"
read -r -p "(Default: git): " gituser
if [[ "$gituser" == "" ]] ; then
    gituser="git"
fi

if ! id -u "$gituser" > /dev/null 2>&1 ; then
    echo "This user does not exist."
    echo "I can create it for you with the command:"
    echo "# useradd --home-dir '/home/${gituser}' -m ${gituser}"
    read -r -p "Do you want to create the user ${gituser}? [Y/n] " response
    case "$response" in
	[nN][oO]|[nN])
            echo "As you with, then make sure you create this user before the next now."
            ;;
	*)
	    $SUDO useradd --home-dir "/home/${gituser}" -m "${gituser}"
	    read -r -p "Do you want to add a public key for this user? [y/N] " reppub
	    case "$reppub" in
		[yY][eE][sS]|[yY])
		    echo "To get your public key, run on the client side:"
		    echo "$ cat ~/.ssh/id_rsa.pub"
		    echo "and copy the whole output."
		    read -r -p "Please provide the whole content of your public key: " pubkey
		    $SUDO install -d -o "${gituser}" -g "${gituser}" -m "700" "/home/${gituser}/.ssh"
		    $SUDO bash -c "echo '${pubkey}' >> '/home/${gituser}/.ssh/authorized_keys'"
		    $SUDO chown "${gituser}:${gituser}" "/home/${gituser}/.ssh/authorized_keys"
		    $SUDO chmod 644 "/home/${gituser}/.ssh/authorized_keys"
		    echo "Key installed!"
		    echo "To use it, please add in your local ~/.ssh/config the following content and change the hostname:"
		    echo "#########################################"
		    echo "# You can change the host name if needed"
		    echo "Host ${gituser}@${serveraddr}:${port}"
		    echo "     User ${gituser}"
		    echo "     Hostname ${serveraddr}"
		    echo "     Port ${port}"
		    echo "     PreferredAuthentications publickey"
		    echo "     IdentityFile ~/.ssh/id_rsa"
		    echo ""
		    echo "#########################################"
		    ;;
	    esac
	    read -r -p "Do you want to add a password to the user (facultative if you already provided a public key)? [y/N] " reppass
	    case "$reppass" in
		[yY][eE][sS]|[yY])
		    echo "Please give the password of the user ${gituser}:"
		    $SUDO passwd "${gituser}"
		    ;;
	    esac
    esac
fi

# ===========================================
# === Creating the git repo
# ===========================================

echo "What is the path to the wanted git repo?"
read -r -p "(Default: /home/${gituser}/salt/salt_config.git) >" pathgitrepo
if [[ "$pathgitrepo" == "" ]] ; then
    pathgitrepo="/home/${gituser}/salt/salt_config.git"
fi
if [[ -e "$pathgitrepo" ]] ; then
    echo "The git repo '$pathgitrepo' already exists..."
else
    echo "Creating the bare repo at ${pathgitrepo}..."
    $SUDO su ${gituser} -c "git init --bare ${pathgitrepo}"
fi
$SUDO su ${gituser} -c "touch \"${pathgitrepo}/hooks/post-receive\" && chmod +x \"${pathgitrepo}/hooks/post-receive\""

echo '#!/usr/bin/env bash' | $SUDO tee "${pathgitrepo}/hooks/post-receive"
echo 'sudo /opt/git_hook/update_salt_folder.sh' | $SUDO tee -a "${pathgitrepo}/hooks/post-receive"


# ===========================================
# === Creating the hook script
# ===========================================

echo "Creating the script to run to update the salt configuration"
echo "in /opt/git_hook/update_salt_folder.sh"
read -r -p "Press Enter to continue." response
$SUDO mkdir -p /opt/git_hook/
tmpfile=$(mktemp)
cat >"$tmpfile" <<EOL
#!/usr/bin/env bash
set -e

cd ${pathgitrepo}
EOL

cat >>"$tmpfile" <<'EOL'
tempdir=$(mktemp -d --tmpdir salt-XXXXXXXXXX)
git archive master | tar -C "$tempdir" -xf -
if [ -e "$tempdir/srv/" ]; then
    for subfolder in "$tempdir/srv/"*; do
        rsync -r --delete-after --no-p --chown=root:root --chmod=Du=rwx,Dgo=,Fu=rw,Fog= "$tempdir/srv/" /srv/
    done
fi
if [ -e "$tempdir/etc_salt_master.d/" ]; then
    rsync -r --delete-after --no-p --chown=root:root --chmod=Du=rwx,Dgo=rx,Fu=rw,Fog=rx "$tempdir/etc_salt_master.d/" /etc/salt/master.d/
fi
rm -rf "$tempdir"
EOL

$SUDO mkdir -p "/opt/git_hook/"
$SUDO mv "$tmpfile" "/opt/git_hook/update_salt_folder.sh"
$SUDO chmod 755 "/opt/git_hook/update_salt_folder.sh"
$SUDO chown root:root "/opt/git_hook/update_salt_folder.sh"

echo "The script /opt/git_hook/update_salt_folder.sh needs to be run as root."
echo "That's why we need to allow user ${gituser} to run this script as root."
read -r -p "Do you want to let me edit 'visudo' for you?[Y/n] " response
case "$response" in
    [nN][oO]|[nN])
        echo "As you wish, but make sure that the file"
	echo "/opt/git_hook/update_salt_folder.sh"
	echo "can be run by the user ${gituser} will root access."
	echo "You can do it by running 'visudo' and add at the end:"
	echo "${gituser} ALL = (root) NOPASSWD: /opt/git_hook/update_salt_folder.sh"
        ;;
    *)
	echo "${gituser} ALL = (root) NOPASSWD: /opt/git_hook/update_salt_folder.sh" | $SUDO EDITOR='tee -a' visudo
        ;;
esac

echo ""
echo ""
echo "##################################################"
echo "############### Congratulation !!! ###############"
echo "##################################################"
echo "Now to synchronize your salt files with the git repository, you just"
echo "need to create a git repo with the following folders:"
echo " - 'srv/' (and often 'srv/salt/'): all the folders inside will be"
echo "     put inside '/srv/'"
echo " - 'etc_salt_master.d': all the files inside will be put inside"
echo "     '/etc/salt/master.d/"
echo "(Or you can use the current git repository)"
echo ""
echo "Then, to push your modifications, you just need to push them to the"
echo "git repository '${gituser}@${serveraddr}:${pathgitrepo}' at port ${port}"
echo ""
echo "The first time, you will need to add the remote server to"
echo "your local git repo:"
echo "  $ git remote add saltserver ssh://${gituser}@${serveraddr}:${port}${pathgitrepo}"
echo ""
echo "And to push the first time the master branch the the saltserver remote:"
echo "  $ git push --set-upstream saltserver master"
echo ""
echo "Then, just connect to the server and run the usual code to apply the changes:"
echo "  $ salt '*' state.apply"
echo ""
echo "Enjoy !"
echo ""
echo "NB: if you want, you can edit on the server the file"
echo "    /opt/git_hook/update_salt_folder.sh"
echo "    to run the state.apply code automatically when you push."
