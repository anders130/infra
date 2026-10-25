{
    inputs,
    config,
    ...
}: let
    inherit (config) hostKeys;
in {
    den.aspects.forgejo.nixos = {
        config,
        pkgs,
        lib,
        ...
    }: let
        svc = config.my.services.forgejo;
        exe = "${config.services.forgejo.package}/bin/forgejo";
        tokenDir = "/var/lib/forgejo-actions-runner-token";
        tokenFile = "${tokenDir}/token.env";

        genTokenScript = pkgs.writeShellScript "forgejo-actions-runner-token" ''
            set -euo pipefail
            if [ ! -s ${tokenFile} ]; then
                TOKEN=$(${exe} actions generate-runner-token)
                printf 'TOKEN=%s\n' "$TOKEN" > ${tokenFile}
            fi
        '';

        deployKeyAgentSock = "/run/forgejo-deploy-agent/agent.sock";

        runnerName = config.networking.hostName;
    in {
        services.forgejo.settings.actions.ENABLED = true;

        users.groups.deploy-key-readers = {};
        sops.secrets."deploy/ssh_key" = {
            sopsFile = config.my.secretFiles.forgejo-deploy;
            group = "deploy-key-readers";
            mode = "0440";
        };

        systemd.services.forgejo-deploy-key-agent = {
            description = "SSH agent holding the Forgejo deploy key for CI";
            wantedBy = ["multi-user.target"];
            before = ["gitea-runner-${runnerName}.service"];
            requiredBy = ["gitea-runner-${runnerName}.service"];
            serviceConfig = {
                Type = "simple";
                DynamicUser = true;
                User = "gitea-runner";
                Group = "gitea-runner";
                SupplementaryGroups = ["deploy-key-readers"];
                RuntimeDirectory = "forgejo-deploy-agent";
                ExecStart = pkgs.writeShellScript "forgejo-deploy-key-agent" ''
                    set -euo pipefail
                    ${pkgs.openssh}/bin/ssh-agent -D -a ${deployKeyAgentSock} &
                    agentPid=$!
                    trap 'kill $agentPid 2>/dev/null' EXIT TERM INT

                    for _ in $(seq 1 50); do
                        [ -S ${deployKeyAgentSock} ] && break
                        sleep 0.2
                    done

                    keyCopy=$(mktemp /run/forgejo-deploy-agent/key.XXXXXX)
                    install -m 400 ${config.sops.secrets."deploy/ssh_key".path} "$keyCopy"
                    SSH_AUTH_SOCK=${deployKeyAgentSock} ${pkgs.openssh}/bin/ssh-add "$keyCopy"
                    rm -f "$keyCopy"

                    wait $agentPid
                '';
            };
        };

        systemd.services."gitea-runner-${runnerName}" = {
            after = ["forgejo-deploy-key-agent.service"];
            requires = ["forgejo-deploy-key-agent.service"];
            environment.SSH_AUTH_SOCK = deployKeyAgentSock;
            serviceConfig.SupplementaryGroups = ["deploy-key-readers"];
        };

        programs.ssh.extraConfig = ''
            Host *
                StrictHostKeyChecking accept-new
                ServerAliveInterval 10
                ServerAliveCountMax 3
        '';

        programs.ssh.knownHosts =
            (lib.mapAttrs (host: publicKey: {
                hostNames = [inputs.self.deploy.nodes.${host}.hostname];
                inherit publicKey;
            })
            hostKeys)
            // {
                ${svc.fqdn} = {
                    hostNames = ["[${svc.fqdn}]:${toString svc.sshPort}"];
                    publicKey = svc.sshHostKey;
                };
            };

        systemd.services.forgejo-actions-runner-token = {
            description = "Generate Forgejo Actions runner registration token";
            after = ["forgejo.service"];
            requires = ["forgejo.service"];
            before = ["gitea-runner-${runnerName}.service"];
            requiredBy = ["gitea-runner-${runnerName}.service"];
            serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                User = config.services.forgejo.user;
                Group = config.services.forgejo.group;
                StateDirectory = "forgejo-actions-runner-token";
                Environment = [
                    "FORGEJO_WORK_DIR=${config.services.forgejo.stateDir}"
                    "FORGEJO_CUSTOM=${config.services.forgejo.customDir}"
                    "HOME=${config.services.forgejo.stateDir}"
                ];
                ExecStart = genTokenScript;
            };
        };

        services.gitea-actions-runner.instances.${runnerName} = {
            enable = true;
            name = runnerName;
            url = svc.url;
            inherit tokenFile;
            labels = ["native:host"];
            hostPackages = with pkgs; [
                bash
                coreutils
                curl
                gawk
                gitMinimal
                gnused
                nodejs
                wget
                nix
                openssh
            ];
        };
    };
}
