{
    serviceRegistry."space-engineers" = {
        ports.udp = nixos: [nixos.my.games.space-engineers.port];
        dashboard = nixos: {
            name = "Space Engineers";
            category = "Games";
            widget = {
                inherit (nixos.my.games.space-engineers) port;
                type = "game-server";
                kind = "space-engineers";
                host = "127.0.0.1";
                manifestPath = "${nixos.my.games.space-engineers.dataDir}/SpaceEngineersDedicated/steamapps/appmanifest_298740.acf";
            };
            resourceUnits = ["podman-space-engineers.service"];
        };
        actions = [
            {
                id = "restart";
                label = "Restart";
                unit = "podman-space-engineers";
                verb = "restart";
            }
            {
                id = "stop";
                label = "Stop";
                unit = "podman-space-engineers";
                verb = "stop";
            }
        ];
    };

    den.aspects.space-engineers.nixos = {
        config,
        lib,
        ...
    }: let
        inherit (lib) mkOption types;
        cfg = config.my.games.space-engineers;
    in {
        options.my.games.space-engineers = {
            port = mkOption {
                type = types.int;
                default = 27016;
            };
            instanceName = mkOption {
                type = types.str;
                default = "default";
                description = "The name of the Space Engineers instance.";
            };
            dataDir = mkOption {
                type = types.str;
                default = "/var/lib/space-engineers";
                description = "The directory where Space Engineers stores its data.";
            };
        };
        config = let
            inherit (cfg) dataDir;
        in {
            virtualisation.oci-containers.containers.space-engineers = {
                image = "docker.io/devidian/spaceengineers:winestaging";
                ports = ["${toString cfg.port}:27016/udp"];
                environment = {
                    WINEDEBUG = "-all";
                    INSTANCE_NAME = cfg.instanceName;
                    PUBLIC_IP = "0.0.0.0";
                };
                volumes = [
                    "${dataDir}/plugins:/appdata/space-engineers/plugins"
                    "${dataDir}/instances:/appdata/space-engineers/instances"
                    "${dataDir}/SpaceEngineersDedicated:/appdata/space-engineers/SpaceEngineersDedicated"
                    "${dataDir}/steamcmd:/root/.steam"
                ];
                extraOptions = [
                    "--network=host"
                    "--memory=16g"
                    "--memory-swap=16g"
                    "--no-healthcheck"
                ];
            };

            systemd.tmpfiles.rules = [
                "d '${dataDir}' 0755 root root - -"
                "d '${dataDir}/plugins' 0755 root root - -"
                "d '${dataDir}/instances' 0755 root root - -"
                "d '${dataDir}/SpaceEngineersDedicated' 0755 root root - -"
                "d '${dataDir}/steamcmd' 0755 root root - -"
            ];
            systemd.services.hearth.serviceConfig.ReadOnlyPaths = ["${dataDir}/SpaceEngineersDedicated/steamapps/appmanifest_298740.acf"];
        };
    };

    den.aspects."space-engineers".readme = {
        title = "Space Engineers";
        intro = "Space Engineers dedicated server via Docker ([devidian/spaceengineers](https://hub.docker.com/r/devidian/spaceengineers)).";
        sections = [
            {
                title = "Usage";
                content = ''
                    1. Add the module to your `configuration.nix`:

                       ```nix
                       {
                           services.space-engineers = {
                               enable = true;
                               port = 27016;
                               instanceName = "default";
                               dataDir = "/var/lib/space-engineers";
                           };
                       }
                       ```

                    2. Set up the instance:
                       1. Setup a SE instance like explained [here](https://www.spaceengineersgame.com/dedicated-servers/)
                       2. Rename the `<LoadWorld>` value in the `SpaceEngineers-Dedicated.cfg` file to:

                          ```xml
                          <MyConfigDedicated>
                              ...
                              <LoadWorld>Z:\appdata\space-engineers\instances\default\Saves\[World Name]</LoadWorld>
                              <WorldName>[World Name]</WorldName>
                              ...
                          </MyConfigDedicated>
                          ```

                       3. Copy the instance into the `instances` directory:
                          > the Instance is located in `C:\Users\[User]\AppData\Roaming\SpaceEngineersDedicated`

                    3. Start the service:

                       ```sh
                       sudo systemctl start podman-space-engineers
                       ```
                '';
            }
            {
                title = "Fixing a broken / stuck server";
                content = ''
                    The container runs steamcmd on every start (app ID `298740`). If the server won't start, steamcmd's install manifest is usually corrupt. Symptoms in `journalctl -u podman-space-engineers`:

                    - `ERROR! Failed to install app '298740' (Missing configuration)`
                    - `Application could not be started` / `ShellExecuteEx failed: File not found`

                    **Fix (copy-paste, safe, reversible):**

                    ```sh
                    # 1. Delete the corrupt manifest (steamcmd rebuilds it from scratch)
                    sudo rm -f /var/lib/space-engineers/SpaceEngineersDedicated/steamapps/appmanifest_298740.acf

                    # 2. Restart 2-3 times. Each restart resumes the download; the
                    #    install is done when a pass prints "Success! App '298740' fully installed".
                    sudo systemctl restart podman-space-engineers
                    ```

                    Don't `podman exec` into the container - it auto-removes on exit, so edit files on the host under `/var/lib/space-engineers/` instead.

                    **Confirm it worked** - server is healthy once the manifest shows `StateFlags "4"` (fully installed) with a real size and build id:

                    ```sh
                    sudo grep -E 'StateFlags|SizeOnDisk|buildid' \
                      /var/lib/space-engineers/SpaceEngineersDedicated/steamapps/appmanifest_298740.acf
                    ```

                    A corrupt manifest reads `StateFlags "2"` with `SizeOnDisk "0"` and `buildid "0"`; a healthy one reads `StateFlags "4"` with the real byte count and a non-zero build id. A `state is 0x602` line mid-fix just means "still updating" - keep restarting.
                '';
            }
        ];
    };
}
