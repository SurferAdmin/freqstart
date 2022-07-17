<div id="top"></div>

<!-- FREQSTART -->
# FREQSTART v0.1.8

`Warning` Major changes to code in v.0.1.6. Stop containers and run setup again, review project files!

### Freqtrade with Docker

Freqstart simplifies the use of Freqtrade with Docker. Including a simple setup guide for Freqtrade,
configurations and FreqUI with a secured SSL proxy for IPs and domains. Freqtrade also automatically
installs implemented strategies based on Docker Compose files and detects necessary updates.

If you are not familiar with Freqtrade, please read the complete documentation first on: [www.freqtrade.io](https://www.freqtrade.io/)

![Freqstart Screen Shot][product-screenshot]

### Features

* `Freqtrade` Guided setup for Freqtrade with Docker including the config generator and "user_data" folder.
* `Docker` Version check of images via manifest using minimal ressources and creating local backups.
* `Prerequisites` Install server prerequisites and upgrades and check for timezone sync and set it to UTC.
* `FreqUI` Full setup of FreqUI with Nginx proxy for secured IP (openssl), domain (letsencrypt) or localhost.
* `Binance Proxy` Setup for Binance proxy if you run multiple bots at once incl. reusable config file.
* `Example Bot` Example bot for Binance with all implemented features and as guidance for ".yml" container.
* `Strategies` Automated installation of implemented strategies like NostalgiaForInfinity incl. updates.

### Strategies

The following list is in alphabetical order and does not represent any recommendation:

* DoesNothingStrategy (Author: Gert Wohlgemuth, https://github.com/freqtrade/freqtrade-strategies)
* MultiMA_TSL (Author: stash86, https://github.com/stash86/MultiMA_TSL/)
* NostalgiaForInfinityX (Author: iterativ, https://github.com/iterativv/NostalgiaForInfinity)

Help expanding the strategies list and include config files if possible: [freqstart.strategies.json](https://github.com/berndhofer/freqstart/blob/develop/freqstart.strategies.json)

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- DISCLAIMER -->
## Disclaimer
 
This software is for educational purposes only. Do not risk money which you are afraid to lose. USE THE SOFTWARE AT YOUR OWN RISK. THE AUTHORS AND ALL AFFILIATES ASSUME NO RESPONSIBILITY FOR YOUR TRADING RESULTS.

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- GETTING STARTED -->
## Getting Started

Freqstart provides an interactive setup guide for server security, Freqtrade incl. config creation, FreqUI, Binance- & Kucoin-Proxy routines.

### Prerequisites

`Warning` Freqstart installs server packages and configurations tailored to the needs of Freqtrade. It is recommended to set it up in a new and clean environment!

`Packages` git, curl, jq, docker-ce, chrony, nginx, certbot, python3-certbot-nginx, ufw, openssl

`Freqstart` is beeing developed and testet on Vultr "Tokyo" Server with `Ubuntu 22.04 x64`. Please open any issues with your specific OS.

`Performance` If you use more than three bots i recommend at least: AMD High Performance -> Tokyo -> 60GB NVMe/2 vCPUs

Try Vultr "Tokyo" Server and get $100 usage for free:<br/>
[https://www.vultr.com/?ref=9122650-8H](https://www.vultr.com/?ref=9122650-8H)

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
   freqstart --bot example.yml
   ```
2. Start a `Freqtrade` container, non-interactive
   ```sh
   freqstart --bot example.yml --yes
   ```
   
### Stop

1. Stop a `Freqtrade` container and disable autoupdate
   ```sh
   freqstart --bot example.yml --kill
   ```
2. Stop a `Freqtrade` container and disable autoupdate, non-interactive 
   ```sh
   freqstart --bot example.yml --kill --yes
   ```
   
### Autoupdate

1. Start a `Freqtrade` container with autoupdate (image, strategies etc.)
   ```sh
   freqstart --bot example.yml --auto
   ```
2. Start a `Freqtrade` container with autoupdate (image, strategies etc.), non-interactive
   ```sh
   freqstart --bot example.yml --auto --yes
   ```
   
### Reset (WARNING: Stopp and remove all containers, networks and images!)

   ```sh
   freqstart --reset
   ```
   
<p align="right">(<a href="#top">back to top</a>)</p>

<!-- EXAMPLE PROJECT -->
## Example Project (.yml)

### Project file with NostalgiaForInfinityX

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
         --config /freqtrade/user_data/kucoin_proxy.json
   ```

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- ROADMAP -->
## Roadmap

See the [open issues](https://github.com/berndhofer/freqstart/issues) for a full list of proposed features (and known issues).

### Changelog

`v0.1.8`
* Modified proxy network creation to be non-verbose.
* Removed frequi_cors config parameter since it is deprecated after integrating Nginx into FreqUI routine.
* Add hash to file creation function.
* Improved value get and update value from json and other files incl. set value in a temporary file.
* Changend docker manifest tmp filetype.
* Add validation of strategy path files incl. non-implemented strategies.

`v0.1.7`
* Fixed unbound variable in help function.
* Improved some function argument checks.
* Moved creation of docker proxy network to project routine.

`v0.1.6`
* Use docker start instead of recreating the project file and improved restart routine.
* Add containers docker network "freqstart_proxy" (No network needed in project file from v0.1.5).
* Start proxy container with fixed IP in subnet of "freqstart_proxy".
* Created a function to create files incl. sudo for permission and check if file exist. (Thanks: lsiem)
* Removed secret and key routine from Freqtrade confing creation (Most of the time the config has to be modified manually anyway).
* Improved argument check for functions.
* Changed expose to port redirect with localhost ip to proxy project files.
* Add docker network prune in project compose routine to remove orphaned networks.
* Add reset mode to stopp and remove all containers, networks and images.
* Improved check for nginx if is not installed.
* Fixed login data creation in FreqUI routine when no entries were made.
* Fixed scriptlock and cleanup routine.
* Add routine to check for root and suggest creating a user interactively incl. file transfer.
* Add routine to add current user to docker group.
* Fixed Nginx/FreqUI routing error (502).
* Improved Nginx routine for secured domain setup.

`v0.1.5`
* Add docker network policy to proxy project files and bot files (Workaround to use multiple docker project files).
* Removed example bot routine and add example to readme.
* Fixed FreqUI container name and restart policy.
* Update container to restart no before validation instead of manipulating the docker project file.
* Add remove orphan container to project compose routine.
* Fixed unbound variable in docker compose. (Thanks: lsiem)
* Fixed permission error in cleanup routine. (Thanks: lsiem)
* Add cron remove for letsencrypt cert in the nginx reconfiguration routine.
* Fixed domain validation error from host command.
* File creation routine to create path if it doesnt exist.

`v0.1.4`
* Changed docker vars name creation. WARNING: Existing/running containers may not be dedected correctly.
* Implemented kucoin proxy setup routine incl. reusable config.
* Rebuild binance proxy routine to docker compose.
* Fixed unbound variable in strategies check for yml files.
* Fixed unbound variable in configs check for yml files.
* Removed docker run function.
* Add trap ERR and function for handling errors.
* Fixed FreqUI docker ps check if container is active.
* Disabled port check for compose force mode.
* Split FreqUI and Nginx setup routine and made Nginx mandatory.
* Moved ufw installation from Nginx setup to prerequisites.
* Add LAN ip proxy forward for binance and kucoin proxies.

`v0.1.3`
* Rebuild script without template to remove overhead.
* Example bot config routine error fixed.

`v0.1.2`
* Strategy "MultiMA_TSL" add to strategies config.
* Countdown for validating container is set to 30s again.

`v0.1.1`
* Automated reissue of letsencrypt cert if used with Nginx proxy for FreqUI.
* Optional daily auto update for containers incl. implemented strategies with -a argument.

`v0.1.0`
* Update container conf strategy update only if container has been restarted.
* Improved starting routine and check for non-optional bot arguments.

`v0.0.9`
* Fixed error in comparing strategy files.
* Changed docker container validation routine.

`v0.0.8`
* Improved container strategy update verification routine.
* Improved "FreqUI" setup and added compose routine if container is running.
* Cleaned shellcheck warnings and some general improvements.

`v0.0.7`
* Implemented strategy update check for every container via project config file.
* Raised countdown to 30s to validate docker container.

`v0.0.6`
* Fixed an error in FreqUI routine with domain configuration.
* Rewrite project.yml restart to "no" and update restart to "on-failure" after validation.

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