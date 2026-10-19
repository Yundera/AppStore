# Yundera AppStore

## About
The official curated app store for [Yundera](https://yundera.com) Personal Cloud Servers (PCS).
Each app is a Docker Compose project that **Maison**, the PCS dashboard, installs and keeps up
to date. Every app is reachable over HTTPS by default through Caddy, at addresses like
`https://memos-alice.nsl.sh`, and can sit behind the PCS's single sign-on.

The store uses the CasaOS store layout, and every app carries an `x-casaos` block, so it also
loads in CasaOS. Maison reads each app's `x-compose-app` manifest.

## Using the store
Maison lists this store by default. To add it by hand, add a store in **Settings → App stores**
with:

```
https://github.com/Yundera/AppStore/archive/refs/heads/main.zip
```

## Contributing
New apps and fixes are welcome:

1. Read [CONTRIBUTING.md](CONTRIBUTING.md), the requirements every app must pass (the review
   checklist), and [GUIDELINES.md](GUIDELINES.md), which explains how to meet them, how to test
   on a PCS, and the conventions every app follows.
2. Test your app on a PCS from your own fork of the store before opening a PR.
3. Check issues labelled `help wanted` for open requests.

## Sponsors
* **Yundera** - [yundera.com](https://yundera.com)
  Easy to use cloud server for open source container applications
* **NSL.SH** - [nsl.sh](https://nsl.sh)
  Free subdomain provider for open source projects

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
