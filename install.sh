#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
CLEAR='\033[0m'


echo -e "${GREEN}Matrix Synapse + PostgreSQL + Coturn (Audio & Video calls) + Caddy script is running.${CLEAR}"

apt update
apt -y install debconf-utils
apt -y install sudo

POSTGRESQL_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c32)
COTURN_AUTH_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c32)
REGISTRATION_SHARED_SECRET=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c32)

echo -e "${RED}IMPORTANT:${CLEAR} ${YELLOW}The script automatically creates a subdomain for the matrix, so, next, you will need to enter your domain in the following format:${CLEAR} ${GREEN}mydomain.com${CLEAR}\n${YELLOW}And if you used duckdns (I recommend it if you want a budget server), the format will be${CLEAR} ${GREEN}mydomain.duckdns.org${CLEAR}"
read -p "Enter your domain: " DOMAIN

echo "matrix-synapse-py3 matrix-synapse/report-stats boolean false" | debconf-set-selections -v
echo "matrix-synapse-py3 matrix-synapse/server-name string matrix.${DOMAIN}" | debconf-set-selections -v

#INSTALLING MATRIX SYNAPSE
echo -e "${GREEN}Installing Matrix Synapse${CLEAR}"
apt install -y lsb-release wget apt-transport-https
wget -O /usr/share/keyrings/matrix-org-archive-keyring.gpg https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/matrix-org.list
apt update
apt -y install matrix-synapse-py3

#INSTALLING AND CONFIGURING POSTGRESQL-14
echo -e "${GREEN}Installing PostgreSQL-14${CLEAR}"
apt -y install postgresql-14
runuser -l postgres -c 'psql -c "CREATE USER synapse_user WITH PASSWORD '"'"${POSTGRESQL_PASSWORD}"'"';"'
runuser -l postgres -c 'createdb --encoding=UTF8 --locale=C --template=template0 --owner=synapse_user synapse'
echo "local synapse synapse_user scram-sha-256" >> /etc/postgresql/14/main/pg_hba.conf

cat <<EOT > /etc/matrix-synapse/homeserver.yaml
pid_file: "/var/run/matrix-synapse.pid"
listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    bind_addresses: ['::1', '127.0.0.1']
    resources:
      - names: [client, federation]
        compress: false
database:
  name: psycopg2
  args:
    user: synapse_user
    password: ${POSTGRESQL_PASSWORD}
    dbname: synapse
    host: localhost
    cp_min: 5
    cp_max: 10
log_config: "/etc/matrix-synapse/log.yaml"
media_store_path: /var/lib/matrix-synapse/media
signing_key_path: "/etc/matrix-synapse/homeserver.signing.key"
trusted_key_servers:
  - server_name: "matrix.org"
registration_shared_secret: ${REGISTRATION_SHARED_SECRET}
EOT

echo "listen_addresses = 'localhost'" >> /etc/postgresql/14/main/postgresql.conf

#INSTALLING AND CONFIGURING CADDY
echo -e "${GREEN}Installing Caddy${CLEAR}"
apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt -y install caddy


cat <<EOT > /etc/caddy/Caddyfile
matrix.${DOMAIN} {
  reverse_proxy /_matrix/* localhost:8008
  reverse_proxy /_synapse/client/* localhost:8008
  reverse_proxy localhost:8008
}

matrix.${DOMAIN}:8448 {
  reverse_proxy /_matrix/* localhost:8008
}
EOT

#INSTALLING AND CONFIGURING COTURN
echo -e "${GREEN}Installing Coturn${CLEAR}"
sudo NEEDRESTART_MODE=a apt -y install coturn

cat <<EOT > /etc/turnserver.conf
server-name=turn.$DOMAIN
realm=turn.$DOMAIN
listening-ip=$(dig +short myip.opendns.com @resolver1.opendns.com)

listening-port=3478
min-port=10000
max-port=20000

# The "verbose" option is useful for debugging issues
verbose

use-auth-secret
static-auth-secret=${COTURN_AUTH_PASSWORD}
EOT

echo "turn_uris: [ \"turn:turn.${DOMAIN}?transport=udp\", \"turn:turn.${DOMAIN}?transport=tcp\" ]" >> /etc/matrix-synapse/homeserver.yaml
echo "turn_shared_secret: ${COTURN_AUTH_PASSWORD}" >> /etc/matrix-synapse/homeserver.yaml

#RESTARTING SERVICES
echo -e "${GREEN}Restarting Caddy service...${CLEAR}"
systemctl restart caddy.service
echo -e "${GREEN}Restarting PostgreSQL service...${CLEAR}"
systemctl restart postgresql.service
echo -e "${GREEN}Restarting Coturn service...${CLEAR}"
systemctl restart coturn.service
echo -e "${GREEN}Restarting Matrix Synapse service...${CLEAR}"
systemctl restart matrix-synapse.service

echo -e "${GREEN}DONE${CLEAR}"

echo -e "${GREEN}Visit ${CYAN}\e[4mhttps://matrix.${DOMAIN}/\e[0m${GREEN} and check if matrix start page is appeared${CLEAR}"
echo -e "${RED}IMPORTANT: You may need to wait a while for the server to come up${CLEAR}"
echo -e "\n"
echo -e "${GREEN}You can register a user using the following command:${CLEAR}"
echo -e "${CYAN}register_new_matrix_user -u USERNAME -p PASSWORD -a https://matrix.${DOMAIN} -c /etc/matrix-synapse/homeserver.yaml${CLEAR}"
echo -e "${GREEN}where USERNAME is your username and PASSWORD is your password${CLEAR}"
echo -e "\n"
read -p "Do you want the script to create two users to test the server? (y/n) " yn

case $yn in 
	[yY] ) 
		secs=$((30))
		while [ $secs -gt 0 ]; do
		   echo -ne "${YELLOW}Waiting for server to startup: ${GREEN}$secs\033[0K\r${CLEAR}"
		   sleep 1
		   : $((secs--))
		done
		FIRST_USER_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c32)
		SECOND_USER_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c32)
		register_new_matrix_user -u first_user -p ${FIRST_USER_PASSWORD} -a "https://matrix.${DOMAIN}" -c /etc/matrix-synapse/homeserver.yaml
		register_new_matrix_user -u second_user -p ${SECOND_USER_PASSWORD} -a "https://matrix.${DOMAIN}" -c /etc/matrix-synapse/homeserver.yaml
		echo -e "${YELLOW}First user login and password: ${CLEAR}${GREEN}first_user${CLEAR}:${GREEN}${FIRST_USER_PASSWORD}${CLEAR}"
		echo -e "${YELLOW}Second user login and password: ${CLEAR}${GREEN}second_user${CLEAR}:${GREEN}${SECOND_USER_PASSWORD}${CLEAR}"
		;;
	[nN] ) echo Okay;
		exit;;
	* ) echo invalid response;;
esac

