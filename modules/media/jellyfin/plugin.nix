{lib, ...}: {
    den.aspects.jellyfin.nixos = {
        config,
        pkgs,
        ...
    }: let
        inherit (lib) mkOption types;
        jf = config.services.jellyfin;
        plugins = config.my.services.jellyfin.plugins;

        targetAbi = let
            parts = lib.splitString "." jf.package.version;
        in
            lib.concatStringsSep "." (parts ++ lib.genList (_: "0") (4 - lib.length parts));

        folder = plugin: "${jf.dataDir}/plugins/${plugin.folderPrefix}_${plugin.version}";

        drv = pname: plugin: let
            fallbackMeta = pkgs.writeText "meta-${pname}.json" (builtins.toJSON {
                inherit (plugin) guid version name;
                inherit targetAbi;
                status = "Active";
            });
        in
            pkgs.runCommand "jellyfin-plugin-${pname}-${plugin.version}" {nativeBuildInputs = [pkgs.unzip pkgs.jq];} ''
                mkdir -p $out
                unzip ${plugin.zip} -d $out
                if [ -f $out/meta.json ]; then
                    jq '. + {status: "Active"}' $out/meta.json > $out/meta.json.tmp
                    mv $out/meta.json.tmp $out/meta.json
                else
                    cp ${fallbackMeta} $out/meta.json
                fi
            '';
    in {
        options.my.services.jellyfin.plugins = mkOption {
            type = types.attrsOf (types.submodule ({name, ...}: {
                options = {
                    name = mkOption {
                        type = types.str;
                        default = name;
                        description = "Display name written to a fallback meta.json when the release zip ships none.";
                    };
                    version = mkOption {type = types.str;};
                    guid = mkOption {type = types.str;};
                    folderPrefix = mkOption {type = types.str;};
                    zip = mkOption {type = types.package;};
                };
            }));
            default = {};
        };

        config.systemd = {
            tmpfiles.rules =
                ["d ${jf.dataDir}/plugins 0755 ${jf.user} ${jf.group} -"]
                ++ lib.mapAttrsToList (pname: plugin: "C+ ${folder plugin} 0755 ${jf.user} ${jf.group} - ${drv pname plugin}") plugins;
            services.jellyfin.preStart =
                plugins
                |> lib.mapAttrsToList (_: plugin: ''
                    find ${jf.dataDir}/plugins -maxdepth 1 -name '${plugin.folderPrefix}_*' ! -name '${plugin.folderPrefix}_${plugin.version}' -exec rm -rf {} +
                    chmod -R u+w ${folder plugin}
                '')
                |> map lib.mkAfter
                |> lib.mkMerge;
        };
    };
}
