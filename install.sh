#!/bin/bash

# Get user options
while getopts i:-: option; do
    case "${option}" in
        -)
            case "${OPTARG}" in
                help)
                    help="true";;
                resolveip)
                    resolveip="true";;
                resolvedns)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    resolvedns=${val};;
                install-http)
                    http="true";;
                skip-http)
                    http="false";;
            esac;;
        i) resolveip="true";;
    esac
done

function displayhelp() {
    if [[ ! -z $help ]]; then
        echo 'usage: install.sh --resolveip --resolvedns "fqdn"'
        echo "options:"
        echo "--resolveip    Use IP como nome do servidor. Não é possível usar em combinação com --resolvedns ou -d"
        echo '--resolvedns "fqdn"    Use FQDN para o nome do servidor. Não é possível usar em combinação com --resolveip ou -i'
        echo "--install-http    Instale o servidor http para hospedar scripts de instalação. Não é possível usar em combinação com --skip-http ou -n"
        echo "--skip-http    Ignore a instalação do servidor http. Não é possível usar em combinação com --install-http ou -h"
        exit 0
    fi
}
displayhelp
# Get Username
uname=$(whoami)
admintoken=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c16)

ARCH=$(uname -m)

# identify OS
if [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID

    UPSTREAM_ID=${ID_LIKE,,}

    # Fallback to ID_LIKE if ID was not 'ubuntu' or 'debian'
    if [ "${UPSTREAM_ID}" != "debian" ] && [ "${UPSTREAM_ID}" != "ubuntu" ]; then
        UPSTREAM_ID="$(echo ${ID_LIKE,,} | sed s/\"//g | cut -d' ' -f1)"
    fi


elif type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    # Older Debian/Ubuntu/etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
    # Older SuSE/etc.
    OS=SuSE
    VER=$(cat /etc/SuSe-release)
elif [ -f /etc/redhat-release ]; then
    # Older Red Hat, CentOS, etc.
    OS=RedHat
    VER=$(cat /etc/redhat-release)
else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    VER=$(uname -r)
fi


# output debugging info if $DEBUG set
if [ "$DEBUG" = "true" ]; then
    echo "OS: $OS"
    echo "VER: $VER"
    echo "UPSTREAM_ID: $UPSTREAM_ID"
    exit 0
fi

# Setup prereqs for server
# common named prereqs
PREREQ="curl wget unzip tar"
PREREQDEB="dnsutils"
PREREQRPM="bind-utils"
PREREQARCH="bind"

echo "Instalando pré-requisitos"
if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ]  || [ "${UPSTREAM_ID}" = "ubuntu" ] || [ "${UPSTREAM_ID}" = "debian" ]; then
    sudo apt-get update
    sudo apt-get install -y  ${PREREQ} ${PREREQDEB} # git
elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ]   || [ "${UPSTREAM_ID}" = "rhel" ] ; then
# opensuse 15.4 fails to run the relay service and hangs waiting for it
# needs more work before it can be enabled
# || [ "${UPSTREAM_ID}" = "suse" ]
    sudo yum update -y
    sudo yum install -y  ${PREREQ} ${PREREQRPM} # git
elif [ "${ID}" = "arch" ] || [ "${UPSTREAM_ID}" = "arch" ]; then
    sudo pacman -Syu
    sudo pacman -S ${PREREQ} ${PREREQARCH}
else
    echo "Não suporta OS"
    # give them the option to continue
    echo -n "Você gostaria de continuar? As dependências podem não ser satisfeitas... [y/n] "
    read continue_no_dependencies
    if [ $continue_no_dependencies == "y" ]; then
        echo ontinuando..."
    elif [ $continue_no_dependencies != "n" ]; then
        echo "Resposta inválida, saindo."
	exit 1
    else
        exit 1
    fi
fi

# Choice for DNS or IP
if [[ -z "$resolveip" && -z "$resolvedns" ]]; then
    PS3='Choose your preferred option, IP or DNS/Domain:'
    WAN=("IP" "DNS/Dominio")
    select WANOPT in "${WAN[@]}"; do
    case $WANOPT in
    "IP")
    wanip=$(dig @resolver4.opendns.com myip.opendns.com +short)
    break
    ;;

    "DNS/Domain")
    echo -ne "Digite seu domínio/endereço DNS preferido ${NC}: "
    read wanip
    #check wanip is valid domain
    if ! [[ $wanip =~ ^[a-zA-Z0-9]+([a-zA-Z0-9.-]*[a-zA-Z0-9]+)?$ ]]; then
        echo -e "${RED}Domínio/endereço DNS inválido${NC}"
        exit 1
    fi
    break
    ;;
    *) echo "invalid option $REPLY";;
    esac
    done
elif [[ ! -z "$resolveip" && ! -z "$resolvedns" ]]; then
    echo -e "\nERROR: Você não pode usar os dois --resolveip & --resolvedns opções simultaneamente"
    exit 1
elif [[ ! -z "$resolveip" && -z "$resolvedns" ]]; then
    wanip=$(dig @resolver4.opendns.com myip.opendns.com +short)
elif [[ -z "$resolveip" && ! -z "$resolvedns" ]]; then
    wanip="$resolvedns"
    if ! [[ $wanip =~ ^[a-zA-Z0-9]+([a-zA-Z0-9.-]*[a-zA-Z0-9]+)?$ ]]; then
        echo -e "${RED}Domínio/endereço DNS inválido${NC}"
        exit 1
    fi
fi

# Make Folder /opt/rustdesk/
if [ ! -d "/opt/rustdesk" ]; then
    echo "Criando /opt/rustdesk"
    sudo mkdir -p /opt/rustdesk/
fi
sudo chown "${uname}" -R /opt/rustdesk
cd /opt/rustdesk/ || exit 1


#Download latest version of Rustdesk
RDLATEST=$(curl https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest -s | grep "tag_name"| awk '{print substr($2, 2, length($2)-3) }')

echo "Instalando o RUSTDESK Server"
echo "Traduzido por Henrique Lucas"
if [ "${ARCH}" = "x86_64" ] ; then
wget "https://github.com/rustdesk/rustdesk-server/releases/download/${RDLATEST}/rustdesk-server-linux-amd64.zip"
unzip rustdesk-server-linux-amd64.zip
mv amd64/* /opt/rustdesk/
elif [ "${ARCH}" = "armv7l" ] ; then
wget "https://github.com/rustdesk/rustdesk-server/releases/download/${RDLATEST}/rustdesk-server-linux-armv7.zip"
unzip rustdesk-server-linux-armv7.zip
mv armv7/* /opt/rustdesk/
elif [ "${ARCH}" = "aarch64" ] ; then
wget "https://github.com/rustdesk/rustdesk-server/releases/download/${RDLATEST}/rustdesk-server-linux-arm64v8.zip"
unzip rustdesk-server-linux-arm64v8.zip
mv arm64v8/* /opt/rustdesk/
fi

chmod +x /opt/rustdesk/hbbs
chmod +x /opt/rustdesk/hbbr


# Make Folder /var/log/rustdesk/
if [ ! -d "/var/log/rustdesk" ]; then
    echo "Criando /var/log/rustdesk"
    sudo mkdir -p /var/log/rustdesk/
fi
sudo chown "${uname}" -R /var/log/rustdesk/

# Setup Systemd to launch hbbs
rustdesksignal="$(cat << EOF
[Unit]
Description=Rustdesk Signal Server
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/opt/rustdesk/hbbs -k _
WorkingDirectory=/opt/rustdesk/
User=${uname}
Group=${uname}
Restart=always
StandardOutput=append:/var/log/rustdesk/signalserver.log
StandardError=append:/var/log/rustdesk/signalserver.error
# Restart service after 10 seconds if node service crashes
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
)"
echo "${rustdesksignal}" | sudo tee /etc/systemd/system/rustdesksignal.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable rustdesksignal.service
sudo systemctl start rustdesksignal.service

# Setup Systemd to launch hbbr
rustdeskrelay="$(cat << EOF
[Unit]
Description=Rustdesk Relay Server
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/opt/rustdesk/hbbr -k _
WorkingDirectory=/opt/rustdesk/
User=${uname}
Group=${uname}
Restart=always
StandardOutput=append:/var/log/rustdesk/relayserver.log
StandardError=append:/var/log/rustdesk/relayserver.error
# Restart service after 10 seconds if node service crashes
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
)"
echo "${rustdeskrelay}" | sudo tee /etc/systemd/system/rustdeskrelay.service > /dev/null
sudo systemctl daemon-reload
sudo systemctl enable rustdeskrelay.service
sudo systemctl start rustdeskrelay.service

while ! [[ $CHECK_RUSTDESK_READY ]]; do
  CHECK_RUSTDESK_READY=$(sudo systemctl status rustdeskrelay.service | grep "Active: active (running)")
  echo -ne "O Rustdesk Relay ainda não está pronto...${NC}\n"
  sleep 3
done

pubname=$(find /opt/rustdesk -name "*.pub")
key=$(cat "${pubname}")

echo "Arrumando a instalação"
if [ "${ARCH}" = "x86_64" ] ; then
rm rustdesk-server-linux-amd64.zip
rm -rf amd64
elif [ "${ARCH}" = "armv7l" ] ; then
rm rustdesk-server-linux-armv7.zip
rm -rf armv7
elif [ "${ARCH}" = "aarch64" ] ; then
rm rustdesk-server-linux-arm64v8.zip
rm -rf arm64v8
fi

function setuphttp () {
    # Create windows install script
    wget https://raw.githubusercontent.com/dinger1986/rustdeskinstall/master/WindowsAgentAIOInstall.ps1
    sudo sed -i "s|wanipreg|${wanip}|g" WindowsAgentAIOInstall.ps1
    sudo sed -i "s|keyreg|${key}|g" WindowsAgentAIOInstall.ps1

    # Create linux install script
    wget https://raw.githubusercontent.com/dinger1986/rustdeskinstall/master/linuxclientinstall.sh
    sudo sed -i "s|wanipreg|${wanip}|g" linuxclientinstall.sh
    sudo sed -i "s|keyreg|${key}|g" linuxclientinstall.sh

    # Download and install gohttpserver
    # Make Folder /opt/gohttp/
    if [ ! -d "/opt/gohttp" ]; then
        echo "Criando /opt/gohttp"
        sudo mkdir -p /opt/gohttp/
        sudo mkdir -p /opt/gohttp/public
    fi
    sudo chown "${uname}" -R /opt/gohttp
    cd /opt/gohttp
    GOHTTPLATEST=$(curl https://api.github.com/repos/codeskyblue/gohttpserver/releases/latest -s | grep "tag_name"| awk '{print substr($2, 2, length($2)-3) }')

    echo "Instalando Go HTTP Server"
    if [ "${ARCH}" = "x86_64" ] ; then
    wget "https://github.com/codeskyblue/gohttpserver/releases/download/${GOHTTPLATEST}/gohttpserver_${GOHTTPLATEST}_linux_amd64.tar.gz"
    tar -xf  gohttpserver_${GOHTTPLATEST}_linux_amd64.tar.gz 
    elif [ "${ARCH}" =  "aarch64" ] ; then
    wget "https://github.com/codeskyblue/gohttpserver/releases/download/${GOHTTPLATEST}/gohttpserver_${GOHTTPLATEST}_linux_arm64.tar.gz"
    tar -xf  gohttpserver_${GOHTTPLATEST}_linux_arm64.tar.gz
    elif [ "${ARCH}" = "armv7l" ] ; then
    echo "Go HTTP Server não suportado em dispositivos ARM de 32 bits"
    echo -e "O seu endereço de IP/DNS é: ${wanip}"
    echo -e "E sua chave secreta é: ${key}"
    exit 1
    fi

    # Copy Rustdesk install scripts to folder
    mv /opt/rustdesk/WindowsAgentAIOInstall.ps1 /opt/gohttp/public/
    mv /opt/rustdesk/linuxclientinstall.sh /opt/gohttp/public/

    # Make gohttp log folders
    if [ ! -d "/var/log/gohttp" ]; then
        echo "Criando /var/log/gohttp"
        sudo mkdir -p /var/log/gohttp/
    fi
    sudo chown "${uname}" -R /var/log/gohttp/

    echo "Organizando a instalação do servidor Go HTTP"
    if [ "${ARCH}" = "x86_64" ] ; then
    rm gohttpserver_"${GOHTTPLATEST}"_linux_amd64.tar.gz
    elif [ "${ARCH}" = "armv7l" ] || [ "${ARCH}" =  "aarch64" ]; then
    rm gohttpserver_"${GOHTTPLATEST}"_linux_arm64.tar.gz
    fi


    # Setup Systemd to launch Go HTTP Server
    gohttpserver="$(cat << EOF
[Unit]
Description=Go HTTP Server
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/opt/gohttp/gohttpserver -r ./public --port 8000 --auth-type http --auth-http admin:${admintoken}
WorkingDirectory=/opt/gohttp/
User=${uname}
Group=${uname}
Restart=always
StandardOutput=append:/var/log/gohttp/gohttpserver.log
StandardError=append:/var/log/gohttp/gohttpserver.error
# Restart service after 10 seconds if node service crashes
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
)"
    echo "${gohttpserver}" | sudo tee /etc/systemd/system/gohttpserver.service > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable gohttpserver.service
    sudo systemctl start gohttpserver.service


    echo -e "Seu endereço IP/DNS é ${wanip}"
    echo -e "Sua chave secreta é: is ${key}"
    echo -e "Instale o Rustdesk em suas máquinas e altere sua chave pública e nome IP/DNS para os valores acima"
    echo -e "Você pode acessar seus scripts de instalação para clientes em http:// ${wanip}:8000"
    echo -e "O nome de usuário é admin e a senha é ${admintoken}"
    if [[ -z "$http" ]]; then
        echo "Pressione qualquer tecla para finalizar a instalação"
        while [ true ] ; do
        read -t 3 -n 1
        if [ $? = 0 ] ; then
        exit ;
        else
        echo "Esperando selecionar qualquer tecla"
        fi
        done
        break
    fi
}

# Choice for Extras installed
if [[ -z "$http" ]]; then
    PS3='Please choose if you want to download configs and install HTTP server:'
    EXTRA=("Yes" "No")
    select EXTRAOPT in "${EXTRA[@]}"; do
    case $EXTRAOPT in
    "Yes")
    setuphttp
    break
    ;;
    "No")
    echo -e "Seu endereço IP/DNS é: ${wanip}"
    echo -e "Sua chave pública é: ${key}"
    echo -e "Instale o Rustdesk em suas máquinas e altere sua chave pública e nome IP/DNS para os valores acima"

    echo "Pressione qualquer tecla para finalizar a instalação"
    while [ true ] ; do
    read -t 3 -n 1
    if [ $? = 0 ] ; then
    exit ;
    else
    echo "aguardando o pressionamento da tecla"
    fi
    done
    break
    ;;
    *) echo "opção inválida $REPLY";;
    esac
    done
elif [ "$http" = "true" ]; then
    setuphttp
elif [ "$http" = "false" ]; then
    echo -e "Seu endereço IP/DNS é ${wanip}"
    echo -e "Sua chave pública é ${key}"
    echo -e "Instale o Rustdesk em suas máquinas e altere sua chave pública e nome IP/DNS para os valores acima"
fi
