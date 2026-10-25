{pkgs}: let
    inherit (pkgs) lib;
    toAbiVersion = version: let
        parts = lib.splitString "." version;
    in
        lib.concatStringsSep "." (parts ++ lib.genList (_: "0") (4 - lib.length parts));
in {
    mkPluginDrv = {
        pname,
        version,
        guid,
        jellyfinPackage,
        zip,
        extraMeta ? {},
    }: let
        fallbackMeta = pkgs.writeText "meta-${pname}.json" (builtins.toJSON (extraMeta
        // {
            inherit guid version;
            name = extraMeta.name or pname;
            targetAbi = toAbiVersion jellyfinPackage.version;
            status = "Active";
        }));
    in
        pkgs.runCommand "jellyfin-plugin-${pname}-${version}" {nativeBuildInputs = [pkgs.unzip pkgs.jq];} ''
            mkdir -p $out
            unzip ${zip} -d $out
            if [ -f $out/meta.json ]; then
                jq '. + {status: "Active"}' $out/meta.json > $out/meta.json.tmp
                mv $out/meta.json.tmp $out/meta.json
            else
                cp ${fallbackMeta} $out/meta.json
            fi
        '';
    installPlugin = {
        jf,
        folderPrefix,
        version,
        drv,
    }: let
        folder = "${jf.dataDir}/plugins/${folderPrefix}_${version}";
    in {
        tmpfilesRules = [
            "d ${jf.dataDir}/plugins 0755 ${jf.user} ${jf.group} -"
            "C+ ${folder} 0755 ${jf.user} ${jf.group} - ${drv}"
        ];
        preStart = ''
            find ${jf.dataDir}/plugins -maxdepth 1 -name '${folderPrefix}_*' ! -name '${folderPrefix}_${version}' -exec rm -rf {} +
            chmod -R u+w ${folder}
        '';
    };
}
