# Volt

**What is your old iPod's battery really worth? Live readings plus a stress test that measures it.**

A ten-year-old iPod usually still says "100 %". This app shows what the battery controller actually reports – and then drains the battery under load to see how many mAh are really left.

## Live readings

Charge in % and mAh, full-charge vs. design capacity, health (full ÷ design), charge cycles, voltage, current, temperature and charging state – refreshed every 2 seconds. When iOS gives no time estimate, the app calculates the remaining time from the current draw itself.

The values come straight from IOKit's `IOPMPowerSource`, loaded at runtime so the app doesn't need to link private frameworks.

## Stress test

1. Charge to at least 99 % and leave the cable plugged in – the test arms itself.
2. Pull the cable. The test starts: two CPU threads at full load, screen stays on.
3. Every second the app adds up current × time, so it measures the mAh that actually come out of the battery.

The result is a grade from **Top** (≥ 80 % of design capacity) down to **Poor**, lowered if the voltage sagged below 3.3 V. If the iPod reports no current reading, the grade comes from runtime under load instead.

It stops by itself above 44 °C, when the cable goes back in or the app leaves the foreground. If the battery is good enough to run until the iPod dies, that's fine too: the result is saved every second and shown on the next launch as "ran until shutdown".

## Runs on

iOS 6.1.6 · jailbroken iPod touch 4 (assumes 930 mAh if the device reports no design capacity)

## Install

Easiest via the **[Reboot App Store](https://github.com/SecondTrack/reboot)** right on the iPod. By hand: `.deb` from the [latest release](https://github.com/SecondTrack/batterie/releases/latest), `dpkg -i`, then `uicache`.

Build it yourself with [Theos](https://theos.dev): `make package` (iOS 6.0+, armv7).

## License

GPL-3.0 – see [LICENSE](LICENSE).
Not affiliated with Apple. iPod is a trademark of Apple Inc.
