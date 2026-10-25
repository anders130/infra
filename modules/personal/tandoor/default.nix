{den, ...}: {
    serviceRegistry.tandoor = {
        web = {
            subdomain = "tandoor";
            port = 9007;
        };
        dashboard = nixos: {
            name = "Tandoor";
            category = "Personal";
            widget = {
                type = "tandoor";
                baseUrl = nixos.my.services.tandoor.url;
                tokenEnvVar = "TANDOOR_TOKEN";
            };
            widgetSecrets.TANDOOR_TOKEN.name = "tandoor/api_key";
            resourceUnits = ["tandoor-recipes.service"];
        };
        access = {};
    };

    den.aspects.tandoor.includes = with den.aspects; [postgres];

    den.aspects.tandoor.nixos = {config, ...}: let
        svc = config.my.services.tandoor;
        dbname = "tandoor_recipes";
    in {
        my.services.postgres.databases.${dbname} = {};
        services.tandoor-recipes = {
            inherit (svc) port;
            enable = true;
            address = "127.0.0.1";
            extraConfig = {
                ALLOWED_HOSTS = svc.fqdn;
                ENABLE_METRICS = 1;
                SOCIAL_DEFAULT_GROUP = "user";
                GUNICORN_MEDIA = "1";
                MEDIA_ROOT = "/var/lib/tandoor-recipes";

                DB_ENGINE = "django.db.backends.postgresql";
                POSTGRES_HOST = "/run/postgresql";
                POSTGRES_PORT = config.services.postgresql.settings.port;
                POSTGRES_USER = dbname;
                POSTGRES_DB = dbname;
                TZ = config.time.timeZone;
            };
        };
    };
    den.aspects.tandoor.readme = {
        title = "Tandoor";
        sections = [
            {
                title = "Migrating tandoor-recipes on NixOS";
                content = ''
                    On the running instance you want to migrate away from, run:

                    ```bash
                    sudo /var/lib/tandoor-recipes/tandoor-recipes-manage export -a \
                        --exclude contenttypes \
                        --exclude auth.permission \
                        --exclude auth.group \
                        --exclude admin.logentry > /home/$USER/tandoor-recipes-dump.json
                    ```

                    After copying the dump file to your new instance, run:

                    ```bash
                    sudo mkdir /data
                    sudo chown -R tandoor_recipes:tandoor_recipes /data
                    sudo mv /path/to/tandoor-recipes-dump.json /data/dump.json

                    sudo /var/lib/tandoor-recipes/tandoor-recipes-manage import /data/dump.json
                    ```
                '';
            }
        ];
    };
}
