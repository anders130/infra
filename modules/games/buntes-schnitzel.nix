{inputs, ...}: {
    flake-file.inputs.buntes-schnitzel.url = "git+ssh://git@github.com/kale-collective/buntes-schnitzel";
    serviceRegistry.buntes-schnitzel = {
        web = {
            subdomain = "buntes-schnitzel";
            port = 3001;
        };
        dashboard = {
            name = "Buntes Schnitzel";
            category = "Games";
            widget = {type = "link";};
        };
    };
    den.aspects.buntes-schnitzel.nixos = {config, ...}: {
        imports = [inputs.buntes-schnitzel.nixosModules.default];
        nixpkgs.overlays = [inputs.buntes-schnitzel.overlays.default];
        services.buntes-schnitzel = {
            inherit (config.my.services.buntes-schnitzel) port;
            enable = true;
        };
    };
}
