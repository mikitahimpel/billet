# perf-device

Heat, CPU and thermal numbers from Ourio on a real iPhone on a cable. Docs: `docs/perf/device-measurements.md`.

## Build (Release, Labs and perf hooks on, one in-place update of the installed app)

```sh
cd apps/ios && xcodegen generate
BILLET_LABS=YES BILLET_PERF_HOOKS=YES xcodebuild build -project Billet.xcodeproj -scheme Billet \
  -configuration Release -destination 'id=<UDID>' -derivedDataPath ~/Library/Caches/perf-device-dd \
  -allowProvisioningUpdates
xcrun devicectl device install app --device <UDID> \
  ~/Library/Caches/perf-device-dd/Build/Products/Release-iphoneos/Ourio.app
```

Install only as an update of the same bundle id; never uninstall. Take the Mac's build lock around the build only.

## One run

```sh
PERF_UDID=<UDID> tools/perf-device/run.py <name> --lab "noSunShadow,tier=full" --room living --seconds 180 \
  --cool-to <baseline battery temp C>
```

The phone must be unlocked, Auto-Lock set to Never, brightness fixed, Low Power Mode off. `run.py` launches the app
with `devicectl device process launch --console`, samples `AppleSmartBattery` (temperature, amperage, voltage) every
10 s through libimobiledevice, reads the app's `PERFLINE` lines (CPU, thermal state, governor, room stats, scene
writes per second), and writes `battery.csv`, `app.log` and `summary.json` to `~/Library/Caches/perf-device-runs/<name>`.

`-perf.lab` takes comma-separated names from `PerfSuspect` (`noSunShadow`, `fewerLights`, `noBloom`, `bakedBlobs`,
`mergeFurniture`, `fullMeshes`, `ownLoop`, a leading `-` turns one off), `tier=full|fair|serious|critical` and `meter`.
`-perf.room living|bedroom` picks the room. Both exist only in builds with `PERF_HOOKS=YES` or Debug.

`sweep.sh` runs the list of configurations in turn; `trace.sh` records an Instruments template against the running app.

## Reading the numbers

On a cable the phone charges, which heats the battery and makes battery % useless: compare configurations against each
other, same cable, same brightness, run order alternated, baseline repeated. Battery temperature moves slowly; a
3-minute run shows a slope, not a steady state.
