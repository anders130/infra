{inputs, ...}: {
    flake-file.inputs.disko.url = "github:nix-community/disko";
    den.aspects.disko.nixos.imports = [inputs.disko.nixosModules.disko];
}
