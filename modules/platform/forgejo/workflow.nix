{inputs, ...}: {
    perSystem = {
        pkgs,
        lib,
        ...
    }: let
        deployHosts = lib.attrNames inputs.self.deploy.nodes;
        allowFailureHosts = lib.filter
        (host: !inputs.self.nixosConfigurations.${host}.config.my.networking.alwaysOnline)
        deployHosts;
    in {
        files.file.".forgejo/workflows/deploy.yml".text = builtins.readFile
        ((pkgs.formats.yaml {}).generate "deploy.yml" {
            on = {
                push.branches = ["master"];
                workflow_dispatch = {};
            };
            jobs.deploy = {
                runs-on = "native";
                strategy = {
                    fail-fast = false;
                    matrix = {
                        host = deployHosts;
                        include = map (host: {
                            inherit host;
                            allowFailure = true;
                        })
                        allowFailureHosts;
                    };
                };
                steps = let
                    tolerateFailure = "[ \"\${{ matrix.allowFailure == true }}\" = true ]";
                in [
                    {uses = "actions/checkout@v4";}
                    {
                        name = "Build \${{ matrix.host }}";
                        run = "nix build --accept-flake-config .#nixosConfigurations.\${{ matrix.host }}.config.system.build.toplevel --no-link || ${tolerateFailure}";
                    }
                    {
                        name = "Deploy \${{ matrix.host }}";
                        run = "nix run --accept-flake-config .#deploy -- --skip-checks .#\${{ matrix.host }} || ${tolerateFailure}";
                    }
                ];
            };
        });
    };
}
