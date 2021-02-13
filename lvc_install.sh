#!/bin/bash

TMP_FOLDER=$(mktemp -d)
CONFIG_FILE="levantcoin.conf"
CONFIG_FOLDER=".levantcoin"
COIN_DAEMON="levantcoind"
COIN_CLI="levantcoin-cli"
COIN_PATH="/usr/local/bin/"
COIN_ARCHIVE="levantcoin-masternode"
COIN_VERSION="1.0.0.0g"
COIN_TGZ="https://github.com/levantcoin-project/levantcoin/releases/download/${COIN_VERSION}/${COIN_ARCHIVE}.tar.gz"
COIN_NAME="levantcoin"
COIN_PORT=29004

NODEIP=$(wget -q4O - icanhazip.com)

BLUE="\033[0;34m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m" 
PURPLE="\033[0;35m"
RED='\033[0;31m'
GREEN="\033[0;32m"
NC='\033[0m'
MAG='\e[1;35m'

function purge_old_installation() {
  echo -e "${GREEN}Searching and removing old $COIN_NAME files and configurations${NC}"
  systemctl stop "${COIN_NAME}.service" > /dev/null 2>&1
  killall "${COIN_DAEMON}" > /dev/null 2>&1
  rm -- "$0" > /dev/null 2>&1
  rm ~/"${CONFIG_FOLDER}/bootstrap.dat.old" > /dev/null 2>&1
  rm ~/"${CONFIG_FOLDER}/${CONFIG_FILE}" > /dev/null 2>&1
  cd /usr/local/bin && rm "${COIN_CLI}" "${COIN_DAEMON}" > /dev/null 2>&1
  cd /usr/bin && rm "${COIN_CLI}" "${COIN_DAEMON}" > /dev/null 2>&1
  echo -e "${GREEN}* Done${NC}"
}

function create_swap() {
  MEMORY_TOTAL="$(free -mt | grep Total: | awk '{printf $2}')"
  if [ "$MEMORY_TOTAL" -lt "900" ]
  then
    echo -e "${RED}You have only ${MEMORY_TOTAL}MB of memory.${NC} Creating 2GB swap-file."
    if [ -e /swapfile_nbx ]
    then
      echo -e "${RED}/swapfile_nbx already exists.${NC}"
      exit 1
    fi
    dd if=/dev/zero of=/swapfile_nbx bs=2048 count=1048576 &> /dev/null
    chmod 600 /swapfile_nbx
    mkswap /swapfile_nbx &> /dev/null
    swapon /swapfile_nbx &> /dev/null
    if [ "$?" -gt "0" ]
    then
	  echo -e "${RED}Error creating swap file.${NC}"
    fi
    echo >> /etc/fstab
    echo /swapfile_nbx swap swap defaults 0 0 >> /etc/fstab
    echo -e "${GREEN}* Done${NC}"
  fi
}

function download_node() {
  echo -e "${GREEN}Downloading and Installing VPS $COIN_NAME Daemon${NC}"
  cd "${TMP_FOLDER}" >/dev/null 2>&1
  wget -qO "${COIN_ARCHIVE}.tar.gz" "${COIN_TGZ}"
  if [ "$?" -gt "0" ]
  then
    echo -e "${RED}Failed to download ${COIN_NAME}. Please investigate.${NC}"
    exit 1
  fi
  tar -zxvf "${COIN_ARCHIVE}.tar.gz" >/dev/null 2>&1
  rm "${COIN_ARCHIVE}.tar.gz"
  cd "${COIN_ARCHIVE}" >/dev/null 2>&1
  chmod +x "${COIN_DAEMON}" "${COIN_CLI}"
  cp "${COIN_DAEMON}" "${COIN_CLI}" "${COIN_PATH}"
  cd ~ >/dev/null 2>&1
  rm -rf "${TMP_FOLDER}" >/dev/null 2>&1
}


function configure_systemd() {
  cat << EOF > "/etc/systemd/system/${COIN_NAME}.service"
[Unit]
Description=${COIN_NAME} service
After=network.target

[Service]
User=root
Group=root

ExecStart=${COIN_PATH}${COIN_DAEMON}
ExecStop=-${COIN_PATH}${COIN_CLI} stop

Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl start "${COIN_NAME}.service"
  systemctl enable "${COIN_NAME}.service" >/dev/null 2>&1

  if [[ -z "$(ps axo cmd:100 | egrep ${COIN_DAEMON})" ]]
  then
    echo -e "${RED}${COIN_NAME} is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start ${COIN_NAME}.service"
    echo -e "systemctl status ${COIN_NAME}.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}

function create_key() {
  "${COIN_PATH}${COIN_DAEMON}" -daemon
  sleep 3
  if [ -z "$(ps axo cmd:100 | grep $COIN_DAEMON)" ]
  then
   echo -e "${RED}${COIN_NAME} server couldn not start. Check /var/log/syslog for errors.{$NC}"
   exit 1
  fi
  COIN_KEY="$(${COIN_PATH}${COIN_CLI} createmasternodekey)"
  if [ "$?" -gt "0" ]
  then
    echo -e "${RED}Wallet not fully loaded. Let us wait and try again to generate the PRIVATE Key${NC}"
    sleep 3
    COIN_KEY="$(${COIN_PATH}${COIN_CLI} createmasternodekey)"
  fi
  "${COIN_PATH}${COIN_CLI}" stop
  sleep 3
}

function update_config() {
  mkdir $CONFIGFOLDER >/dev/null 2>&1
  RPCUSER=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w4 | head -n1)
  RPCPASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w20 | head -n1)
  cat << EOF >> ~/"${CONFIG_FOLDER}/${CONFIG_FILE}"
rpcuser=Levantcoin$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
maxconnections=64
masternode=1
masternodeprivkey=${COIN_KEY}
externalip=${NODEIP}:${COIN_PORT}
EOF
}


function get_ip() {
  declare -a NODE_IPS
  for ip in $(hostname --all-ip-addresses)
  do
    NODE_IPS+=($(wget -q4 -T 5 -O - --bind-address="${ip}" icanhazip.com))
  done
  NODE_IPS=($(echo "${NODE_IPS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

  if [ ${#NODE_IPS[@]} -gt 1 ]
  then
    echo -e "${GREEN}More than one IP. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
    INDEX=0
    for ip in ${NODE_IPS[@]}
    do
      echo ${INDEX} "$ip"
      let INDEX=${INDEX}+1
    done
    read -e choose_ip
    NODEIP="${NODE_IPS[$choose_ip]}"
  else
    NODEIP="${NODE_IPS[0]}"
  fi
}


function checks() {


  if [[ $EUID -ne 0 ]]
  then
    echo -e "${RED}$0 must be run as root.${NC}"
    exit 1
  fi

}

function important_information() {
  echo
  echo -e "${BLUE}================================================================================${NC}"
  echo -e "${GREEN}Configuration file is:${NC} ${RED}~/${CONFIG_FOLDER}/${CONFIG_FILE}${NC}"
  echo -e "${GREEN}Start:${NC} ${RED}systemctl start ${COIN_NAME}.service${NC}"
  echo -e "${GREEN}Stop:${NC} ${RED}systemctl stop ${COIN_NAME}.service${NC}"
  echo -e "${GREEN}VPS_IP:${NC} ${GREEN}${NODEIP}:${COIN_PORT}${NC}"
  echo -e "${GREEN}MASTERNODE PRIVATE KEY is:${NC} ${PURPLE}${COIN_KEY}${NC}"
  echo -e "${BLUE}================================================================================${NC}"
  echo -e "${CYAN}Start your daemon - leavantcoind (alias name) (wallet)${NC}"
  echo -e "${CYAN}Start your masternode using the command${NC}"
  echo -e "${CYAN}startmasternode alias false MN1${NC}"
  echo -e "${CYAN}MN1 = name wallet or alias${NC}"
  echo -e "${BLUE}================================================================================${NC}"
}

function setup_node() {
  get_ip
  create_key
  update_config
  important_information
  configure_systemd
}


clear

purge_old_installation
create_swap
download_node
setup_node
