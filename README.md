# DSS (DualSense/DSShock Service) Controller Mapper 🎮

**Version: 0.1.0-alpha**

DSS Controller Mapper is an ultra-lightweight Windows service written in Nim. It is designed to map Sony DualSense (PS5) and DualShock 4 (PS4) controllers as virtual Xbox 360 controllers.

Unlike heavier alternatives, this tool focuses on pure performance, minimal RAM usage (<2MB), no GUI interface and near-zero input latency.

---

## ✨ Key Features

- **Plug & Play Support:** Automatic detection of DualSense and DS4 (v1 & v2) controllers.
- **Xbox 360 Emulation:** Full compatibility with all Windows games and PC Game Pass.
- **Event-Driven Architecture:** The service "sleeps" when no controller is connected, saving CPU cycles and battery life.
- **Zero UI:** No invasive windows; manage everything through simple, transparent batch scripts.

## 🎮 Controller Shortcuts (Macros)

The mapper includes built-in shortcuts to make managing your controller easier without needing to interact with the PC:

- **PS + Options:** Physically turns off the controller (works only in Bluetooth mode).
- **PS + Circle:** Disconnects the controller and completely closes the DSS background service.

## 🛠️ Requirements

To run the mapper, your system must have the following:

- **ViGEmBus Driver:** The kernel driver that enables virtual controller emulation.
  - Download the latest version here: [ViGEmBus Releases](https://github.com/nefarius/ViGEmBus/releases).
- **Runtime Libraries** (Included in the release):
  - `vigemclient.dll`
  - `hidapi.dll`
- **OS:** Windows 10 or 11 (64-bit).

## 🚀 Installation & Usage

1. Download the latest package from the **Releases** section.
2. Extract the contents to a folder of your choice.
3. **To enable Auto-Start:** Run `autostart.bat`. The mapper will now start silently every time you log into Windows.
4. **To remove Auto-Start:** Run `remove_autostart.bat`.
5. Connect your controller via USB or Bluetooth and start playing!

## ⚙️ Compilation (For Developers)

If you wish to compile the source code yourself, ensure you have the [Nim compiler](https://nim-lang.org/) installed and run:

```bash
nim c -d:release --app:gui --mm:arc dss.nim
```

- `-d:release`: Optimizes for maximum performance.
- `--app:gui`: Hides the terminal window on startup.
- `--mm:arc`: Enables deterministic, ultra-lightweight memory management.

## ⚠️ Important Notes

- **DualSense (PS5) Support:** The application has currently been tested extensively only with the DualShock 4 (v1 & v2). Support for the DualSense controller is implemented but still needs thorough testing.
- **False Positives:** Some Antivirus software may flag the executable. This is common for Nim programs that interact with the Windows Registry (for startup) and simulate hardware input. The code is open-source and can be audited.
- **Input Conflict:** It is recommended not to use this tool alongside DS4Windows or Steam Input to avoid "Double Input" issues.

## 🔮 Future Developments

- **Touchpad-to-Mouse:** Full implementation to use the controller's trackpad to move the mouse cursor and perform left/right clicks.
- **Adaptive Trigger Support:** Add support for the Adaptive Triggers found on the DualSense controller.
- **Controller Mapping:** Allow users to customize the mapping of keys to the controller buttons.
- **GUI Interface:** Add a simple GUI interface to manage the service settings?

## 🤝 Contributions

Pull requests are welcome! If you find a bug or have an idea for a new feature (such as Adaptive Trigger support), please open an Issue.

*Created with ❤️ using Nim.*
