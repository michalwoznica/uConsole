# Stage 11 physical validation

**Status:** physical hardware pass complete; consolidated image corrections implemented, rebuild/regression pending  
**Test image:** Arch Linux ARM 2026.08, `linux-uconsole 6.18.60-1-uconsole`  
**Raspberry Pi Linux source:** `0b41724521c9adf5399409d02aece6c1df0a4432`

This document records only conclusions supported by physical testing of the
uConsole. It also records the small image-layer corrections justified by that
testing. The kernel/hardware drivers are left unchanged where the physical
results proved them correct.

## Physical results

### Boot, display, input and storage

- The image boots from microSD into the visible Arch Linux ARM console.
- CWU50 panel output works.
- VC4/KMS/DSI produces the console display.
- OCP8178 backlight hardware works and exposes
  `/sys/class/backlight/backlight`.
- Built-in keyboard works for normal console use.
- USB mass storage was detected with `lsblk`, mounted and unmounted
  successfully.
- The microSD path is functionally proven by booting and operating the system
  from the card.
- Reboot and shutdown/power-off have both been exercised successfully during
  this validation cycle.

### Networking and package management

- Wi-Fi associates and passes IPv4 traffic.
- DNS works through NetworkManager + systemd-resolved.
- NetworkManager retains the Wi-Fi profile/password across reboot.
- `pacman -Syu` works on the physical device with the normal pacman sandbox;
  the target Landlock configuration is therefore proven functional.

### Audio and headphone switching

Built-in speakers and the headphone jack both produce audio.

The first headphone-switch test exposed one boot-policy defect: GPIO10
(`HP_DET`) remained low both with and without headphones inserted. The custom
`uconsole_amp_switch` module was loaded and bound correctly, so this was not a
driver-loading failure.

Applying the live equivalent of ClockworkPi's no-pull policy:

```sh
pinctrl set 10 ip pn
```

made GPIO10 read low with headphones unplugged and high with headphones
inserted. Automatic routing then worked correctly in both directions: speakers
mute on insertion and resume on removal.

**Implemented image correction:**

```ini
gpio=10=ip,np
```

is now part of `image/archlinuxarm/boot/config-uconsole-cm4.txt`.

No amplifier-switch driver or device-tree GPIO polarity change is required.

### Battery and charging

Physical AC transitions work:

```text
charging cable connected:    battery=Charging,    AC online=1
charging cable disconnected: battery=Discharging, AC online=0
```

Correct live sysfs paths on this hardware are:

```text
/sys/class/power_supply/axp20x-battery/status
/sys/class/power_supply/axp22x-ac/online
```

### Power button

A very brief power-button press is detected and, on the tested image, causes
immediate system power-off. This proves the PMIC/input path works, but the
policy is too easy to trigger accidentally for a general-purpose console
image.

**Implemented image correction:** Arch systemd-logind now receives a target
specific drop-in with:

```ini
HandlePowerKey=ignore
```

This deliberately changes only the short-press userspace policy. The working
kernel/PMIC input path remains untouched. Explicit console shutdown remains
available, and a different button policy can be chosen later without changing
hardware support.

### Backlight keys

Direct backlight control works. The tested device reported:

```text
brightness=15
max_brightness=21
```

and writing `5` to `/sys/class/backlight/backlight/brightness` visibly dimmed
the display.

`evtest` on the uConsole Consumer Control input interface also proved that the
keyboard emits the correct Linux events:

```text
KEY_BRIGHTNESSDOWN (224)
KEY_BRIGHTNESSUP   (225)
```

The missing layer was therefore console userspace, not the keyboard firmware,
input driver or OCP8178 driver.

**Implemented image correction:** the Arch target installs and enables a small
systemd service that listens to the uConsole Consumer Control event interface
with `evtest` and adjusts the backlight sysfs value one step per key press. It
requires no X11, Wayland or desktop environment and adds no new package beyond
the already-selected `evtest` validation/base package.

The first rebuilt image exposed one narrow userspace defect: the handler
searched case-sensitively for `ClockworkPi uConsole Consumer Control`, while
the physical keyboard is reported by the kernel as exactly:

```text
ClockworkPI uConsole Consumer Control
```

The service remained active but never spawned `evtest`; its child was only the
2-second retry sleep. Applying the live one-line name correction and restarting
the service made `Fn + <` / `Fn + >` control brightness immediately. This
physically proves the handler design and isolates the permanent correction to
the exact device-name capitalization.

### Bluetooth

The Bluetooth controller is present, powered and not rfkill-blocked.

Direct kernel-management discovery with:

```sh
timeout 20s btmgmt find
```

started discovery and found multiple nearby LE devices with RSSI values. This
physically proves the controller, firmware communication, kernel Bluetooth
management path and RF receive/discovery path.

Normal BlueZ discovery is also physically proven. The correct non-interactive
BlueZ command:

```sh
bluetoothctl -t 20 scan on
```

returned discovered devices on the rebuilt image. Earlier testing with an
external `timeout 20s bluetoothctl scan on` wrapper was misleading; there is no
Bluetooth package/configuration defect to correct. No BlueZ pin, downgrade or
image workaround is required.

## Image changes justified by Stage 11

The consolidated rebuild contains exactly these new Stage 11 corrections:

1. `gpio=10=ip,np` in the Raspberry Pi firmware boot policy for reliable
   headphone detect.
2. A console-only brightness-key service that maps the already-correct
   `KEY_BRIGHTNESSUP/DOWN` input events to the working backlight sysfs control.
3. An Arch/systemd-logind drop-in that ignores a brief power-key press so an
   accidental tap does not immediately shut down the device.

Bluetooth is deliberately **not** changed in this checkpoint because no
specific package/configuration correction has yet been physically justified.

## Rebuild regression status

Physical regression results on the first rebuilt image:

- boot to visible console: PASS;
- headphone insertion/removal without manual `pinctrl`: PASS;
- brief power-button press ignored: PASS;
- normal BlueZ discovery with `bluetoothctl -t 20 scan on`: PASS;
- brightness keys: FAIL initially because of the exact device-name
  capitalization mismatch, then PASS immediately after applying the live
  `ClockworkPI` correction and restarting the service.

The repository now carries that exact permanent brightness-name correction. A
final image rebuild is required only to prove that the distributable artifact
contains the already physically proven fix. After flashing it, the only
necessary hardware regression is `Fn + <` / `Fn + >`; broad hardware
re-enumeration is not required.
