{
    den.aspects.ds1.nixos = {
        my.services.nextcloudBusyCalendarSync = {
            nextcloudUsername = "jesse";
            sourceCalendars."Personal" = {
                summary = "Busy";
                location = "Away";
            };
        };
    };
}
