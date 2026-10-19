{
    serviceRegistry.hytale = {
        ports.udp = nixos: [nixos.my.games.hytale.port];
        dashboard = nixos: {
            name = "Hytale";
            category = "Games";
            widget = {
                type = "game-server";
                kind = "hytale";
                statusUrl = "${nixos.services.gameStatusHttp.baseUrl}/podman-hytale";
            };
            resourceUnits = ["podman-hytale.service"];
        };
        actions = [
            {
                id = "restart";
                label = "Restart";
                unit = "podman-hytale";
                verb = "restart";
            }
            {
                id = "stop";
                label = "Stop";
                unit = "podman-hytale";
                verb = "stop";
            }
        ];
    };

    den.aspects.hytale.nixos = {
        config,
        lib,
        ...
    }: let
        cfg = config.my.games.hytale;
        workDir = "/var/lib/hytale";
    in {
        options.my.games.hytale.port = lib.mkOption {
            type = lib.types.port;
            default = 5520;
        };

        config = {
            virtualisation.oci-containers.containers.hytale = {
                image = "indifferentbroccoli/hytale-server-docker";
                environment = {
                    DEFAULT_PORT = toString cfg.port;
                    ENABLE_BACKUPS = "TRUE";
                    SERVER_NAME = "NixOS Hytale Server";
                    MAX_MEMORY = "8G";
                    PATCHLINE = "release";
                };
                volumes = [
                    "/var/lib/hytale/data:/home/hytale/server-files"
                ];
                extraOptions = [
                    "--tty"
                    "--stop-timeout=30"
                ];
                autoStart = false;
                user = "root:root";
                ports = ["${toString cfg.port}:5520/udp"];
            };
            systemd.tmpfiles.settings."50-hytale"."${workDir}/data".d = {
                user = "1000";
                group = "1000";
                mode = "0755";
            };
        };
    };

    den.aspects.hytale.readme = {
        title = "Hytale";
        intro = "Dedicated **Hytale Server** using the Docker image from [indifferentbroccoli/hytale-server-docker](https://github.com/indifferentbroccoli/hytale-server-docker).";
        sections = [
            {
                title = "Initial Setup & Authentication";
                content = ''
                    The Hytale dedicated server requires two authentication steps:

                    1. Authenticating the server download
                    2. Authenticating the server instance itself

                    ### 1. Authenticating the Server Download

                    After enabling the module, start the service:

                    ```bash
                    systemctl start podman-hytale.service
                    ```

                    Then:

                    1. Open the logs of the service:

                    ```bash
                    journalctl -u podman-hytale.service -f
                    ```

                    2. Copy the authentication URL shown in the logs
                    3. Open the URL in your browser
                    4. Log in with your Hytale account
                    5. Return to the terminal and wait for the download to complete

                    ### 2. Authenticating the Server Instance

                    Once the download has finished, attach to the running container:

                    ```bash
                    podman attach hytale
                    ```

                    Inside the container console, authenticate the server:

                    ```bash
                    /auth login device
                    ```

                    Follow the instructions shown in the terminal.

                    #### Persist the Authentication Token

                    To ensure authentication persists across rebuilds and restarts, run:

                    ```bash
                    /auth persist Encrypted
                    ```

                    After this step, the server can be restarted without re-authentication.
                '';
            }
        ];
    };
}
