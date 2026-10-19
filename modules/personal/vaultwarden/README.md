# Vaultwarden

Self-hosted [Bitwarden](https://bitwarden.com)-compatible password manager.

## Dependencies

- [caddy](/modules/platform/caddy.nix)
- [sops](/modules/platform/sops)

## Usage

```nix
den.aspects.<host>.includes = with den.aspects; [vaultwarden];
networking.domain = "example.com"; # serves at vault.example.com
my.services.vaultwarden.backupDir = "/path/to/backup"; # optional
```

## Secrets

Edit the secrets file:

```bash
sops hosts/ds1/secrets/vaultwarden.env
```

Update keys after adding a new device:

```bash
sops updatekeys hosts/ds1/secrets/vaultwarden.env
```

### ADMIN_TOKEN

```bash
nix shell nixpkgs#libargon2 nixpkgs#openssl --command \
    sh -c 'echo -n "YourPassword" | argon2 "$(openssl rand -base64 32)" -e -id -k 19456 -t 2 -p 1'
```
