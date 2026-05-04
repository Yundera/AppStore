# Yundera CasaOS 3rd-Party AppStore

## About
This AppStore provides a curated list of applications compatible with CasaOS running on Yundera servers. The apps are specifically configured to work with Caddy reverse proxy and nsl.sh free subdomains, accessible over HTTPS by default.

### Key Differences from Official CasaOS AppStore
Regular CasaOS app URL:
```http://demo.casaos.io:5230/```

Yundera app URL:
```https://memo-demo.nsl.sh```

All apps are designed to run on CasaIMG, a dockerized version of CasaOS.
All apps are accessible over HTTPS by default via Caddy reverse proxy.
All apps are tested on Yundera servers using nsl.sh routing domains.

## Related Projects
- [CasaIMG](https://github.com/yundera/casa-img) - Docker-based CasaOS image manager with Caddy integration

## Sponsors
* **Yundera** - [yundera.com](https://yundera.com)
  Easy to use cloud server for open source container applications
* **NSL.SH** - [nsl.sh](https://nsl.sh)
  Free subdomain provider for open source projects

## Contributing
We welcome contributions to help grow this AppStore:

1. Read our [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on submitting apps in Docker Compose format
2. **Important**: Test your submission thoroughly on a Yundera instance running CasaOS before creating a PR
3. Check issues labeled `help wanted` for specific areas needing assistance

## Contributors
<a href="https://github.com/yundera/AppStore/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=yundera/AppStore" />
</a>

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->
<!-- ALL-CONTRIBUTORS-LIST:END -->
