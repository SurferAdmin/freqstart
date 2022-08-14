<div id="top"></div>

<!-- FREQSTART -->
# FREQSTART v2.0.4 - rootless
(Requires full setup. Do not update from versions below v2.0.0)

See what has been changed: <a href="#changelog">Changelog</a>

## Setup & Docker-Manager for Freqtrade

Freqstart simplifies the use of Freqtrade with Docker. Including a simple setup guide for Freqtrade,
configurations and FreqUI with a secured SSL proxy for IP or domain. Freqstart also automatically
installs implemented strategies based on Docker Compose files and detects necessary updates.

If you are not familiar with Freqtrade, please read the complete documentation first on: [www.freqtrade.io](https://www.freqtrade.io/)

![Freqstart Screen Shot][product-screenshot]

### Features

* `Freqtrade` Guided setup for Docker including the native config generator and creation of "user_data" folder.
* `Docker` Version check of images via manifest using minimal ressources and creating local backups.
* `Prerequisites` Install server prerequisites and upgrades and check for timezone sync (UTC).
* `FreqUI` Full setup of FreqUI with Nginx proxy for secured IP (openssl), domain (letsencrypt) or localhost.
* `Binance Proxy` Setup for Binance proxy if you run multiple bots at once incl. reusable config file.
* `Kucoin Proxy` Setup for Kucoin proxy if you run multiple bots at once incl. reusable config file.
* `Strategies` Automated installation of implemented strategies like NostalgiaForInfinity incl. updates.

### Strategies

The following list is in alphabetical order and does not represent any recommendation:

* DoesNothingStrategy (Author: Gert Wohlgemuth, https://github.com/freqtrade/freqtrade-strategies)
* MultiMA_TSL (Author: stash86, https://github.com/stash86/MultiMA_TSL/)
* NostalgiaForInfinityX (Author: iterativ, https://github.com/iterativv/NostalgiaForInfinity)

Help expanding the strategies list and include config files if possible: [freqstart.strategies.json](https://github.com/berndhofer/freqstart/blob/develop/freqstart.strategies.json)

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- GETTING STARTED -->
## Getting Started

Freqstart provides an interactive setup guide for server security, Freqtrade incl. config creation, FreqUI, Binance- & Kucoin-Proxy routines.

### Prerequisites

Freqstart installs server packages and configurations tailored to the needs of Freqtrade and may overwrite existing installations and configurations. It is recommended to set it up in a new and clean environment!

Packages: git, curl, jq, docker-ce, docker-compose, docker-ce-rootless-extras, systemd-container, uidmap, dbus-user-session, chrony, ufw, dnsutils, lsof , cron, uidmap

### Recommended VPS

Vultr (AMD High Performance / Tokyo): [www.vultr.com](https://www.vultr.com/?ref=9122650-8H)

### Installation

1. Clone the repo
   ```sh
   git clone https://github.com/berndhofer/freqstart.git
   ```
2. Change directory to `freqstart`
   ```sh
   cd ~/freqstart
   ```
3. Make `freqstart.sh` executable
   ```sh
   sudo chmod +x freqstart.sh
   ```
4. Setup `freqstart`
   ```sh
   ./freqstart.sh --setup
   ```
   
### Start

1. Start a `Freqtrade` container
   ```sh
   freqstart --compose example.yml
   ```
2. Start a `Freqtrade` container, non-interactive
   ```sh
   freqstart --compose example.yml --yes
   ```
   
### Stop

1. Stop a `Freqtrade` container and disable autoupdate
   ```sh
   freqstart --quit example.yml
   ```
2. Stop a `Freqtrade` container and disable autoupdate, non-interactive 
   ```sh
   freqstart --quit example.yml --yes
   ```
   
### Reset to stop and remove all docker images, containers and networks

   ```sh
   freqstart --reset
   ```
   
<p align="right">(<a href="#top">back to top</a>)</p>

<!-- EXAMPLE PROJECT -->
## Pojects

With Freqstart you are no longer bound to a single docker-compose.yml and can freely structure and link your Freqtrade bots.

* Have multiple container (services) in one project file
* Have a single container (service) in multiple project files
* Have multiple container (services) in multiple project files

### Example Project (example.yml)

* Project file based on NostalgiaForInfinityX and Binance (BUSD) with Proxy and FreqUI enabled.

`NOTICE:` Port is not needed anymore for FreqUI exposure.

   ```yml
   version: '3' # REQUIRED
   services: # REQUIRED: For multiple services duplicate code from here
     example_dryrun: # REQUIRED: Do not forget to change service name
       image: freqtradeorg/freqtrade:stable # REQUIRED: For more updates use freqtradeorg/freqtrade:latest
       volumes: # REQUIRED
         - "./user_data:/freqtrade/user_data" # REQUIRED: Do not change
       command: > # REQUIRED
         trade # REQUIRED
         --dry-run # OPTIONAL: Remove if you want to trade live
         --db-url sqlite:////freqtrade/user_data/example_dryrun.sqlite # REQUIRED: Do not forget to change sqlite name
         --logfile /freqtrade/user_data/logs/example_dryrun.log # OPTIONAL: Recommended and do not forget to change log name
         --strategy NostalgiaForInfinityX # REQUIRED
         --strategy-path /freqtrade/user_data/strategies/NostalgiaForInfinityX # REQUIRED
         --config /freqtrade/user_data/strategies/NostalgiaForInfinityX/exampleconfig.json # REQUIRED: Add your API credentials from exchange
         --config /freqtrade/user_data/strategies/NostalgiaForInfinityX/pairlist-volume-binance-busd.json # OPTIONAL: Use different volume or static pairlists
         --config /freqtrade/user_data/strategies/NostalgiaForInfinityX/blacklist-binance.json # OPTIONAL
         --config /freqtrade/user_data/freqstart_frequi.json # OPTIONAL: If you want to manage bot via FreqUI
         --config /freqtrade/user_data/freqstart_proxy_binance.json # OPTIONAL: If you want to use proxy for Binance
   ```

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- ROADMAP -->
## Roadmap

See the [open issues](https://github.com/berndhofer/freqstart/issues) for a full list of proposed features (and known issues).

### Changelog

`v2.0.4`
* Fixed missing docker host variable while running script from conrjob (Review "crontab -e" if necessary)
* Added "/script" directory to maintain a cleaner approach
* Docker project routine can run now projects from different directories and defaults to script directory when no directory is set (Feel free to place your custom project yml files wherever you like)
* Improved strategies routine to allow additional custom strategies file (Do not change "/script/strategies.json" but add "/strategies.json" file optionally)

`v2.0.3`
* Removed deprecated code in docker routine and value get/update functions
* Improved ufw ssh port confirmation and removed unnecessary output in function
* Improved cron routine for certbot and added cron remove to docker purge

`v2.0.2`
* Improved sudoers function

`v2.0.1`
* Fast permission fix for user_data folder
* Removed nginx unblock function
* Fixed sudoers function

`v2.0.0`
* Implemented rootless docker setup routine
* Overhauled user routine incl usage of machinectl for login so set env variable correctly
* Removed port exposure from docker services as a requirement for FreqUI access
* Removed port validation from docker project function as this is not a requirement anymore
* Removed docker image backup logic because of overhead and security concerns
* Fixed some permission and shellcheck errors (Thanks: tomjrtsmith)
* Fixed package installation routine for minimal images (Thanks: lsiem)

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- DISCLAIMER -->
## Disclaimer
 
This software is for educational purposes only. Do not risk money which you are afraid to lose. USE THE SOFTWARE AT YOUR OWN RISK. THE AUTHORS AND ALL AFFILIATES ASSUME NO RESPONSIBILITY FOR YOUR TRADING RESULTS.

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- SUPPORT -->
## Support

Since this is a small project where I taught myself some bash scripts, you are welcome to improve the code. If you just use the script and like it, remember that it took a lot of time, testing and also money for infrastructure. You can contribute by donating to the following wallets. Thank you very much for that!

* `BTC` 1M6wztPA9caJbSrLxa6ET2bDJQdvigZ9hZ
* `ETH` 0xb155f0F64F613Cd19Fb35d07D43017F595851Af5
* `BSC` 0xb155f0F64F613Cd19Fb35d07D43017F595851Af5

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->
[product-screenshot]: images/screenshot.png