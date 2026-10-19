{
    serviceRegistry.actual.oidc = {
        redirectUris = nixos: ["${nixos.my.services.actual.url}/openid/callback"];
        clientSettings = {
            token_endpoint_auth_method = "client_secret_basic";
            access_token_signed_response_alg = "none";
            userinfo_signed_response_alg = "none";
        };
        nixos = {config, ...}: let
            svc = config.my.services.actual;
            cfgOidc = svc.oidc;
        in {
            users.groups.actual = {};
            users.users.actual = {
                isSystemUser = true;
                group = "actual";
            };

            sops.secrets."actual/oidc_client_secret" = {
                owner = "actual";
                group = "actual";
            };

            services.actual = {
                user = "actual";
                group = "actual";
                settings.openId = {
                    discoveryURL = cfgOidc.issuerUrl;
                    client_id = cfgOidc.clientId;
                    client_secret._secret = config.sops.secrets."actual/oidc_client_secret".path;
                    server_hostname = svc.url;
                    authMethod = "oauth2";
                };
            };
        };
    };
}
