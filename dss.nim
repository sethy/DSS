import os, times, strutils
import registry

{.link: "dss_res.o".}

# --- Win32 API for System Events ---
type
  HWND = int
  UINT = uint32
  WPARAM = int
  LPARAM = int
  LRESULT = int
  WNDPROC = proc(hwnd: HWND, uMsg: UINT, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.}
  HIDDeviceObj = object
    device_handle: int
    read_pending: bool
    read_buf: pointer
    ol: pointer
  HidDevicePtr = ptr HIDDeviceObj

  WNDCLASSA {.pure.} = object
    style: UINT
    lpfnWndProc: WNDPROC
    cbClsExtra: int32
    cbWndExtra: int32
    hInstance: int
    hIcon: int
    hCursor: int
    hbrBackground: int
    lpszMenuName: cstring
    lpszClassName: cstring

  MSG {.pure.} = object
    hwnd: HWND
    message: UINT
    wParam: WPARAM
    lParam: LPARAM
    time: uint32
    pt: array[2, int32]

const
  WM_DEVICECHANGE = 0x0219
  WM_WTSSESSION_CHANGE = 0x02B1
  WTS_SESSION_LOCK = 0x7
  WTS_SESSION_UNLOCK = 0x8
  NOTIFY_FOR_THIS_SESSION = 0

proc RegisterClassA(lpWndClass: ptr WNDCLASSA): uint16 {.stdcall, dynlib: "user32", importc.}
proc CreateWindowExA(dwExStyle: uint32, lpClassName: cstring, lpWindowName: cstring, dwStyle: uint32, X: int32, Y: int32, nWidth: int32, nHeight: int32, hWndParent: HWND, hMenu: int, hInstance: int, lpParam: pointer): HWND {.stdcall, dynlib: "user32", importc.}
proc GetMessageA(lpMsg: ptr MSG, hWnd: HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT): int32 {.stdcall, dynlib: "user32", importc.}
proc TranslateMessage(lpMsg: ptr MSG): int32 {.stdcall, dynlib: "user32", importc.}
proc DispatchMessageA(lpMsg: ptr MSG): LRESULT {.stdcall, dynlib: "user32", importc.}
proc DefWindowProcA(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall, dynlib: "user32", importc.}
proc WTSRegisterSessionNotification(hWnd: HWND, dwFlags: uint32): int32 {.stdcall, dynlib: "wtsapi32", importc.}
proc WTSUnRegisterSessionNotification(hWnd: HWND): int32 {.stdcall, dynlib: "wtsapi32", importc.}

# Global variables for thread synchronization
var
  sessionLocked = false
  deviceChanged = true # True at startup to force an initial scan
  runMapping = true

# --- Logging ---
proc logMsg(msg: string) =
  try:
    let logFile = getAppDir() / "dss_service.log"
    let f = open(logFile, fmAppend)
    f.writeLine("[" & $now() & "] " & msg)
    f.close()
  except:
    discard

# --- Constants and ViGEmBus Types ---
const ViGEmClientDll = "vigemclient.dll"

type
  PVIGEM_CLIENT = pointer
  PVIGEM_TARGET = pointer
  VIGEM_ERROR = cint

  XUSB_REPORT* {.packed.} = object
    wButtons*: uint16
    bLeftTrigger*: uint8
    bRightTrigger*: uint8
    sThumbLX*: int16
    sThumbLY*: int16
    sThumbRX*: int16
    sThumbRY*: int16

# Xbox 360 Button Constants
const
  XUSB_GAMEPAD_DPAD_UP* = 0x0001'u16
  XUSB_GAMEPAD_DPAD_DOWN* = 0x0002'u16
  XUSB_GAMEPAD_DPAD_LEFT* = 0x0004'u16
  XUSB_GAMEPAD_DPAD_RIGHT* = 0x0008'u16
  XUSB_GAMEPAD_START* = 0x0010'u16
  XUSB_GAMEPAD_BACK* = 0x0020'u16
  XUSB_GAMEPAD_LEFT_THUMB* = 0x0040'u16
  XUSB_GAMEPAD_RIGHT_THUMB* = 0x0080'u16
  XUSB_GAMEPAD_LEFT_SHOULDER* = 0x0100'u16
  XUSB_GAMEPAD_RIGHT_SHOULDER* = 0x0200'u16
  XUSB_GAMEPAD_GUIDE* = 0x0400'u16
  XUSB_GAMEPAD_A* = 0x1000'u16
  XUSB_GAMEPAD_B* = 0x2000'u16
  XUSB_GAMEPAD_X* = 0x4000'u16
  XUSB_GAMEPAD_Y* = 0x8000'u16

# ViGEm Functions (FFI)
proc vigem_alloc*(): PVIGEM_CLIENT {.stdcall, dynlib: ViGEmClientDll, importc.}
proc vigem_free*(client: PVIGEM_CLIENT) {.stdcall, dynlib: ViGEmClientDll, importc.}
proc vigem_connect*(client: PVIGEM_CLIENT): VIGEM_ERROR {.stdcall, dynlib: ViGEmClientDll, importc.}
proc vigem_disconnect*(client: PVIGEM_CLIENT) {.stdcall, dynlib: ViGEmClientDll, importc.}
proc vigem_target_x360_alloc*(): PVIGEM_TARGET {.stdcall, dynlib: ViGEmClientDll, importc.}
proc vigem_target_add*(client: PVIGEM_CLIENT, target: PVIGEM_TARGET): VIGEM_ERROR {.stdcall, dynlib: ViGEmClientDll, importc.}
proc vigem_target_remove*(client: PVIGEM_CLIENT, target: PVIGEM_TARGET) {.stdcall, dynlib: ViGEmClientDll, importc.}
proc vigem_target_free*(target: PVIGEM_TARGET) {.stdcall, dynlib: ViGEmClientDll, importc.}
proc vigem_target_x360_update*(client: PVIGEM_CLIENT, target: PVIGEM_TARGET, report: XUSB_REPORT): VIGEM_ERROR {.stdcall, dynlib: ViGEmClientDll, importc.}

# ViGEm Force Feedback (notification callback)
type
  X360_NOTIFICATION_CALLBACK* = proc(client: PVIGEM_CLIENT, target: PVIGEM_TARGET, largeMotor: uint8, smallMotor: uint8, ledNumber: uint8, userData: pointer) {.stdcall.}

proc vigem_target_x360_register_notification*(client: PVIGEM_CLIENT, target: PVIGEM_TARGET, notification: X360_NOTIFICATION_CALLBACK, userData: pointer): VIGEM_ERROR {.stdcall, dynlib: ViGEmClientDll, importc.}
proc vigem_target_x360_unregister_notification*(target: PVIGEM_TARGET) {.stdcall, dynlib: ViGEmClientDll, importc.}

# --- HIDAPI Constants and Types ---
const HidApiDll = "hidapi.dll"

type
  hid_device = pointer
  hid_device_info = object
    path: cstring
    vendor_id: uint16
    product_id: uint16
    serial_number: pointer
    release_number: uint16
    manufacturer_string: pointer
    product_string: pointer
    usage_page: uint16
    usage: uint16
    interface_number: cint
    next: ptr hid_device_info

# HIDAPI Functions (FFI)
proc hid_init*(): cint {.cdecl, dynlib: HidApiDll, importc.}
proc hid_exit*(): cint {.cdecl, dynlib: HidApiDll, importc.}
proc hid_enumerate*(vendor_id, product_id: uint16): ptr hid_device_info {.cdecl, dynlib: HidApiDll, importc.}
proc hid_free_enumeration*(devs: ptr hid_device_info) {.cdecl, dynlib: HidApiDll, importc.}
proc hid_open_path*(path: cstring): hid_device {.cdecl, dynlib: HidApiDll, importc.}
proc hid_close*(dev: hid_device) {.cdecl, dynlib: HidApiDll, importc.}
proc hid_read_timeout*(dev: hid_device, data: ptr uint8, length: csize_t, milliseconds: cint): cint {.cdecl, dynlib: HidApiDll, importc.}
proc hid_write*(dev: hid_device, data: ptr uint8, length: csize_t): cint {.cdecl, dynlib: HidApiDll, importc.}
proc hid_send_feature_report*(dev: hid_device, data: ptr uint8, length: csize_t): cint {.cdecl, dynlib: HidApiDll, importc.}
proc hid_get_serial_number_string*(dev: hid_device, string: pointer, maxlen: csize_t): cint {.cdecl, dynlib: HidApiDll, importc.}

# --- Bluetooth API for Disconnection ---
const IOCTL_BTH_DISCONNECT_DEVICE = 0x41000c
type
  BLUETOOTH_FIND_RADIO_PARAMS {.pure.} = object
    dwSize: uint32

proc DeviceIoControl(hDevice: int, dwIoControlCode: uint32, lpInBuffer: pointer, nInBufferSize: int32, lpOutBuffer: pointer, nOutBufferSize: int32, lpBytesReturned: ptr int32, lpOverlapped: pointer): int32 {.stdcall, dynlib: "kernel32", importc.}
proc CloseHandle(hObject: int): int32 {.stdcall, dynlib: "kernel32", importc.}
proc GetLastError(): int32 {.stdcall, dynlib: "kernel32", importc.}
proc HidD_SetOutputReport(hidDeviceObject: int, reportBuffer: pointer, reportBufferLength: int32): bool {.stdcall, dynlib: "hid.dll", importc.}

proc BluetoothFindFirstRadio(pbtfrp: ptr BLUETOOTH_FIND_RADIO_PARAMS, phRadio: ptr int): int {.stdcall, dynlib: "bthprops.cpl", importc.}
proc BluetoothFindRadioClose(hFind: int): int32 {.stdcall, dynlib: "bthprops.cpl", importc.}

# --- SendInput Mouse API (come DS4Windows) ---
type
  MOUSEINPUT {.pure.} = object
    dx: int32
    dy: int32
    mouseData: uint32
    flags: uint32
    time: uint32
    extraInfo: pointer

  INPUT {.pure.} = object
    inputType: uint32
    mi: MOUSEINPUT

const
  INPUT_MOUSE = 0'u32
  MOUSEEVENTF_MOVE = 0x0001'u32
  MOUSEEVENTF_LEFTDOWN = 0x0002'u32
  MOUSEEVENTF_LEFTUP = 0x0004'u32
  MOUSEEVENTF_RIGHTDOWN = 0x0008'u32
  MOUSEEVENTF_RIGHTUP = 0x0010'u32

proc SendInput(cInputs: uint32, pInputs: ptr INPUT, cbSize: int32): uint32 {.stdcall, dynlib: "user32", importc.}

proc moveMouse(dx, dy: int32) =
  var inp: INPUT
  inp.inputType = INPUT_MOUSE
  inp.mi.flags = MOUSEEVENTF_MOVE
  inp.mi.dx = dx
  inp.mi.dy = dy
  discard SendInput(1, addr inp, cast[int32](sizeof(inp)))

proc clickMouse(flags: uint32) =
  var inp: INPUT
  inp.inputType = INPUT_MOUSE
  inp.mi.flags = flags
  discard SendInput(1, addr inp, cast[int32](sizeof(inp)))

# --- Controller Logic ---
type
  ControllerType = enum
    Unknown, DS4, DualSense

const
  VID_SONY = 0x054C'u16
  PID_DS4_V1 = 0x05C4'u16
  PID_DS4_V2 = 0x09CC'u16
  PID_DUALSENSE = 0x0CE6'u16

proc mapAnalog(val: uint8): int16 =
  # Map range 0-255 to -32768 to 32767
  result = cast[int16]((int32(val) * 257) - 32768)

const
  touchpadSensitivity = 0.7     # Modificabile: 0.5 = metà velocità, 1.0 = normale, 2.0 = doppio
  touchpadClickDeadzone = 12    # Pixel touch ignorati durante il click (evita movimenti accidentali)

var
  lastTouchX = 0
  lastTouchY = 0
  lastTouchActive = false
  lastTouchActive2 = false
  lastTouchID = 0'u8
  lastTouchClick = false
  rightClickActive = false
  touchRemainderX = 0.0
  touchRemainderY = 0.0
  clickActive = false
  clickStartX = 0
  clickStartY = 0

# Rumble/Force Feedback state
var
  currentLargeMotor: uint8 = 0
  currentSmallMotor: uint8 = 0
  lastRumbleSendTime: float = 0
  rumbleCheckCounter: int = 0
  controllerIsBT: bool = false   # Stored when device is opened

# Force Feedback callback (chiamato da thread interno ViGEmClient)
var
  rumblePendingLargeMotor: uint8 = 0
  rumblePendingSmallMotor: uint8 = 0
  rumblePendingFlag: bool = false

proc handleTouchpad(data: array[100, uint8], touchOffset: int, touchClick: bool) =
  # --- Legge il touch count (byte 33 per DS4, 31 per DualSense) ---
  let touchCount = data[touchOffset - 2]
  
  # --- Gestione click fisico (funziona sempre, anche se touchCount = 0) ---
  if touchClick and not lastTouchClick:
    # Click: se entrambi i tocchi sono attivi → right click, altrimenti left
    if touchCount >= 2 and (data[touchOffset] and 0x80) == 0 and (data[touchOffset + 4] and 0x80) == 0:
      clickMouse(MOUSEEVENTF_RIGHTDOWN)
      rightClickActive = true
    else:
      clickMouse(MOUSEEVENTF_LEFTDOWN)
      rightClickActive = false
    # Attiva deadzone: evita movimenti accidentali durante il clic
    if touchCount > 0:
      clickActive = true
      clickStartX = int(data[touchOffset + 1]) + ((int(data[touchOffset + 2]) and 0x0F) * 255)
      clickStartY = ((int(data[touchOffset + 2]) and 0xF0) shr 4) + (int(data[touchOffset + 3]) * 16)
  elif not touchClick and lastTouchClick:
    if rightClickActive:
      clickMouse(MOUSEEVENTF_RIGHTUP)
      rightClickActive = false
    else:
      clickMouse(MOUSEEVENTF_LEFTUP)
    clickActive = false
  lastTouchClick = touchClick

  # --- Se touchCount = 0, non ci sono tocchi → resetta stati ed esce ---
  if touchCount == 0:
    lastTouchActive = false
    lastTouchActive2 = false
    return

  # --- Da qui in poi: touchCount > 0, ci sono tocchi validi ---
  let t1byte = data[touchOffset]
  let t2byte = data[touchOffset + 4]

  # Touch active: bit 7 = 0 significa tocco presente
  let touch1Active = (t1byte and 0x80) == 0
  let touch1ID = t1byte and 0x7F
  let touch2Active = (t2byte and 0x80) == 0

  # Coordinate: formula DS4Windows
  let currentX1 = int(data[touchOffset + 1]) + ((int(data[touchOffset + 2]) and 0x0F) * 255)
  let currentY1 = ((int(data[touchOffset + 2]) and 0xF0) shr 4) + (int(data[touchOffset + 3]) * 16)

  # --- Touch 1: movimento del mouse ---
  if touch1Active:
    if lastTouchActive and lastTouchID == touch1ID:
      let rawDx = int32(currentX1 - lastTouchX)
      let rawDy = int32(currentY1 - lastTouchY)

      if (rawDx != 0 or rawDy != 0) and not touch2Active:
        # Click deadzone: durante il click ignora piccoli movimenti accidentali
        var shouldMove = true
        if clickActive:
          let totalDx = abs(currentX1 - clickStartX)
          let totalDy = abs(currentY1 - clickStartY)
          if totalDx < touchpadClickDeadzone and totalDy < touchpadClickDeadzone:
            shouldMove = false # Ancora nella deadzone, non muovere il cursore
          else:
            clickActive = false # Uscito dalla deadzone
        
        if shouldMove:
          var xMotion = float(rawDx) * touchpadSensitivity + touchRemainderX
          var yMotion = float(rawDy) * touchpadSensitivity + touchRemainderY
          let xAction = int32(xMotion)
          let yAction = int32(yMotion)
          touchRemainderX = xMotion - float(xAction)
          touchRemainderY = yMotion - float(yAction)
          if xAction != 0 or yAction != 0:
            moveMouse(xAction, yAction)
    else:
      touchRemainderX = 0.0
      touchRemainderY = 0.0

    lastTouchX = currentX1
    lastTouchY = currentY1
    lastTouchID = touch1ID

  lastTouchActive = touch1Active
  lastTouchActive2 = touch2Active

proc parseDpad(val: uint8, buttons: var uint16) =
  let dpad = val and 0x0F
  case dpad:
    of 0: buttons = buttons or XUSB_GAMEPAD_DPAD_UP
    of 1: buttons = buttons or XUSB_GAMEPAD_DPAD_UP or XUSB_GAMEPAD_DPAD_RIGHT
    of 2: buttons = buttons or XUSB_GAMEPAD_DPAD_RIGHT
    of 3: buttons = buttons or XUSB_GAMEPAD_DPAD_DOWN or XUSB_GAMEPAD_DPAD_RIGHT
    of 4: buttons = buttons or XUSB_GAMEPAD_DPAD_DOWN
    of 5: buttons = buttons or XUSB_GAMEPAD_DPAD_DOWN or XUSB_GAMEPAD_DPAD_LEFT
    of 6: buttons = buttons or XUSB_GAMEPAD_DPAD_LEFT
    of 7: buttons = buttons or XUSB_GAMEPAD_DPAD_UP or XUSB_GAMEPAD_DPAD_LEFT
    else: discard

proc parseDS4(data: array[100, uint8], report: var XUSB_REPORT): tuple[valid: bool, disconnect: bool, closeApp: bool] =
  var offset = 0
  var touchOffset = 35
  if data[0] == 0x11:
    offset = 2
    touchOffset = 35 + 2 # L'offset per il touchpad su BT è 37
  elif data[0] == 0x01:
    offset = 0
    touchOffset = 35
  else:
    return (false, false, false) # Ignore other report types (e.g. calibration)

  report.wButtons = 0
  
  # Analog Axes
  report.sThumbLX = mapAnalog(data[1 + offset])
  report.sThumbLY = mapAnalog(not data[2 + offset]) # Invert Y axis
  report.sThumbRX = mapAnalog(data[3 + offset])
  report.sThumbRY = mapAnalog(not data[4 + offset]) # Invert Y axis
  
  # Analog Triggers
  report.bLeftTrigger = data[8 + offset]
  report.bRightTrigger = data[9 + offset]
  
  # D-Pad and Main Buttons (Byte 5)
  parseDpad(data[5 + offset], report.wButtons)
  if (data[5 + offset] and 0x10) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_X # Square -> X
  if (data[5 + offset] and 0x20) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_A # Cross -> A
  if (data[5 + offset] and 0x40) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_B # Circle -> B
  if (data[5 + offset] and 0x80) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_Y # Triangle -> Y
  
  # Secondary Buttons (Byte 6)
  if (data[6 + offset] and 0x01) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_LEFT_SHOULDER # L1
  if (data[6 + offset] and 0x02) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_RIGHT_SHOULDER # R1
  if (data[6 + offset] and 0x10) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_BACK # Share -> Back
  if (data[6 + offset] and 0x20) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_START # Options -> Start
  if (data[6 + offset] and 0x40) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_LEFT_THUMB # L3
  if (data[6 + offset] and 0x80) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_RIGHT_THUMB # R3
  
  # PS Button (Byte 7) and Disconnect Macro
  let psPressed = (data[7 + offset] and 0x01) != 0
  let optionsPressed = (data[6 + offset] and 0x20) != 0
  let circlePressed = (data[5 + offset] and 0x40) != 0
  let touchClick = (data[7 + offset] and 0x02) != 0
  
  if psPressed: report.wButtons = report.wButtons or XUSB_GAMEPAD_GUIDE
  
  # Trackpad Handling (Touch data offset: 35 for USB, 35+2=37 for BT)
  handleTouchpad(data, touchOffset, touchClick)

  return (true, psPressed and optionsPressed, psPressed and circlePressed)

proc parseDualSense(data: array[100, uint8], report: var XUSB_REPORT): tuple[valid: bool, disconnect: bool, closeApp: bool] =
  var offset = 0
  var touchOffset = 33
  if data[0] == 0x31:
    offset = 1
    touchOffset = 33 + 1 # L'offset per il touchpad su BT è 34
  elif data[0] == 0x01:
    offset = 0
    touchOffset = 33
  else:
    return (false, false, false)

  report.wButtons = 0
  
  # Analog Axes
  report.sThumbLX = mapAnalog(data[1 + offset])
  report.sThumbLY = mapAnalog(not data[2 + offset])
  report.sThumbRX = mapAnalog(data[3 + offset])
  report.sThumbRY = mapAnalog(not data[4 + offset])
  
  # Analog Triggers
  report.bLeftTrigger = data[5 + offset]
  report.bRightTrigger = data[6 + offset]
  
  # D-Pad and Main Buttons (Byte 8)
  parseDpad(data[8 + offset], report.wButtons)
  if (data[8 + offset] and 0x10) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_X
  if (data[8 + offset] and 0x20) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_A
  if (data[8 + offset] and 0x40) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_B
  if (data[8 + offset] and 0x80) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_Y
  
  # Secondary Buttons (Byte 9)
  if (data[9 + offset] and 0x01) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_LEFT_SHOULDER # L1
  if (data[9 + offset] and 0x02) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_RIGHT_SHOULDER # R1
  if (data[9 + offset] and 0x10) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_BACK # Create -> Back
  if (data[9 + offset] and 0x20) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_START # Options -> Start
  if (data[9 + offset] and 0x40) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_LEFT_THUMB # L3
  if (data[9 + offset] and 0x80) != 0: report.wButtons = report.wButtons or XUSB_GAMEPAD_RIGHT_THUMB # R3
  
  # PS Button (Byte 10) and Disconnect Macro
  let psPressed = (data[10 + offset] and 0x01) != 0
  let optionsPressed = (data[9 + offset] and 0x20) != 0
  let circlePressed = (data[8 + offset] and 0x40) != 0
  let touchClick = (data[10 + offset] and 0x02) != 0
  
  if psPressed: report.wButtons = report.wButtons or XUSB_GAMEPAD_GUIDE
  
  # Trackpad Handling (Touch data offset: 33 for USB, 33+1=34 for BT)
  handleTouchpad(data, touchOffset, touchClick)

  return (true, psPressed and optionsPressed, psPressed and circlePressed)

proc parseMacAddress(macStr: string): uint64 =
  var cleanMac = macStr.replace(":", "").replace("-", "")
  if cleanMac.len != 12: return 0
  try:
    result = parseHexInt(cleanMac).uint64
  except:
    result = 0

proc sendRumbleToDS4(dev: hid_device, cType: ControllerType, isBluetooth: bool, largeMotor, smallMotor: uint8) =
  ## Invia il force feedback (rumble) al controller DS4 fisico.
  ## largeMotor = motore lento/sinistro (0-255)
  ## smallMotor = motore veloce/destro (0-255)
  if cType == ControllerType.DS4:
    if isBluetooth:
      var btRep: array[78, uint8]
      btRep[0] = 0x11
      btRep[1] = 0x80
      btRep[3] = 0xFF
      btRep[6] = smallMotor   # Right/fast motor
      btRep[7] = largeMotor    # Left/slow motor
      # LED lightbar (default: DS4 blue glow, personalizzabile in futuro)
      btRep[8] = 0    # R
      btRep[9] = 0    # G
      btRep[10] = 64  # B (64 = intensità medio-bassa, evita abbagliamento)
      
      let devObj = cast[HidDevicePtr](dev)
      let hHandle = devObj.device_handle
      discard HidD_SetOutputReport(hHandle, addr btRep[0], int32(sizeof(btRep)))
    else:
      var usbRep: array[32, uint8]
      usbRep[0] = 0x05
      usbRep[1] = 0xFF
      usbRep[4] = smallMotor   # Right/fast motor
      usbRep[5] = largeMotor    # Left/slow motor
      # LED lightbar
      usbRep[6] = 0    # R
      usbRep[7] = 0    # G
      usbRep[8] = 64  # B
      # no flash (sempre acceso)
      usbRep[9] = 0   # Flash on
      usbRep[10] = 0  # Flash off
      
      discard hid_write(dev, addr usbRep[0], csize_t(sizeof(usbRep)))
    lastRumbleSendTime = epochTime()

# Callback chiamata da ViGEmClient quando il gioco invia force feedback
proc rumbleNotificationCallback(client: PVIGEM_CLIENT, target: PVIGEM_TARGET, largeMotor: uint8, smallMotor: uint8, ledNumber: uint8, userData: pointer) {.stdcall.} =
  rumblePendingLargeMotor = largeMotor
  rumblePendingSmallMotor = smallMotor
  rumblePendingFlag = true

proc wakeupController(dev: hid_device, cType: ControllerType, isBluetooth: bool) =
  if cType == ControllerType.DS4:
    if isBluetooth:
      # Metodo BT: output report da 78 byte
      var btRep: array[78, uint8]
      btRep[0] = 0x11     # HID report ID per BT
      btRep[1] = 0x80     # Flags: enable rumble/LED
      btRep[3] = 0xFF     # Flags: enable tutto
      # LED lightbar default (DS4 blue)
      btRep[8] = 0    # R
      btRep[9] = 0    # G
      btRep[10] = 64  # B
      
      # Output report via control pipe (HidD_SetOutputReport)
      let devObj = cast[HidDevicePtr](dev)
      let hHandle = devObj.device_handle
      let w2 = HidD_SetOutputReport(hHandle, addr btRep[0], int32(sizeof(btRep)))
      let gle2 = GetLastError()
      if not w2:
        logMsg("ERROR: HidD_SetOutputReport BT fallita gle=" & $gle2)
    else:
      # Metodo USB: output report via hid_write
      var usbRep: array[32, uint8]
      usbRep[0] = 0x05
      usbRep[1] = 0xFF
      # LED lightbar default (DS4 blue)
      usbRep[6] = 0    # R
      usbRep[7] = 0    # G
      usbRep[8] = 64  # B
      discard hid_write(dev, addr usbRep[0], csize_t(sizeof(usbRep)))
    
    # Metodo feature report 0x02 (legacy)
    var legacyRep: array[78, uint8]
    legacyRep[0] = 0x02
    discard hid_send_feature_report(dev, addr legacyRep[0], csize_t(sizeof(legacyRep)))
  elif cType == ControllerType.DualSense:
    if isBluetooth:
      # Send an output report 0x31 to enable extended data on Bluetooth
      var outputReport: array[78, uint8]
      outputReport[0] = 0x31
      outputReport[1] = 0x00
      outputReport[2] = 0x10
      discard hid_write(dev, addr outputReport[0], csize_t(sizeof(outputReport)))
    else:
      # Send an output report 0x02 to enable extended data on USB
      var outputReport: array[63, uint8]
      outputReport[0] = 0x02
      discard hid_write(dev, addr outputReport[0], csize_t(sizeof(outputReport)))

proc disconnectController(dev: hid_device, cType: ControllerType) =
  # 1. Get the MAC address of the controller
  var serialBuf: array[256, uint16]
  if hid_get_serial_number_string(dev, addr serialBuf[0], 256) == 0:
    var macStr = ""
    for i in 0..<256:
      if serialBuf[i] == 0: break
      macStr.add(chr(serialBuf[i]))
    
    let macAddr = parseMacAddress(macStr)
    if macAddr != 0:
      # 2. Find the main Bluetooth radio
      var params: BLUETOOTH_FIND_RADIO_PARAMS
      params.dwSize = uint32(sizeof(BLUETOOTH_FIND_RADIO_PARAMS))
      var hRadio: int = 0
      let hFind = BluetoothFindFirstRadio(addr params, addr hRadio)
      
      if hFind != 0 and hRadio != 0:
        # 3. Send the disconnect command
        var btAddr = macAddr
        var bytesReturned: int32 = 0
        let success = DeviceIoControl(hRadio, IOCTL_BTH_DISCONNECT_DEVICE, addr btAddr, 8, nil, 0, addr bytesReturned, nil)
        if success == 0:
          logMsg("Error during Bluetooth API disconnection.")
        
        discard CloseHandle(hRadio)
        discard BluetoothFindRadioClose(hFind)
  
  # Fallback: Send a special packet to physically turn off the controller via Bluetooth
  if cType == ControllerType.DS4:
    var disconnectPacket: array[78, uint8]
    disconnectPacket[0] = 0x11 # Report ID for Bluetooth
    disconnectPacket[1] = 0xC0 # Flag for power off
    disconnectPacket[2] = 0x20 # Flag for power off
    discard hid_write(dev, addr disconnectPacket[0], csize_t(sizeof(disconnectPacket)))
  elif cType == ControllerType.DualSense:
    var disconnectPacket: array[78, uint8]
    disconnectPacket[0] = 0x31 # Report ID for Bluetooth
    disconnectPacket[1] = 0x02 # Flag for power off
    disconnectPacket[2] = 0x04 # Flag for power off
    discard hid_write(dev, addr disconnectPacket[0], csize_t(sizeof(disconnectPacket)))
  
  hid_close(dev)

proc regDeleteKeyValueW(hKey: HKEY, lpSubKey, lpValueName: WideCString): int32 {.
  importc: "RegDeleteKeyValueW", dynlib: "Advapi32.dll", stdcall.}

proc deleteUnicodeValue*(path, key: string; handle: HKEY) =
  let hh = newWideCString path
  let kk = newWideCString key
  let err = regDeleteKeyValueW(handle, hh, kk)
  if err != 0:
    raiseOSError(err.OSErrorCode, "regDeleteKeyValueW")

# --- Auto-Start ---
proc setupAutoStart() =
  try:
    let exePath = getAppFilename()
    setUnicodeValue(r"Software\Microsoft\Windows\CurrentVersion\Run", "DSS_Controller_Mapper", exePath, HKEY_CURRENT_USER)
  except:
    logMsg("Failed to configure auto-start.")

proc removeAutoStart() =
  try:
    deleteUnicodeValue(r"Software\Microsoft\Windows\CurrentVersion\Run", "DSS_Controller_Mapper", HKEY_CURRENT_USER)
  except:
    logMsg("Failed to remove auto-start.")

# --- Mapping Thread ---
proc mappingThreadFunc() {.thread.} =
  # Initialize HIDAPI
  if hid_init() != 0:
    logMsg("ERROR: Failed to initialize HIDAPI.")
    return
  defer: discard hid_exit()
  
  # Initialize ViGEmClient
  let client = vigem_alloc()
  if client == nil:
    logMsg("ERROR: Failed to allocate ViGEmClient.")
    return
  defer: vigem_free(client)
  
  let connectRes = vigem_connect(client)
  if connectRes != 0 and connectRes != 0x20000000:
    logMsg("ERROR: Failed to connect to ViGEmBus. Error code: " & $connectRes)
    return
  defer: vigem_disconnect(client)
  
  # Allocate and add virtual Xbox 360 controller
  var target = vigem_target_x360_alloc()
  if target == nil:
    logMsg("ERROR: Failed to allocate Xbox 360 target.")
    return
    
  let addRes = vigem_target_add(client, target)
  if addRes != 0 and addRes != 0x20000000:
    logMsg("ERROR: Failed to add virtual Xbox 360 controller. Error code: " & $addRes)
    return
  # Registra la callback per ricevere il force feedback
  discard vigem_target_x360_register_notification(client, target, rumbleNotificationCallback, nil)
  defer:
    vigem_target_x360_unregister_notification(target)
    vigem_target_remove(client, target)
    vigem_target_free(target)
  
  var 
    dev: hid_device = nil
    cType = ControllerType.Unknown
    report: XUSB_REPORT
    data: array[100, uint8]
  
  while runMapping:
    # If session is locked (e.g. Ctrl+Alt+Del), pause mapping
    # if sessionLocked:
    #   os.sleep(1000)
    #   continue
      
    if dev == nil:
      # Scan only if there was a system event (or at first startup)
      if deviceChanged:
        deviceChanged = false
        var devs = hid_enumerate(VID_SONY, 0)
        var cur = devs
        while cur != nil:
          let pathStr = $cur.path
          # Rileva Bluetooth: path BT ha formato HID#{GUID}_VID&..._PID&...
          # mentre USB ha formato HID#VID_xxxx&PID_xxxx#
          let isBT = "bthenum" in pathStr.toLowerAscii() or
                     "bluetooth" in pathStr.toLowerAscii() or
                     "00001124" in pathStr or           # Bluetooth HID GUID
                     "_PID&" in pathStr                 # formato BT: _VID&xxxx_PID&xxxx
          
          if cur.product_id == PID_DS4_V1 or cur.product_id == PID_DS4_V2:
            dev = hid_open_path(cur.path)
            if dev != nil:
              cType = ControllerType.DS4
              controllerIsBT = isBT
              wakeupController(dev, cType, isBT)
              break
          elif cur.product_id == PID_DUALSENSE:
            dev = hid_open_path(cur.path)
            if dev != nil:
              cType = ControllerType.DualSense
              controllerIsBT = isBT
              wakeupController(dev, cType, isBT)
              break
          cur = cur.next
        hid_free_enumeration(devs)
      
      if dev == nil:
        os.sleep(1000) # Wait before checking flag again
        continue
    
    # Read data with 4ms timeout (approx 250Hz)
    let bytesRead = hid_read_timeout(dev, addr data[0], csize_t(sizeof(data)), 4)
    
    if bytesRead < 0:
      # Error or controller disconnected
      hid_close(dev)
      dev = nil
      cType = ControllerType.Unknown
      deviceChanged = true
      # Reset rumble state per il prossimo controller
      currentLargeMotor = 0
      currentSmallMotor = 0
      lastRumbleSendTime = 0
      rumbleCheckCounter = 0
      continue
    elif bytesRead > 0:
      # Parse data based on controller type
      var disconnectMacro = false
      var closeAppMacro = false
      var validReport = false
      
      if cType == ControllerType.DS4:
        (validReport, disconnectMacro, closeAppMacro) = parseDS4(data, report)
      elif cType == ControllerType.DualSense:
        (validReport, disconnectMacro, closeAppMacro) = parseDualSense(data, report)
        
      if not validReport:
        continue # Ignore non-standard reports (e.g. calibration, battery)
        
      if closeAppMacro:
        #logMsg("PS + Circle detected. Disconnecting controller and closing app...")
        disconnectController(dev, cType)
        runMapping = false
        quit(0)
        
      if disconnectMacro:
        disconnectController(dev, cType)
        dev = nil
        cType = ControllerType.Unknown
        deviceChanged = true
        # Reset rumble state
        currentLargeMotor = 0
        currentSmallMotor = 0
        lastRumbleSendTime = 0
        rumbleCheckCounter = 0
        os.sleep(2000) # Pause to avoid immediate reconnection if buttons are still pressed
        continue
      
      # Send updated state to virtual Xbox 360 controller
      discard vigem_target_x360_update(client, target, report)
      
      # Controlla se la callback ha ricevuto nuovi valori di force feedback
      if rumblePendingFlag:
        rumblePendingFlag = false
        let lm = rumblePendingLargeMotor
        let sm = rumblePendingSmallMotor
        if lm != currentLargeMotor or sm != currentSmallMotor:
          currentLargeMotor = lm
          currentSmallMotor = sm
          sendRumbleToDS4(dev, cType, controllerIsBT, currentLargeMotor, currentSmallMotor)
      
      # Riavvio periodico del rumble ogni ~4s se attivo (firmware DS4 spegne dopo ~5s)
      rumbleCheckCounter += 1
      if rumbleCheckCounter >= 100:
        rumbleCheckCounter = 0
        let rumbleActive = currentLargeMotor > 0 or currentSmallMotor > 0
        if rumbleActive and (epochTime() - lastRumbleSendTime > 4.0):
          sendRumbleToDS4(dev, cType, controllerIsBT, currentLargeMotor, currentSmallMotor)
    else:
      # Timeout reached (no new data), keep loop active
      discard

# --- Message Loop Win32 ---
proc wndProc(hwnd: HWND, uMsg: UINT, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.} =
  case uMsg:
    of WM_DEVICECHANGE:
      deviceChanged = true
      return 1
    of WM_WTSSESSION_CHANGE:
      if wParam == WTS_SESSION_LOCK:
        sessionLocked = true
      elif wParam == WTS_SESSION_UNLOCK:
        sessionLocked = false
      return 0
    else:
      return DefWindowProcA(hwnd, uMsg, wParam, lParam)

proc main() =
  # Set working directory to app directory to ensure DLLs are found
  setCurrentDir(getAppDir())

  # Parse command line arguments
  let args = commandLineParams()
  if "-autostart" in args:
    setupAutoStart()
    return
  elif "-remove_autostart" in args:
    removeAutoStart()
    return
  
  # 1. Start mapping thread
  var mappingThread: Thread[void]
  createThread(mappingThread, mappingThreadFunc)
  
  # 2. Create an invisible window to receive system events
  var wc: WNDCLASSA
  wc.lpfnWndProc = wndProc
  wc.lpszClassName = "DSS_HiddenWindow"
  discard RegisterClassA(addr wc)
  
  let hwnd = CreateWindowExA(0, "DSS_HiddenWindow", "DSS", 0, 0, 0, 0, 0, 0, 0, 0, nil)
  if hwnd != 0:
    discard WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION)
    
    var msg: MSG
    while GetMessageA(addr msg, 0, 0, 0) > 0:
      discard TranslateMessage(addr msg)
      discard DispatchMessageA(addr msg)
      
    discard WTSUnRegisterSessionNotification(hwnd)
  else:
    logMsg("ERROR: Failed to create hidden window.")
  
  runMapping = false
  joinThread(mappingThread)

when isMainModule:
  try:
    main()
  except Exception as e:
    logMsg("FATAL CRASH: " & e.msg)
