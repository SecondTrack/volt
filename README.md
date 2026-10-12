# Battery

**Battery monitor with stress test**

Charge level, voltage, current, temperature, charge cycles and health in real time. The stress test measures the capacity that is really left and gives an honest grade.

## Features

- Live charge, voltage, current and temperature
- Charge cycles and health
- Stress test with an honest grade

## Runs on

iOS 6.1.6 · jailbroken iPod touch

## Install

The easiest way is the **[Reboot App Store](https://github.com/SecondTrack/reboot)** right on the iPod.
By hand: download the `.deb` from the [latest release](https://github.com/SecondTrack/batterie/releases/latest), install it with `dpkg -i`, then run `uicache`.

## Build it yourself

With [Theos](https://theos.dev) (iOS SDK with armv7):

```sh
make package
```

## Part of Reboot

This app is part of **Reboot** by **Second Track** – new apps for old iPods.
All apps: [SecondTrack](https://github.com/SecondTrack).

## License

GPL-3.0 – see [LICENSE](LICENSE). Bundled libraries under `vendor/` keep their own licenses.
Not affiliated with Apple. iPod is a trademark of Apple Inc.
