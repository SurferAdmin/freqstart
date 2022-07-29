<div id="top"></div>

<!-- FREQSTART -->
# FREQSTART v1.0.1

`WARNING` Nginx proxy has been moved to docker in v1.0.0 and could cause errors if native installation exists. Backup "user_data", reset VPS and run setup again.

`v1.0.1`
* TBA

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

Packages: git, curl, jq, docker-ce, chrony, ufw

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
5. Setup `freqstart`, non-interactive
   ```sh
   ./freqstart.sh --setup --yes
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

1. Project file with NostalgiaForInfinityX and Binance with BUSD
   ```yml
   version: '3'
   services:
     example_dryrun: # IMPORTANT: Dont forget to change service name!
       image: freqtradeorg/freqtrade:stable
       volumes:
         - "./user_data:/freqtrade/user_data"
       ports:
         - "127.0.0.1:9000:9999" # OPTIONAL: Choose port between 9000 and 9100 and forward to 9999 or remove if not using FreqUI.
       tty: true
       command: >
         trade
         --dry-run
         --dry-run-wallet
         --db-url sqlite:////freqtrade/user_data/example_dryrun.sqlite
         --logfile /freqtrade/user_data/logs/example_dryrun.log
         --strategy NostalgiaForInfinityX
         --strategy-path /freqtrade/user_data/strategies/NostalgiaForInfinityX
         --config /freqtrade/user_data/strategies/NostalgiaForInfinityX/exampleconfig.json
         --config /freqtrade/user_data/strategies/NostalgiaForInfinityX/pairlist-volume-binance-busd.json
         --config /freqtrade/user_data/strategies/NostalgiaForInfinityX/blacklist-binance.json
         --config /freqtrade/user_data/frequi.json # OPTIONAL: If you want to manage bot via FreqUI.
         --config /freqtrade/user_data/binance_proxy.json
   ```

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- ROADMAP -->
## Roadmap

See the [open issues](https://github.com/berndhofer/freqstart/issues) for a full list of proposed features (and known issues).

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