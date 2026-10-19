{inputs, ...}: {
    serviceRegistry.navidrome = {
        web = {
            subdomain = "music";
            port = 4533;
            protect = true;
        };
        access = {
            oneFactorResources = ["^/rest/"];
            bypassResources = ["^/share/"];
        };
        dashboard = nixos: {
            name = "Navidrome";
            category = "Media";
            widget = {
                type = "navidrome";
                baseUrl = "http://${nixos.services.navidrome.settings.Address}:${toString nixos.services.navidrome.settings.Port}";
                user = "admin";
                tokenEnvVar = "NAVIDROME_TOKEN";
                saltEnvVar = "NAVIDROME_SALT";
            };
            widgetSecrets = {
                NAVIDROME_TOKEN.name = "navidrome/token";
                NAVIDROME_SALT.name = "navidrome/salt";
            };
            resourceUnits = ["navidrome.service"];
        };
    };

    den.aspects.navidrome.nixos = {
        config,
        pkgs,
        ...
    }: let
        plugins = inputs.unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.pkgsCross.wasi32.navidromePlugins;
        address = "127.0.0.1";
    in {
        services.navidrome = {
            enable = true;
            settings = {
                Address = address;
                Port = config.my.services.navidrome.port;
                EnableSharing = true;
                DefaultDownsamplingFormat = "opus";
                ExtAuth.TrustedSources = "${address}/32";
                LyricsPriority = ".ttml,.yaml,.yml,.elrc,.lrc,.srt,.txt,embedded,${plugins.lyrics-plugin.pname}";
            };
            plugins = with plugins; [
                lyrics-plugin
            ];
        };
    };
}
