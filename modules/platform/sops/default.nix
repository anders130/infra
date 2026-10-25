{inputs, ...}: {
    flake-file.inputs.sops-nix.url = "github:Mic92/sops-nix";

    den.aspects.sops.nixos = {
        imports = [inputs.sops-nix.nixosModules.sops];
        sops.age.keyFile = "/home/admin/.config/sops/age/keys.txt";
    };

    perSystem = {pkgs, ...}: {
        packages.update-keys = pkgs.writeShellApplication {
            name = "update-keys";
            runtimeInputs = [pkgs.sops pkgs.findutils];
            text = ''
                find hosts/*/secrets -type f \
                    -exec sops updatekeys -y {} \;
            '';
        };
    };

    den.aspects.sops.readme = {
        title = "Sops";
        intro = "Secrets management with [sops-nix](https://github.com/Mic92/sops-nix).";
        sections = [
            {
                title = "Setup";
                content = ''
                    Generate the age key:

                    ```bash
                    mkdir -p ~/.config/sops/age
                    age-keygen -o ~/.config/sops/age/keys.txt
                    ```

                    Add the public key to `.sops.yaml` at the repo root:

                    ```bash
                    cat ~/.config/sops/age/keys.txt | grep "public key" | awk '{print $NF}'
                    ```
                '';
            }
        ];
    };
}
