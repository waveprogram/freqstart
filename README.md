<div id="top"></div>

<!-- FREQSTART -->
# FREQSTART v3.0.6

See what has been changed: <a href="#changelog">Changelog</a>

## Setup & Docker-Manager for Freqtrade

Freqstart simplifies the use of Freqtrade with Docker. Including a simple setup guide for Freqtrade,
configurations and FreqUI with a secured SSL proxy and Tailscale (VPN). Freqstart also automatically
installs implemented strategies based on Docker Compose files and detects necessary updates.

Freqstart is the combined public knowledge, based on best practice solutions, to run Freqtrade
in the most secure environment possible. Every step can be done manually and even if you decide
to remove Freqstart, you can start and stop your project files with native Docker commands.

IF YOU ARE NOT FAMILIAR WITH FREQTRADE, PLEASE READ THE COMPLETE DOCUMENTATION FIRST ON: [www.freqtrade.io](https://www.freqtrade.io/)

For `Freqstart` related questions, use die github issue list: [open issues](https://github.com/freqstart/freqstart/issues)

For `Freqtrade` related questions, join the official discord: https://discord.gg/g549bRAy

### Features

* `Freqtrade` Guided setup for Docker projects.
* `Docker` Version check of images via manifest using minimal ressources.
* `Prerequisites` Install server prerequisites and updates.
* `FreqUI` Full setup of FreqUI incl. Nginx proxy and Tailscale (VPN).
* `Binance Proxy` Setup for Binance proxy incl. reusable config file.
* `Kucoin Proxy` Setup for Kucoin proxy incl. reusable config file.
* `Strategies` Automated installation of implemented strategies incl. updates.

### Strategies

The following list of implemented strategies is in alphabetical order and does not represent any recommendation:

* `Cenderawasih_3` (Author: stash86, Source: https://github.com/stash86/MultiMA_TSL/)
* `Cenderawasih_3_kucoin` (Author: stash86, Source: https://github.com/stash86/MultiMA_TSL/)
* `DoesNothingStrategy` (Author: Gert Wohlgemuth)
* `MultiMA_TSL` (Author: stash86, Source: https://github.com/stash86/MultiMA_TSL/)
* `MultiMA_TSL5` (Author: stash86, Source: https://github.com/stash86/MultiMA_TSL/)
* `NASOSv4` (Author: Rallipanos, pluxury)
* `NASOSv5` (Author: Rallipanos, pluxury)
* `NostalgiaForInfinityNext_7_13_0` (Author: iterativ, Source: https://github.com/iterativv/NostalgiaForInfinity)
* `NostalgiaForInfinityX` (Author: iterativ, Source: https://github.com/iterativv/NostalgiaForInfinity)

Help expanding the strategies list and include config files if possible: [freqstart_strategies.json](https://raw.githubusercontent.com/freqstart/freqstart/stable/freqstart_strategies.json)

Optional: Add freqstart_strategies_custom.json to script root and add your own URLs from other sources.

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- GETTING STARTED -->
## Getting Started

Freqstart provides an interactive setup guide for server security, Freqtrade incl. config creation, FreqUI, Binance- & Kucoin-Proxy routines.

### Prerequisites

Freqstart installs server packages and configurations tailored to the needs of Freqtrade and may overwrite existing installations and configurations. It is recommended to set it up in a new and clean environment!

Packages: curl, jq, openssl, docker-ce, docker-compose, docker-ce-rootless-extras, systemd-container, uidmap, dbus-user-session

### Recommended VPS

If you take crypto bot trading seriously, never use a VPS with only one core. Freqtrade doesn't use multithreading, but with CPU-heavy strategies like NFIX, your VPS would be at almost 100% capacity every time. It is also recommended to add 1 CPU core per bot. So if you are running 3 different strategies, you should have at least 4 CPU cores to have some buffer for other system tasks. Additionally, install bashtop ($ sudo apt install bashtop), set the timing to 30,000ms and see how long it takes your VPS to finish calculating a new trade candle from 100% to below 20% within 10 bars (= 5 minutes) per core. A good benchmark for NFIX would be 2 minutes, which equals 4 bars. Anything higher or consistently above 90% risks losing you money or never getting a trade entry. Don't be too cheap on your way to the moon, or you'll probably end up in goblin town anyway.

HostHatch (NVMe 4GB & 16GB / Hong Kong / Ubuntu LTS): [hosthatch.com](https://cloud.hosthatch.com/a/2781)

Vultr (Intel High Frequency 2 Core / Tokyo / Ubuntu LTS): [vultr.com](https://www.vultr.com/?ref=9122650-8H)

#### Test VPS latency

How to test latency to Binance exchange from your VPS (Ping will not work because Binance is using Cloudflare CDN):

`time curl -X GET "https://api.binance.com/api/v3/exchangeInfo?symbol=BNBBTC"`

### Setup `Freqstart`

   Clone the repo
   ```sh
   git clone https://github.com/freqstart/freqstart.git
   ```
   Change directory to `freqstart`
   ```sh
   cd ~/freqstart
   ```
   Make `freqstart.sh` executable
   ```sh
   sudo chmod +x freqstart.sh
   ```
   Setup `freqstart`
   ```sh
   ./freqstart.sh
   ```

### Update `Freqstart` script and strategies file

   ```sh
   freqstart --update
   ```

### Start `Freqtrade` docker projects

   ```sh
   freqstart
   ```

### Stop `Freqtrade` docker projects

   ```sh
   freqstart --quit
   ```

### Reset all `Freqtrade` docker projects incl. containers and networks

   ```sh
   freqstart --reset
   ```

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- EXAMPLE PROJECT -->
## Project

With Freqstart you are no longer bound to a single docker-compose.yml and can freely structure and link your Freqtrade bots.

* Have multiple container (services) in one project file
* Have a single container (service) in multiple project files
* Have multiple container (services) in multiple project files

### Example Docker Project

* Project file based on NostalgiaForInfinityX and Binance (BUSD) with Proxy and FreqUI enabled.

   ```yml
   version: '3'
   services:
     example_dryrun:
       image: freqtradeorg/freqtrade:stable
       volumes:
         - "./user_data:/freqtrade/user_data"
       command: >
         trade
         --dry-run
         --db-url sqlite:////freqtrade/user_data/example_dryrun.sqlite
         --logfile /freqtrade/user_data/logs/example_dryrun.log
         --strategy NostalgiaForInfinityX
         --strategy-path /freqtrade/user_data/strategies/NostalgiaForInfinityX
         --config /freqtrade/user_data/config.json
         --config /freqtrade/user_data/strategies/NostalgiaForInfinityX/pairlist-volume-binance-busd.json
         --config /freqtrade/user_data/strategies/NostalgiaForInfinityX/blacklist-binance.json
         --config /freqtrade/user_data/freqstart_frequi.json
         --config /freqtrade/user_data/freqstart_binance.json
   ```

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- ROADMAP -->
## Roadmap

See the [open issues](https://github.com/freqstart/freqstart/issues) for a full list of proposed features (and known issues).

### Changelog
`v3.0.6`
* Implemented Tailscale (VPN) setup routine.
* Implemented FreqUI setup routine based on Tailscale IP v4 incl. Openssl and secured Nginx ratelimit config.
* Redesigned setup validation of all functions and console output.
* Fixed strategy function jq error if strategy only has one file.
* Removed debug option.

`v3.0.5`
* Fixed wrong response in update routine.
* Added setup option and related functions.
* Removed unattended server upgrades from prerequisites.

`v3.0.4`
* Optimized project compose and quit routines incl. auto update.
* Removed strategies config download from project strategies routine and added to prerequisites and script update.

`v3.0.3`
* Auto update now only adds projects to crontab when every container inside has been sucessfully validated.
* Update changed to once a day. Reset crontab ($ crontab -r) and run script again.

`v3.0.2`
* Improved project routine to disable auto restart for non-started or stopped projects.

`v3.0.1`
* Improved download routine.
* Implemented script update option.

`v3.0.0`
* Granted the permission from original author to continue further development.

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- SUPPORT -->
## Support

You can contribute by donating to the following wallets:

* `BTC` 1M6wztPA9caJbSrLxa6ET2bDJQdvigZ9hZ
* `ETH` 0xb155f0F64F613Cd19Fb35d07D43017F595851Af5
* `BSC` 0xb155f0F64F613Cd19Fb35d07D43017F595851Af5

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- DISCLAIMER -->
## Disclaimer
 
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.