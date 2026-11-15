{
    den.aspects.home-assistant.nixos = {
        lib,
        pkgs,
        ...
    }: let
        solplanet = pkgs.buildHomeAssistantComponent rec {
            owner = "zbigniewmotyka";
            domain = "solplanet";
            version = "0.8.1";

            src = pkgs.fetchFromGitHub {
                inherit owner;
                repo = "home-assistant-solplanet";
                tag = "v${version}";
                hash = "sha256-eDui9HBaNh8oBcTWM6/znqUUCOftojzwfaJTmKmRSVk=";
            };

            meta = {
                description = "Solplanet/AISWEI solar inverter integration for Home Assistant";
                homepage = "https://github.com/zbigniewmotyka/home-assistant-solplanet";
                license = lib.licenses.mit;
            };
        };
    in {
        config.services.home-assistant.customComponents = [solplanet];
    };
}
