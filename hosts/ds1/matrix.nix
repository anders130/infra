{
    den.aspects.ds1.nixos = {config, ...}: let
        domain = "matrix.${config.networking.domain}";
        baseDomain = config.networking.domain;
    in {
        my.services.caddy.virtualHosts."${baseDomain}".extraConfig =
            #caddy
            ''
                handle /.well-known/matrix/* {
                    header Access-Control-Allow-Origin "*"
                    header Content-Type "application/json"

                    @client path /.well-known/matrix/client
                    handle @client {
                        respond `{
                            "m.homeserver":{"base_url":"https://${domain}"},
                            "org.matrix.msc4143.rtc_foci": [
                                {
                                    "type": "livekit",
                                    "livekit_service_url": "https://lk-jwt-service.${baseDomain}"
                                }
                            ]
                        }`
                    }

                    @server path /.well-known/matrix/server
                    handle @server {
                        respond `{"m.server":"${domain}:443"}`
                    }
                }
            '';
    };
}
