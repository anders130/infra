# Obsidian LiveSync

CouchDB for the [Self-hosted LiveSync](https://github.com/vrtmrz/obsidian-livesync) plugin. Vaults sync with per-person non-admin accounts, not the server admin.

## Dependencies

- [caddy](/modules/platform/caddy.nix)
- [sops](/modules/platform/sops)

## Accounts and vaults

Live in CouchDB, not in Nix -- no rebuild needed. Run on the host as root:

```bash
sudo obsidian-livesync-user add <user> <database>     # account + database
sudo obsidian-livesync-user grant <user> <database>   # another database, password untouched
sudo obsidian-livesync-user passwd <user>
sudo obsidian-livesync-user remove <user>
sudo obsidian-livesync-user reset <database>          # wipe and recreate
sudo obsidian-livesync-user list
```

## Connecting the plugin

Enter the remote settings, let the plugin complain that the connection
fails, then hit **Start LiveSync anyway** in its settings. It works.

The complaint is its config check reading `/_node/_local/_config`, which
is admin-only and never passes for a non-admin account.
