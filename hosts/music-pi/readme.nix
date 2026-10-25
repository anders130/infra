{config, ...}: let
    inherit (config.readmeLib) mkSdImageInstall;
in {
    den.aspects.music-pi.readme = {
        intro = "Raspberry Pi for audio playback, equipped with a HiFiBerry DAC+ HAT.";
        install = mkSdImageInstall "an SD card" "music-pi";
    };
}
