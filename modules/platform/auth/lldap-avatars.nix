{
    den.aspects.lldap.nixos = {
        config,
        pkgs,
        lib,
        ...
    }: let
        svc = config.my.services.lldap;
        avatarDir = "/var/lib/lldap-avatars";
        lldapUrl = "http://127.0.0.1:${toString svc.port}";

        # LLDAP has no HTTP route serving jpegPhoto; publish it as a static
        # file and write the URL back as a custom "avatarUrl" attribute.
        exportScript = pkgs.writeShellApplication {
            name = "lldap-export-avatars";
            runtimeInputs = [pkgs.curl pkgs.jq];
            text = ''
                PASSWORD=$(cat ${config.sops.secrets."lldap/admin_password".path})
                TOKEN=$(curl -sf -X POST "${lldapUrl}/auth/simple/login" \
                    -H "Content-Type: application/json" \
                    -d "{\"username\":\"admin\",\"password\":\"$PASSWORD\"}" | jq -r .token)

                gql() {
                    curl -sf "${lldapUrl}/api/graphql" \
                        -H "Authorization: Bearer $TOKEN" \
                        -H "Content-Type: application/json" \
                        -d "$1"
                }

                # One-time schema setup; fails harmlessly once it already exists.
                gql '{"query":"mutation { addUserAttribute(name: \"avatarUrl\", attributeType: STRING, isList: false, isVisible: true, isEditable: false) { ok } }"}' \
                    > /dev/null 2>&1 || true

                gql '{"query":"{ users { id avatar } }"}' \
                    | jq -r '.data.users[] | select(.avatar != null and .avatar != "") | [.id, .avatar] | @tsv' \
                    | while IFS=$'\t' read -r id avatar; do
                        printf '%s' "$avatar" | base64 -d > "${avatarDir}/$id.jpg"
                        url="${svc.url}/avatars/$id.jpg"
                        payload=$(jq -n --arg id "$id" --arg url "$url" \
                            '{query: "mutation($id: String!, $url: String!) { updateUser(user: {id: $id, insertAttributes: [{name: \"avatarUrl\", value: [$url]}]}) { ok } }", variables: {id: $id, url: $url}}')
                        gql "$payload" > /dev/null
                    done
            '';
        };
    in {
        systemd.tmpfiles.rules = [
            "d ${avatarDir} 0755 root root -"
        ];

        systemd.services.lldap-export-avatars = {
            description = "Publish LLDAP user avatars as static files and their URL into LDAP";
            after = ["lldap.service"];
            requires = ["lldap.service"];
            serviceConfig = {
                Type = "oneshot";
                ExecStart = lib.getExe exportScript;
            };
        };

        systemd.timers.lldap-export-avatars = {
            description = "Periodically refresh LLDAP avatar exports";
            wantedBy = ["timers.target"];
            timerConfig = {
                OnBootSec = "1m";
                OnUnitActiveSec = "15m";
            };
        };

        my.services.caddy.virtualHosts.${svc.fqdn}.extraConfig = ''
            handle_path /avatars/* {
                root * ${avatarDir}
                file_server
            }
        '';
    };
}
