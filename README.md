# 4sds84-New-XrayR

Mirror of official XrayR v0.9.4 Linux release assets.

Source release:

https://github.com/XrayR-project/XrayR/releases/tag/v0.9.4

## Install

Run as root on the VPS:

```bash
wget -N https://raw.githubusercontent.com/fastincc/4sds84-New-XrayR/main/install.sh && bash install.sh
```

Install a specific version:

```bash
wget -N https://raw.githubusercontent.com/fastincc/4sds84-New-XrayR/main/install.sh && bash install.sh v0.9.4
```

Install and also install acme.sh:

```bash
wget -N https://raw.githubusercontent.com/fastincc/4sds84-New-XrayR/main/install.sh && INSTALL_ACME=1 bash install.sh v0.9.4
```

## Notes

- The installer keeps `/etc/XrayR/config.yml` when it already exists.
- The installer replaces `/usr/local/XrayR` and backs up the old directory as `/usr/local/XrayR.bak.YYYYMMDDHHMMSS`.
- The real binary is `/usr/local/XrayR/XrayR`.
- The management command is `/usr/bin/XrayR`, with `/usr/bin/xrayr` as a lowercase alias.
- For V2Board 1.7.2 route management, use `PanelType: "NewV2board"` and check node `NodeType` compatibility.
