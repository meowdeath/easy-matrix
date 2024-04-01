
## Matrix Synapse + PostgreSQL + Coturn (Audio & Video calls) + Caddy installation script

Matrix Synapse + PostgreSQL + Coturn (Audio & Video calls) + Caddy installation script

### Prerequisites

* VPS server with Debian/Ubuntu
* Domain. You can get it for free at [duckdns.org](https://www.duckdns.org/) (You need to login, create domain and specify the public ipv4 address of your VPS server) 

### Verified systems

1. Ubuntu 22.04 (Server)

### Run Command
1. You can use the following command to run the script (run as root)
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/meowdeath/easy-matrix-install/main/install.sh)
   ```
2. IMPORTANT: The script automatically creates a subdomain for the matrix, so, when the script asks for the domain, you will need to enter your domain in the following format: mydomain.com. And if you used [duckdns.org](https://www.duckdns.org/) (I recommend it if you want a budget server), the format will be mydomain.duckdns.org
