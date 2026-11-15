# DO-NOT-EDIT. This file was auto-generated using github:denful/flake-file.
# Use `nix run .#write-flake` to regenerate it.
{
    outputs = inputs: import ./outputs.nix inputs;

    nixConfig = {
        abort-on-warn = true;
        extra-experimental-features = ["pipe-operators"];
        extra-substituters = ["https://nixos-raspberrypi.cachix.org" "https://anders130.cachix.org"];
        extra-trusted-public-keys = ["nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=" "anders130.cachix.org-1:mCAq0L6Ld3lG7gxJVHGzKr2rqUZ5qs5YoERxoSjMOXs="];
    };

    inputs = {
        authelia-access-control = {
            url = "git+ssh://forgejo@git.gollub.dev:2222/jesse/authelia-access-control.git";
            inputs = {
                flake-parts.follows = "flake-parts";
                import-tree.follows = "import-tree";
                nixpkgs.follows = "nixpkgs";
            };
        };
        buntes-schnitzel = {
            url = "git+ssh://git@github.com/kale-collective/buntes-schnitzel";
            inputs = {
                flake-parts.follows = "flake-parts";
                import-tree.follows = "import-tree";
                nixpkgs.follows = "nixpkgs";
            };
        };
        calmask = {
            url = "git+ssh://forgejo@git.gollub.dev:2222/jesse/calmask.git";
            inputs = {
                flake-parts.follows = "flake-parts";
                git-hooks.follows = "git-hooks";
                import-tree.follows = "import-tree";
                nixpkgs.follows = "nixpkgs";
                treefmt-nix.follows = "treefmt-nix";
            };
        };
        chordweave = {
            url = "git+ssh://git@github.com/anders130/chordweave?ref=master";
            inputs = {
                flake-parts.follows = "flake-parts";
                git-hooks.follows = "git-hooks";
                import-tree.follows = "import-tree";
                nixpkgs.follows = "nixpkgs";
            };
        };
        den.url = "github:denful/den";
        deploy-rs = {
            url = "github:serokell/deploy-rs";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        disko = {
            url = "github:nix-community/disko";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        files = {
            url = "github:mightyiam/files";
            flake = false;
        };
        flake-file.url = "github:vic/flake-file";
        flake-follows.url = "github:anders130/flake-follows";
        flake-parts = {
            url = "github:hercules-ci/flake-parts";
            inputs.nixpkgs-lib.follows = "nixpkgs-lib";
        };
        git-hooks = {
            url = "github:cachix/pre-commit-hooks.nix";
            inputs = {
                flake-compat.follows = "";
                nixpkgs.follows = "nixpkgs";
            };
        };
        hearth = {
            url = "git+ssh://git@github.com/anders130/hearth?ref=master";
            inputs = {
                flake-parts.follows = "flake-parts";
                git-hooks.follows = "git-hooks";
                import-tree.follows = "import-tree";
                nixpkgs.follows = "nixpkgs";
                treefmt-nix.follows = "treefmt-nix";
            };
        };
        import-tree.url = "github:denful/import-tree";
        lumehub = {
            url = "github:LumeHub/server/dev";
            inputs = {
                flake-parts.follows = "flake-parts";
                git-hooks.follows = "git-hooks";
                import-tree.follows = "import-tree";
            };
        };
        nix-lib = {
            url = "github:anders130/nix-lib";
            inputs = {
                flake-parts.follows = "flake-parts";
                import-tree.follows = "import-tree";
                nixpkgs-lib.follows = "nixpkgs-lib";
            };
        };
        nix-minecraft = {
            url = "github:Infinidoge/nix-minecraft";
            inputs = {
                flake-compat.follows = "";
                nixpkgs.follows = "nixpkgs";
            };
        };
        nixos-raspberrypi = {
            url = "github:nvmd/nixos-raspberrypi/main";
            inputs.flake-compat.follows = "";
        };
        nixpkgs.url = "nixpkgs/nixos-26.05";
        nixpkgs-lib.follows = "nixpkgs";
        sops-nix = {
            url = "github:Mic92/sops-nix";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        soundgate = {
            url = "github:anders130/soundgate";
            inputs = {
                flake-parts.follows = "flake-parts";
                import-tree.follows = "import-tree";
            };
        };
        treefmt-nix = {
            url = "github:anders130/treefmt-nix";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        unstable.url = "nixpkgs/nixos-unstable";
        vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";
    };
}
