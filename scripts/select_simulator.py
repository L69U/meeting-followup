"""Select an installed iPhone simulator instead of hardcoding a device name."""
import json
import os
import subprocess


def choose_device(devices):
    candidates = []
    for runtime, group in devices.items():
        if ".iOS-" not in runtime:
            continue
        for device in group:
            if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
                candidates.append(device)
    if not candidates:
        raise RuntimeError("No available iPhone simulator; install an iOS simulator runtime in Xcode.")
    return candidates[0]["udid"]


if __name__ == "__main__":
    result = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "--json"],
                            check=True, capture_output=True, text=True)
    device = choose_device(json.loads(result.stdout)["devices"])
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
        output.write("SIMULATOR_ID=" + device + "\n")
    print("Selected simulator:", device)
