{inputs, ...}: {
    den.default.nixos = {lib, ...}: let
        inherit (lib) mkOption types;

        mkRequired = type: description:
            mkOption ({inherit type;} // lib.optionalAttrs (description != null) {inherit description;});

        mkOptional = type: default: description:
            mkOption ({inherit type default;} // lib.optionalAttrs (description != null) {inherit description;});

        widgetSecretSubmodule = types.submodule {
            options = {
                name = mkRequired types.str null;
                sopsFile =
                    mkOptional (types.nullOr types.path) null
                    "sops file for the secret; defaults to config.my.secretFiles.dashboard.";
            };
        };

        actionSubmodule = types.submodule {
            options =
                inputs.hearth.lib.actionOptions
                // {
                    minRole = mkOptional (types.nullOr (types.enum ["guest" "user" "admin"])) null null;
                };
        };
    in {
        options.my.networking.tailscaleIP =
            mkOptional (types.nullOr types.str) null
            "Tailscale IP of this host, for relay topology's peer-address derivation.";

        options.my.networking.alwaysOnline =
            mkOptional types.bool true
            "Whether this host is expected to be reachable when CI deploys run. Set false for intermittently-online devices so their absence doesn't fail the deploy workflow.";

        options.my.dashboard.backgroundFile =
            mkOptional (types.nullOr types.path) null
            "Background image file served at /icons/background.<ext>.";

        options.my.secretFiles =
            mkOptional (types.attrsOf types.path) {}
            "Encrypted secret files under hosts/*/secrets/, keyed by filename stem.";

        options.my.dashboard.services = mkOption {
            default = {};
            type = types.attrsOf (types.submodule {
                options = {
                    name = mkRequired types.str null;
                    subtitle = mkOptional (types.nullOr types.str) null null;
                    pollIntervalMs =
                        mkOptional (types.nullOr types.int) null
                        "Overrides Hearth's default poll interval for this service.";
                    visibility =
                        mkOptional (types.nullOr (types.enum ["guest" "user" "admin"])) null
                        "Minimum Hearth role required to see this service at all.";
                    description = mkOptional types.str "" null;
                    icon =
                        mkOptional (types.nullOr types.str) null
                        "dashboard-icons short name, full URL, or data: URI -- omit to auto-discover.";
                    category = mkRequired types.str null;
                    href = mkOptional (types.nullOr types.str) null null;
                    widget = mkOptional (types.nullOr (types.attrsOf types.anything)) null null;
                    sensitive =
                        mkOptional types.bool false
                        "Hide this service by default; toggle with Alt+S.";
                    host =
                        mkOptional (types.nullOr types.str) null
                        "Override for a non-NixOS-host service (e.g. rackflix); otherwise auto-derived.";
                    resourceUnits =
                        mkOptional (types.listOf types.str) []
                        "Systemd unit(s) whose CPU/RAM counts toward this service's task-manager tile.";
                    providesHostMetrics =
                        mkOptional types.bool false
                        "This widget already covers its host's CPU/RAM (e.g. QNAP) -- used for that host's metrics instead of an agent.";
                    widgetSecrets =
                        mkOptional (types.attrsOf widgetSecretSubmodule) {}
                        "Map of Hearth widgetConfig env var names to sops secret config.";
                    actions =
                        mkOptional (types.listOf actionSubmodule) []
                        "Actions rendered as buttons on this service's widget.";
                };
            });
        };
    };
}
