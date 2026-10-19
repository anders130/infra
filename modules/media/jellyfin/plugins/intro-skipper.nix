{lib, ...}: {
    den.aspects.jellyfin.nixos = {
        config,
        pkgs,
        ...
    }: let
        jellyfinLib = import ../_lib.nix {inherit pkgs;};
        jf = config.services.jellyfin;
        version = "12.0.4.0";
        drv = jellyfinLib.mkPluginDrv {
            pname = "intro-skipper";
            inherit version;
            guid = "c83d86bb-a1e0-4c35-a113-e2101cf4ee6b";
            jellyfinPackage = jf.package;
            # No meta.json is bundled in the release zip -- it's normally
            # written by Jellyfin's own repository-install flow instead.
            extraMeta.name = "Intro Skipper";
            zip = pkgs.fetchurl {
                url = "https://github.com/intro-skipper/intro-skipper/releases/download/12.0/v${version}/intro-skipper-v${version}.zip";
                sha256 = "11d7bb171b66a4faa4abb0d9af92d2e9e6ae3ebd6a821bb5aca1d94bff651439";
            };
        };
        install = jellyfinLib.installPlugin {
            inherit jf version drv;
            folderPrefix = "IntroSkipper";
        };
    in {
        systemd.tmpfiles.rules = install.tmpfilesRules;
        systemd.services.jellyfin.preStart = lib.mkAfter install.preStart;
    };
}
