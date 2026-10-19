{
    den.aspects.matrix.nixos = {
        config,
        pkgs,
        ...
    }: let
        baseDomain = config.networking.domain;
        livekitDomain = "livekit.${baseDomain}";
        rtcJwtDomain = "lk-jwt-service.${baseDomain}";
        turnDomain = "turn.${baseDomain}";
        livekitKeyFile = "/var/lib/livekit/livekit.key";
    in {
        sops.secrets."matrix/coturn-secret" = {
            owner = "turnserver";
            group = "matrix-synapse";
            mode = "0440";
            sopsFile = config.my.secretFiles.matrix;
        };

        services = {
            coturn = {
                enable = true;
                no-cli = true;
                no-tcp-relay = true;
                min-port = 50256;
                max-port = 65535;
                use-auth-secret = true;
                static-auth-secret-file = config.sops.secrets."matrix/coturn-secret".path;
                realm = turnDomain;
                extraConfig = ''
                    fingerprint
                    total-quota=0
                    bps-capacity=0
                    stale-nonce
                    no-loopback-peers
                    no-multicast-peers
                '';
            };

            livekit = {
                enable = true;
                openFirewall = true;
                settings = {
                    port = 7880;
                    room.auto_create = false;
                    rtc = {
                        tcp_port = 7881;
                        port_range_start = 50000;
                        port_range_end = 50255;
                        use_external_ip = true;
                    };
                };
                keyFile = livekitKeyFile;
            };

            lk-jwt-service = {
                enable = true;
                livekitUrl = "wss://${livekitDomain}";
                keyFile = livekitKeyFile;
                port = 8081;
            };

            matrix-synapse = {
                extraConfigFiles = [config.sops.secrets."matrix/coturn-secret".path];
                settings = {
                    turn_uris = [
                        "turn:${turnDomain}:3478?transport=udp"
                        "turn:${turnDomain}:3478?transport=tcp"
                    ];
                    experimental_features = {
                        msc3266_enabled = true;
                        msc4222_enabled = true;
                        msc4140_enabled = true;
                    };
                    max_event_delay_duration = "24h";
                };
            };
        };

        systemd.services = {
            livekit-key = {
                description = "Generate LiveKit Key";
                before = ["lk-jwt-service.service" "livekit.service"];
                wantedBy = ["multi-user.target"];
                path = with pkgs; [livekit coreutils gawk];
                script = ''
                    mkdir -p $(dirname ${livekitKeyFile})
                    if [ ! -f ${livekitKeyFile} ]; then
                        echo "Key missing, generating key"
                        echo "lk-jwt-service: $(livekit-server generate-keys | tail -1 | awk '{print $3}')" > "${livekitKeyFile}"
                        chgrp livekit "${livekitKeyFile}"
                        chmod 640 "${livekitKeyFile}"
                    fi
                '';
                serviceConfig.Type = "oneshot";
            };

            lk-jwt-service.environment.LIVEKIT_FULL_ACCESS_HOMESERVERS = baseDomain;
        };

        networking.firewall = {
            allowedTCPPorts = [3478 3479 5349 5350 7881];
            allowedUDPPorts = [3478 3479 5349 5350];
            allowedUDPPortRanges = [
                {
                    from = 49152;
                    to = 65535;
                }
            ];
        };

        my.services.caddy.virtualHosts = {
            "${livekitDomain}" = {
                port = 7880;
                headers = "flush_interval -1";
            };
            "${rtcJwtDomain}".port = config.services.lk-jwt-service.port;
        };
    };
}
