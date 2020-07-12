
#!/bin/sh

# Author: Gajesh Bhat
# Shell script to install developer tools Ubuntu and its derivatives.
# Please free to send hugs or bugs my way.
# Contact : www.gajeshbhat.com

function jumpto
{
    label=$1
    cmd=$(sed -n "/$label:/{:a;n;p;ba};" $0 | grep -v ':$')
    eval "$cmd"
    exit
}

function ChangeMirrorPack
{
#Change the server to main server for update
printf "Changing the Local Mirror Server to Main Server"
sudo sed -i 's|http://[a-z]..|http://|g' /etc/apt/sources.list
}

function RestrictedExtrasPack
{

#Enable Third Party Repos and Update the Repo List
printf "Enabling Third-Party Repos..."
DISTRO=`cat /etc/*-release | grep DISTRIB_CODENAME | sed 's/.*=//g'`
sudo sed -i.bak 's/\(# \)\(deb .*ubuntu '${DISTRO}' partner\)/\2/g' /etc/apt/sources.list
sudo apt-get -y update
sudo apt-get -y upgrade

if [[ $(pgrep kwin) != "" ]]; then   #Different set of packages are needed for KDE based systems
    echo "Installing Restricted Extras for KDE based system"
    sudo apt install -y lame unrar gstreamer1.0-fluendo-mp3 gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-fluendo-mp3 libdvdread4 libk3b6-extracodecs  oxideqt-codecs-extra libavcodec-extra libavcodec-ffmpeg-extra56 libk3b6-extracodecs
  else
    echo "Installing Restricted Extras"
    sudo apt install -y lame unrar gstreamer1.0-fluendo-mp3 gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-fluendo-mp3 libdvdread4 libk3b6-extracodecs  oxideqt-codecs-extra libavcodec-extra libavcodec-ffmpeg-extra56
fi
sudo apt-get -y install flashplugin-installer
sudo apt-get -y install ffmpeg


}

function ChromiumPack
{
sudo apt-get -y install chromium-browser
}

function SynapticPack
{
sudo apt-get -y install synaptic
}

function GdebiPack
{
sudo apt-get -y install gdebi
}

function BuildEssPack
{
sudo apt-get -y install build-essential
}

function CPack
{
sudo apt-get -y install clang
}

function QtPack
{
#Qt Creator 5.7 at the time this code was written. Please raise an issue if new latest stable version is out.
wget http://download.qt.io/official_releases/qt/5.7/5.7.0/qt-opensource-linux-x64-5.7.0.run

chmod +x qt-opensource-linux-x64-5.7.0.run

./qt-opensource-linux-x64-5.7.0.run --script GUI/auto-inst-qt.qs

#Install additions font and video library for Qt
sudo apt-get -y install libfontconfig1
sudo apt-get -y install mesa-common-dev
sudo apt-get -y install libglu1-mesa-dev
}

function JavaPack
{
#Install Java
sudo apt-get -y install default-jre
sudo apt-get -y install default-jdk
}

function GoPack
{
sudo apt-get -y update
sudo apt-get -y upgrade
wget https://storage.googleapis.com/golang/go1.10.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.10.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin:${HOME}/go/bin
source ~/.bashrc
}

function GroovyPack
{
#Install Groovy using SDKMAN
curl -s get.sdkman.io | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install groovy
groovy -version
}

function GitPack
{
sudo apt-get -y install git
}

function HaskellPack
{
#Install haskell
sudo apt-get -y install haskell-platform
}

function PythonPack
{
sudo apt-get -y install python3
sudo apt-get -y install python-pip
pip install --upgrade pip
}

function RubyPack
{
#Install Ruby Full from official repos. (Not from the Bleeding edges)
sudo apt-get -y install ruby-full
}

function DjangoPack
{
sudo pip install django
}

function CustomPip
{
sudo pip install -r packages/python_packages.txt
}

function RailsPack
{
#Installs rails
sudo apt-get -y install rails
}

function NodeJsPack
{
#Following code correctly sets up nodejs
sudo apt-get -y remove nodejs npm # remove existing nodejs and npm packages
sudo apt-get -y install curl
curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install npm@latest -g
}

function ElectronPack
{
NodeJsPack
sudo npm i -D electron@latest
}

function MySQLPack
{
Password=$1
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password password $Password'
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password $Password'
sudo apt-get -y install mysql-server
}

function MongoDBPack
{
sudo rm /etc/apt/sources.list.d/mongodb*.list
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv EA312927
sudo bash -c 'echo "deb http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.2 multiverse" > /etc/apt/sources.list.d/mongodb-org-3.2.list'
sudo apt-get -y update
sudo apt-get -y install mongodb-org
sudo service mongod start
}

function RedisPack
{
sudo apt-get -y install redis-server
}

function PostgresPack
{
sudo apt-get install -y postgresql-9.5 pgadmin3 postgresql-contrib-9.5 postgresql-server-dev-9.5 postgis postgresql-9.5-postgis-2.2 -y
}

function CouchDBPack
{
sudo add-apt-repository ppa:couchdb/stable -y
sudo apt-get -y update
sudo apt-get install couchdb -y
#Secure CouchDB by removing root permissions
sudo stop couchdb
sudo chown -R couchdb:couchdb /usr/lib/couchdb /usr/share/couchdb /etc/couchdb /usr/bin/couchdb
sudo chmod -R 0770 /usr/lib/couchdb /usr/share/couchdb /etc/couchdb /usr/bin/couchdb
sudo start couchdb
}

function SqlitePack
{
sudo apt-get install sqlite3 libsqlite3-dev
}

function MariaDBPack
{
sudo apt-get install software-properties-common
sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xF1656F24C74CD1D8 -y
sudo add-apt-repository 'deb [arch=amd64,i386,ppc64el] http://kartolo.sby.datautama.net.id/mariadb/repo/10.2/ubuntu xenial main' -y
sudo apt-get -y update
sudo apt-get -y install mariadb-server
}

function GeckodriverPack
{
#Install Geckodriver. (v0.18.0)
wget https://github.com/mozilla/geckodriver/releases/download/v0.18.0/geckodriver-v0.18.0-linux64.tar.gz
tar -xvzf geckodriver*
chmod +x geckodriver
sudo mv geckodriver /usr/local/bin/

}

function IntelliJPack
{
#Install IntelliJ
sudo apt-add-repository ppa:mmk2410/intellij-idea -y
sudo apt-get -y update
sudo apt-get -y install intellij-idea-ultimate
}

function AtomPack
{
#Install Atom Text Editor
sudo add-apt-repository ppa:webupd8team/atom -y
sudo apt-get -y update
sudo apt-get -y install atom
}

function BracketsPack
{
sudo add-apt-repository ppa:webupd8team/brackets -y
sudo apt-get -y update
sudo apt-get install -y brackets
}

function SublimeTextPack
{
wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | sudo apt-key add -
sudo apt-get -y install apt-transport-https
echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list
sudo apt-get -y update
sudo apt-get install -y sublime-text
}

function VSCodePack
{
#Install Visual Studio Code (Stable)
curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo mv microsoft.gpg /etc/apt/trusted.gpg.d/microsoft.gpg
sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list'
sudo apt-get -y update
sudo apt-get -y install code # or code-insiders
}

function VirtualBoxPack
{
#Virtual Box with guest editions
sudo apt-get -y install virtualbox
sudo apt-get -y install virtualbox-guest-dkms
}

function VimPack
{
#Vim install and dotfile Configuration (Dont forget to run :PlugInstall after installation) Vimrc configs from amix https://github.com/amix/vimrc
sudo apt-get -y install vim
sudo apt-get -y install curl
git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
}

function VimCustomDotPack
{
VimPack
git clone https://github.com/gajeshbhat/dotfiles.git
sudo cp dotfiles/.vimrc ~/.vimrc
}

function LateXPack
{
#Install Latex in full (Including Language Packages)
sudo apt-get -y install texlive-full
}

function HerokuToolBeltPack
{
#Heroku toolbelt Login and Setup Instruction info at : https://devcenter.heroku.com/articles/heroku-cli
wget -qO- https://cli-assets.heroku.com/install-ubuntu.sh | sh
}

function GpartedPack
{
#Gparted
sudo apt-get -y install gparted
}

function EtcherPack
{
echo "deb https://dl.bintray.com/resin-io/debian stable etcher" | sudo tee /etc/apt/sources.list.d/etcher.list
sudo apt-key adv --keyserver hkp://pgp.mit.edu:80 --recv-keys 379CE192D401AB61 -y
sudo apt-get -y update
sudo apt-get install etcher-electron
}

function AudacityPack
{
sudo apt-get -y install audacity
}

function KdenlivePack
{
sudo apt-add-repository ppa:kdenlive/kdenlive-stable && sudo apt-get -y update
sudo apt-get -y install kdenlive
}

function VocalAppPack
{
sudo flatpak install --from https://flathub.org/repo/appstream/com.github.needleandthread.vocal.flatpakref -y
}

: welcome_msg:
sudo whiptail --title "Welcome to Auto-Workspace(Dialog edition)" --textbox info/hello.txt 20 60 

: bs_tools:
Basic_tools=$(whiptail --title "Select Some Basic Tools" --checklist \
"Choose some basic applications that you want to install" 15 60 8 \
"ChangeMirrorPack" "Change Mirror to Main Server" OFF \
"RestrictedExtrasPack" "Restricted Extras" ON \
"ChromiumPack" "Chromium Browser" OFF \
"SynapticPack" "Synaptic Package Manager" OFF \
"GdebiPack" "Gdebi Package Installer" OFF 3>&1 1>&2 2>&3)
 
exitstatus=$?
if [ $exitstatus = 0 ]; then
    if [ -z $Basic_tools ]; then
    	whiptail --title "Tool Selection Error" --msgbox "Please select atleast one basic tool." 10 60
		jumpto bs_tools
	fi
else
    jumpto welcome_msg
fi

: lang_tools:
Language_tools=$(whiptail --title "Languages and Libs" --checklist --scrolltext \
"Choose programming languages and frameworks to install" 18 65 9 \
"BuildEssPack" "Build Essentials" ON \
"CPack" "GCC(C,C++)" OFF \
"JavaPack" "Java" OFF \
"GroovyPack" "Groovy" OFF \
"GoPack" "Go lang" OFF \
"RubyPack" "Ruby" OFF \
"PythonPack" "Python" OFF \
"NodeJsPack" "NodeJS" OFF \
"ElectronPack" "Electron" OFF \
"HaskellPack" "Haskell" OFF \
"GitPack" "Git" OFF \
"QtPack" "Qt 5.7" OFF \
"DjangoPack" "Django" OFF \
"CustomPip" "Custom Python Package Set" OFF \
"RailsPack" "Ruby on Rails" OFF 3>&1 1>&2 2>&3)
 
exitstatus=$?
if [ $exitstatus = 0 ]; then
    if [ -z $Language_tools ]; then
    	whiptail --title "Selection Error" --msgbox "Please select atleast one Languages or framework." 10 60
		jumpto lang_tools
	fi
else
    jumpto lang_tools
fi

: db_tools:
Database_tools=$(whiptail --title "Select Datbases" --checklist \
"Choose some databases that you want to install" 15 60 8 \
"SqlitePack" "Sqlite3" ON \
"MySQLPack" "MySql" OFF \
"MariaDBPack" "Maria DB" OFF \
"MongoDBPack" "MongoDB" OFF \
"RedisPack" "Redis" OFF \
"PostgresPack" "Postgresql" OFF \
"CouchDBPack" "CouchDB" OFF 3>&1 1>&2 2>&3)
 
exitstatus=$?
if [ $exitstatus = 0 ]; then
    if [ -z $Database_tools ]; then
    	whiptail --title "Selection Error" --msgbox "Please select atleast one database." 10 60
		jumpto db_tools
	fi
	
	if [[ " ${Database_tools[*]} " == *"MySQLPack"* ]]; then
    	: mysql_passwd:
    	Password=$(whiptail --title "MySql Password" --passwordbox "Enter you MySql Password. Click ok to continue (use tab)" 10 60 3>&1 1>&2 2>&3)
    	exitstatus=$?
    	if [ $exitstatus = 0 ]; then
    		if [ -z $Password ]; then
    			whiptail --title "Empty Password Error" --msgbox "Please enter a password." 10 60
				jumpto mysql_passwd
			else
				jumpto dev_tools
			fi
		else
			jumpto db_tools
		fi
	fi
else
	jumpto lang_tools
fi

: dev_tools:
Development_tools=$(whiptail --title "Select Dev Tools" --checklist \
"Choose some developer tools that you want to install" 15 60 8 \
"IntelliJPack" "intellij-idea" ON \
"VimPack" "Vim" OFF \
"VimCustomDotPack" "Vim Custom dotfiles" OFF \
"AtomPack" "Atom Text Editor(Webupd8 PPA)" OFF \
"BracketsPack" "Adobe Brackets(Webupd8 PPA)" OFF \
"SublimeTextPack" "Sublime Text 3" OFF \
"VSCodePack" "Visual Studio Code" OFF  3>&1 1>&2 2>&3)
 
exitstatus=$?
if [ $exitstatus = 0 ]; then
    if [ -z $Basic_tools ]; then
    	whiptail --title "Selection Error" --msgbox "Please select atleast one database." 10 60
		jumpto dev_tools
	fi
else
    jumpto db_tools
fi

: additional_tools:
Additional_tools=$(whiptail --title "Select Additional Tools" --checklist \
"Choose some additional tools that you want to install" 15 60 8 \
"GeckodriverPack" "Geckodriver(Web Scraping)" ON \
"VirtualBoxPack" "Oracle VirtualBox" OFF \
"LateXPack" "LaTeX" OFF \
"HerokuToolBeltPack" "Heroku toolbelt" OFF \
"GpartedPack" "Gparted" OFF \
"EtcherPack" "Etcher ISO Burner" OFF \
"AudacityPack" "Audacity" OFF \
"KdenlivePack" "kdenlive video editor" OFF \
"VocalAppPack" "Vocal Podcast App" OFF  3>&1 1>&2 2>&3)
 
exitstatus=$?
if [ $exitstatus -ne 0 ]; then
    jumpto dev_tools
fi

: confirm_last:
whiptail --title "Final Confirmation!" --yesno "Installation will start when you hit ok.Please provide password if asked. This might take a while so sit back and relax" 10 60
exitstatus=$?
if [ $exitstatus -ne 0 ]; then
    jumpto additional_tools
fi

sudo apt-get -y update
sudo apt-get -y upgrade

for i in "${Basic_tools[@]}"
do
   eval $i

done

for i in "${Language_tools[@]}"
do
   eval $i

done

for i in "${Database_tools[@]}"
do
   if [[ $i == *"MySQLPack"* ]]; then

    eval $i $Password
    
  else
    eval $i
    
    fi

done

for i in "${Development_tools[@]}"
do
   eval $i

done

for i in "${Additional_tools[@]}"
do
   eval $i

done

echo "Cleaning up ..."
sudo apt-get autoclean -y
sudo apt-get autoremove -y
cat art/all_good_bye_ascii.txt