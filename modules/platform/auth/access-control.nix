{
    config,
    inputs,
    ...
}: let
    flake = config;
in {
    config.flake-file.inputs.authelia-access-control = {
        url = "git+ssh://forgejo@git.gollub.dev:2222/jesse/authelia-access-control.git";
        inputs = {
            flake-parts.follows = "flake-parts";
            import-tree.follows = "import-tree";
            nixpkgs.follows = "nixpkgs";
        };
    };

    config.den.aspects.access-control.nixos = {
        config,
        lib,
        ...
    }: let
        acCfg = config.my.services.accessControl;

        accessServices = lib.filterAttrs (_: svc: svc.access != null) flake.serviceRegistry;

        allHostConfigs = lib.mapAttrsToList (_: hostCfg: hostCfg.config) inputs.self.nixosConfigurations;
        domainFor = svcName: let
            match = lib.findFirst (c: (c.my.services or {}) ? ${svcName}) null allHostConfigs;
        in
            if match == null
            then throw "access-control: no host declares my.services.${svcName}"
            else match.my.services.${svcName}.fqdn;

        allDashboardServices = lib.foldl' (acc: c: acc // c.my.dashboard.services) {} allHostConfigs;

        hasLoginBoundary = svcName: let
            svc = flake.serviceRegistry.${svcName} or null;
        in
            svc != null && (svc.web != null || svc.oidc != null);

        actionOnlyServices = lib.filterAttrs (svcName: svc: svc.actions != [] && !(hasLoginBoundary svcName)) allDashboardServices;

        computedServices =
            (lib.mapAttrs (svcName: svc: {
                domain = domainFor svcName;
                mechanism =
                    if svc.web.protect or false
                    then "forward-auth"
                    else "oidc-client";
                defaultAllow =
                    if svc.access.allow != null
                    then svc.access.allow
                    else acCfg.defaultAllow;
                defaultAdmin =
                    if svc.access.admin != null
                    then svc.access.admin
                    else acCfg.defaultAdmin;
                inherit (svc.access) oneFactorResources bypassResources;
            })
            accessServices)
            // (lib.mapAttrs (_: _: {
                domain = "";
                mechanism = "action-only";
                defaultAllow = acCfg.defaultAllow;
                defaultAdmin = acCfg.defaultAdmin;
            })
            actionOnlyServices);
    in {
        imports = [inputs.authelia-access-control.nixosModules.authelia-access-control];

        options.my.services.accessControl = {
            defaultAllow = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [];
                description = "Nix-level fallback when a service has no access.allow of its own. Real group/user names belong live via access-ctl grant-default, not here.";
            };
            defaultAdmin = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [];
            };
        };

        config = {
            services.authelia-access-control = {
                enable = true;
                services = computedServices;
            };

            services.authelia.instances.main.settingsFiles = [
                "${config.services.authelia-access-control.outputDir}/access-control.yaml"
                "${config.services.authelia-access-control.outputDir}/authorization-policies.yaml"
            ];
        };
    };
}
