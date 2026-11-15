{
    den.aspects.jellyfin.nixos = {pkgs, ...}: {
        my.services.jellyfin.plugins.intro-skipper = rec {
            name = "Intro Skipper";
            version = "12.0.4.0";
            guid = "c83d86bb-a1e0-4c35-a113-e2101cf4ee6b";
            folderPrefix = "IntroSkipper";
            zip = pkgs.fetchurl {
                url = "https://github.com/intro-skipper/intro-skipper/releases/download/12.0/v${version}/intro-skipper-v${version}.zip";
                sha256 = "11d7bb171b66a4faa4abb0d9af92d2e9e6ae3ebd6a821bb5aca1d94bff651439";
            };
        };
    };
}
