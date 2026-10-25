{config, ...}: let
    inherit (config.readmeLib) mkSdImageInstall;
in {
    den.aspects.led-pi.readme = {
        intro = "Raspberry Pi controlling LED strips.";
        install = mkSdImageInstall "an SD card" "led-pi";
    };
}
