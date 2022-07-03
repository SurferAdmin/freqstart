<div id="top"></div>

<!-- FREQSTART -->
# FREQSTART v0.1.3

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

Help expanding the strategies list and include config files if possible: [freqstart.strategies.json](https://github.com/berndhofer/freqstart/blob/develop/freqstart.strategies.json)

* DoesNothingStrategy (Author: Gert Wohlgemuth)
* MultiMA_TSL (Author: stash86)
* NostalgiaForInfinityX (Author: iterativ)

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- DISCLAIMER -->
## Disclaimer
 
This software is for educational purposes only. Do not risk money which you are afraid to lose. USE THE SOFTWARE AT YOUR OWN RISK. THE AUTHORS AND ALL AFFILIATES ASSUME NO RESPONSIBILITY FOR YOUR TRADING RESULTS.

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- GETTING STARTED -->
## Getting Started

Freqstart will install Freqtrade and the necessary NostalgiaForInfinity strategies and configs automatically.
With many more "QoL" features tailored to harness the power of Freqtrade and community tested extensions.

### Prerequisites

`Warning` Freqstart installs server packages and configurations tailored to the needs of Freqtrade. It is recommended to set it up in a new and clean environment!

`Packages` git, curl, jq, docker-ce, chrony, nginx, certbot, python3-certbot-nginx, ufw, openssl

`Freqstart` is beeing developed and testet on Vultr "Tokyo" Server with `Ubuntu 22.04 x64`. Please open any issues with your specific OS.

Get closer to Binance? Try Vultr "Tokyo" Server and get $100 usage for free:<br/>
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

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- ROADMAP -->
## Roadmap

See the [open issues](https://github.com/berndhofer/freqstart/issues) for a full list of proposed features (and known issues).

### Changelog

`v0.1.3`
* Rebuild script without template to remove overhead.
* Example bot config routine error fixed.

`v0.1.2`
* Strategy "MultiMA_TSL" added to strategies config.
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