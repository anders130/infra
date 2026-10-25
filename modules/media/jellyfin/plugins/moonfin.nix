{
    inputs,
    lib,
    ...
}: {
    den.aspects.jellyfin.nixos = {
        config,
        pkgs,
        ...
    }: let
        jellyfinLib = import ../_lib.nix {inherit pkgs;};
        jf = config.services.jellyfin;

        seerrCoLocatedPort = config.my.services.seerr.port or null;
        seerrHostConfig = lib.findFirst (c: (c.my.services.seerr.url or null) != null) null (
            lib.mapAttrsToList (_: hostCfg: hostCfg.config) inputs.self.nixosConfigurations
        );
        seerrUrl =
            if seerrCoLocatedPort != null
            then "http://127.0.0.1:${toString seerrCoLocatedPort}"
            else if seerrHostConfig != null
            then seerrHostConfig.my.services.seerr.url
            else null;
        version = "2.2.0.0";
        drv = jellyfinLib.mkPluginDrv {
            pname = "moonfin";
            inherit version;
            guid = "8c5d0e91-4f2a-4b6d-9e3f-1a7c8d9e0f2b";
            jellyfinPackage = jf.package;
            zip = pkgs.fetchurl {
                url = "https://github.com/Moonfin-Client/Plugin/releases/download/2.2.0/Moonfin.Server-${version}.zip";
                sha256 = "00fbc1637a1d1f47b4fbdc6483ab68d2f7887b87b0496af6cac205ea6b1a48a1";
            };
        };
        install = jellyfinLib.installPlugin {
            inherit jf version drv;
            folderPrefix = "Moonfin";
        };

        pluginConfigDir = "${jf.dataDir}/plugins/configurations";
        moonfinConfig = "${pluginConfigDir}/Moonfin.Server.xml";

        setSeerrUrl = pkgs.writeShellApplication {
            name = "jellyfin-moonfin-set-seerr-url";
            runtimeInputs = [pkgs.xmlstarlet];
            text =
                if seerrUrl == null
                then ''
                    echo "Moonfin: no Seerr instance found in the fleet, skipping Seerr integration config."
                ''
                else ''
                    mkdir -p ${pluginConfigDir}
                    if [ ! -f ${moonfinConfig} ]; then
                        printf '<?xml version="1.0" encoding="utf-8"?>\n<PluginConfiguration />\n' > ${moonfinConfig}
                    fi
                    xmlstarlet ed --inplace \
                        -d '/PluginConfiguration/SeerrEnabled' \
                        -d '/PluginConfiguration/SeerrUrl' \
                        -s '/PluginConfiguration' -t elem -n SeerrEnabled -v true \
                        -s '/PluginConfiguration' -t elem -n SeerrUrl -v "${seerrUrl}" \
                        ${moonfinConfig}
                    chown ${jf.user}:${jf.group} ${moonfinConfig}
                '';
        };
    in {
        systemd.tmpfiles.rules = install.tmpfilesRules;
        systemd.services.jellyfin.preStart = lib.mkAfter install.preStart;

        systemd.services.jellyfin-moonfin-set-seerr-url = {
            description = "Point Moonfin's Seerr integration at the local Seerr instance";
            before = ["jellyfin.service"];
            wantedBy = ["jellyfin.service"];
            serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = lib.getExe setSeerrUrl;
            };
        };

        systemd.services.jellyfin.bindsTo = ["jellyfin-moonfin-set-seerr-url.service"];
        systemd.services.jellyfin.after = ["jellyfin-moonfin-set-seerr-url.service"];
    };
}
