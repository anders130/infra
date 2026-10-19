{den, ...}: {
    den.aspects.ds1.includes = with den.aspects; [
        astroneer
        buntes-schnitzel
        game-status-http
        hytale
        minecraft
        space-engineers
        terraria
        tmodloader
    ];

    den.aspects.ds1.nixos = {
        my.games.tmodloader = {
            dataDir = "/mnt/rackflix/appdata/tModLoader";
            tmodloaderVersion = "v2025.05.3.0";
            motd = "NixOS Terraria Server";
            shutdownMessage = "Server is shutting down!";
            mods.enabled = [
                2603400287 # Armor Modifiers & Reforging
                3018274567 # Artificer's Accessories
                2565540604 # Auto Trash
                2669644269 # Boss Checklist
                2824688266 # Calamity Music
                2824688072 # Calamity
                2802867430 # Fargo's Best of Both Worlds
                2908170107 # absoluteAquarian Utilities
                2563309347 # Magic Storage
                2982195397 # Pets Overhaul
                2820025575 # Pylons Prevent Evils
                2619954303 # Recipe Browser
                2839001756 # Unofficial Calamity Whips
            ];
            maxPlayers = 3;
            world = {
                name = "Gallifrey";
                seed = "random";
                size = "large";
                difficulty = "master";
            };
        };
    };
}
