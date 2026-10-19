{
    self,
    config,
    ...
}: {
    serviceRelays = [
        {
            from = self.nixosConfigurations.ds1;
            via = self.nixosConfigurations.vps1;
            services = with config.serviceRegistry; [
                astroneer
                terraria
                tmodloader
                hytale
                space-engineers
            ];
        }
    ];
}
