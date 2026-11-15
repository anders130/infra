{
    config,
    lib,
    ...
}: let
    inherit (config) serviceLib;

    mkAction = name: a: let
        isCommand = a ? command;
        isWidgetAction = a ? widgetAction;
    in {
        inherit (a) id label;
        icon = a.icon or null;
        placement = a.placement or null;
        minRole = a.minRole or null;
        command =
            if isCommand
            then a.command
            else null;
        unit =
            if isCommand || isWidgetAction
            then null
            else a.unit or "${name}.service";
        verb =
            if isCommand || isWidgetAction
            then null
            else a.verb;
        widgetAction =
            if isWidgetAction
            then a.widgetAction
            else null;
    };
in {
    config.den.aspects = lib.mapAttrs (name: svc: {
        nixos = {
            config,
            lib,
            ...
        }: let
            h = serviceLib.resolveFn config svc.dashboard;

            autoHref =
                if svc.web != null
                then config.my.services.${name}.url
                else null;
            resolvedHref = h.href or autoHref;

            actions = serviceLib.resolveFn config svc.actions;
        in {
            config = lib.mkMerge [
                (lib.optionalAttrs (svc.dashboard != null) {
                    my.dashboard.services.${name} = {
                        name = h.name;
                        description = h.description or "";
                        icon = lib.mkDefault (h.icon or null);
                        category = h.category;
                        href = resolvedHref;
                        widget = h.widget or null;
                        sensitive = h.sensitive or false;
                        widgetSecrets = h.widgetSecrets or {};
                        subtitle = h.subtitle or null;
                        pollIntervalMs = h.pollIntervalMs or null;
                        visibility = h.visibility or null;
                        host = h.host or null;
                        resourceUnits = h.resourceUnits or [];
                    };
                })
                (lib.optionalAttrs (actions != []) {
                    my.dashboard.services.${name}.actions = map (mkAction name) actions;
                })
            ];
        };
    })
    config.serviceRegistry;
}
