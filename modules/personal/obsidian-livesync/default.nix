{
    serviceRegistry.obsidian-livesync = {
        web = {
            subdomain = "obsidian";
            port = 5984;
        };
        dashboard = nixos: {
            name = "Obsidian LiveSync";
            description = "CouchDB admin";
            icon = "couchdb";
            category = "Personal";
            href = "${nixos.my.services.obsidian-livesync.url}/_utils";
            visibility = "admin";
            widget.type = "link";
        };
    };

    den.aspects.obsidian-livesync.readme = {
        title = "Obsidian LiveSync";
        intro = "CouchDB for the [Self-hosted LiveSync](https://github.com/vrtmrz/obsidian-livesync) plugin. Vaults sync with per-person non-admin accounts, not the server admin.";
        sections = [
            {
                title = "Dependencies";
                content = ''
                    - [caddy](/modules/platform/caddy.nix)
                    - [sops](/modules/platform/sops)
                '';
            }
            {
                title = "Accounts and vaults";
                content = ''
                    Live in CouchDB, not in Nix -- no rebuild needed. Run on the host as root:

                    ```bash
                    sudo obsidian-livesync-user add <user> <database>     # account + database
                    sudo obsidian-livesync-user grant <user> <database>   # another database, password untouched
                    sudo obsidian-livesync-user passwd <user>
                    sudo obsidian-livesync-user remove <user>
                    sudo obsidian-livesync-user reset <database>          # wipe and recreate
                    sudo obsidian-livesync-user list
                    ```
                '';
            }
            {
                title = "Connecting the plugin";
                content = ''
                    Enter the remote settings, let the plugin complain that the connection
                    fails, then hit **Start LiveSync anyway** in its settings. It works.

                    The complaint is its config check reading `/_node/_local/_config`, which
                    is admin-only and never passes for a non-admin account.
                '';
            }
        ];
    };

    den.aspects.obsidian-livesync.nixos = {config, ...}: let
        svc = config.my.services.obsidian-livesync;
    in {
        sops.secrets.obsidian = {
            owner = config.services.couchdb.user;
            group = config.services.couchdb.group;
            mode = "440";
            sopsFile = config.my.secretFiles.obsidian-livesync;
            restartUnits = ["couchdb.service"];
        };
        services.couchdb = {
            inherit (svc) port;
            enable = true;
            configFile = config.sops.secrets.obsidian.path;
            extraConfig = {
                couchdb = {
                    single_node = true;
                    max_document_size = 50000000;
                };
                chttpd = {
                    require_valid_user = true;
                    max_http_request_size = 4294967296;
                    enable_cors = true;
                };
                chttpd_auth = {
                    require_valid_user = true;
                    authentication_redirect = "/_utils/session.html";
                };
                httpd = {
                    WWW-Authenticate = "Basic realm=\"couchdb\"";
                    enable_cors = true;
                };
                cors = {
                    origins = "app://obsidian.md,capacitor://localhost,http://localhost,https://localhost,capacitor://${svc.fqdn},http://${svc.fqdn},https://${svc.fqdn}";
                    credentials = true;
                    headers = "accept, authorization, content-type, origin, referer";
                    methods = "GET,PUT,POST,HEAD,DELETE";
                    max_age = 3600;
                };
            };
        };
    };
}
