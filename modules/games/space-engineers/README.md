# Space Engineers

Space Engineers dedicated server via Docker ([devidian/spaceengineers](https://hub.docker.com/r/devidian/spaceengineers)).

## Usage

1. Add the module to your `configuration.nix`:

   ```nix
   {
       services.space-engineers = {
           enable = true;
           port = 27016;
           instanceName = "default";
           dataDir = "/var/lib/space-engineers";
       };
   }
   ```

2. Set up the instance:
   1. Setup a SE instance like explained [here](https://www.spaceengineersgame.com/dedicated-servers/)
   2. Rename the `<LoadWorld>` value in the `SpaceEngineers-Dedicated.cfg` file to:

      ```xml
      <MyConfigDedicated>
          ...
          <LoadWorld>Z:\appdata\space-engineers\instances\default\Saves\[World Name]</LoadWorld>
          <WorldName>[World Name]</WorldName>
          ...
      </MyConfigDedicated>
      ```

   3. Copy the instance into the `instances` directory:
      > the Instance is located in `C:\Users\[User]\AppData\Roaming\SpaceEngineersDedicated`

3. Start the service:

   ```sh
   sudo systemctl start podman-space-engineers
   ```

## Fixing a broken / stuck server

The container runs steamcmd on every start (app ID `298740`). If the server won't start, steamcmd's install manifest is usually corrupt. Symptoms in `journalctl -u podman-space-engineers`:

- `ERROR! Failed to install app '298740' (Missing configuration)`
- `Application could not be started` / `ShellExecuteEx failed: File not found`

**Fix (copy-paste, safe, reversible):**

```sh
# 1. Delete the corrupt manifest (steamcmd rebuilds it from scratch)
sudo rm -f /var/lib/space-engineers/SpaceEngineersDedicated/steamapps/appmanifest_298740.acf

# 2. Restart 2-3 times. Each restart resumes the download; the
#    install is done when a pass prints "Success! App '298740' fully installed".
sudo systemctl restart podman-space-engineers
```

Don't `podman exec` into the container - it auto-removes on exit, so edit files on the host under `/var/lib/space-engineers/` instead.

**Confirm it worked** - server is healthy once the manifest shows `StateFlags "4"` (fully installed) with a real size and build id:

```sh
sudo grep -E 'StateFlags|SizeOnDisk|buildid' \
  /var/lib/space-engineers/SpaceEngineersDedicated/steamapps/appmanifest_298740.acf
```

A corrupt manifest reads `StateFlags "2"` with `SizeOnDisk "0"` and `buildid "0"`; a healthy one reads `StateFlags "4"` with the real byte count and a non-zero build id. A `state is 0x602` line mid-fix just means "still updating" - keep restarting.
