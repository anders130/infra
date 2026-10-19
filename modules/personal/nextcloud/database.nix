{
    den.aspects.nextcloud.nixos = {config, ...}: let
        dbname = "nextcloud";
        dbuser = "nextcloud";
    in {
        my.services.postgres.databases.${dbname} = {};
        services.nextcloud.config = {
            inherit dbname dbuser;
            dbtype = "pgsql";
            dbhost = "/run/postgresql";
            dbpassFile = config.sops.secrets."nextcloud/dbPass".path;
        };
    };
}
