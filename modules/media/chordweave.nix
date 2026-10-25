{inputs, ...}: {
    flake-file.inputs.chordweave.url = "git+ssh://git@github.com/anders130/chordweave?ref=master";

    serviceRegistry.chordweave = {
        web.subdomain = "chordweave";
        dashboard = nixos: {
            name = "Chordweave";
            icon = "${nixos.my.services.chordweave.url}/icon.svg";
            category = "Media";
            widget = {
                type = "custom";
                baseUrl = "${nixos.my.services.chordweave.url}/api/songs";
                mappings = [
                    {
                        path = "";
                        label = "Songs";
                        format = "count";
                    }
                ];
            };
            resourceUnits = ["chordweave-api.service" "chordweave-app.service"];
        };
        oidc = {
            redirectUris = nixos: ["${nixos.my.services.chordweave.url}/api/auth/callback"];
            scopes = ["openid" "profile" "email"];
            clientSettings.token_endpoint_auth_method = "client_secret_post";
            nixos = {config, ...}: let
                cfgOidc = config.my.services.chordweave.oidc;
            in {
                services.chordweave.oidc = {
                    enable = true;
                    issuerUrl = cfgOidc.issuerUrl;
                    clientSecretFile = config.sops.secrets."chordweave/oidc_client_secret".path;
                    redirectUri = "${config.my.services.chordweave.url}/api/auth/callback";
                };
                systemd.services.chordweave-api = {
                    after = ["authelia-main-gen-oidc.service"];
                    requires = ["authelia-main-gen-oidc.service"];
                };
            };
        };
        access = {};
    };

    den.aspects.chordweave.nixos = {config, ...}: let
        svc = config.my.services.chordweave;
    in {
        imports = [inputs.chordweave.nixosModules.chordweave];

        services.chordweave = {
            enable = true;
            api.port = 8788;
            app.port = 8787;
        };

        my.services.caddy.virtualHosts.${svc.fqdn}.extraConfig = ''
            handle /api/* {
                reverse_proxy 127.0.0.1:${toString config.services.chordweave.api.port}
            }
            handle {
                reverse_proxy 127.0.0.1:${toString config.services.chordweave.app.port}
            }
        '';
    };
}
