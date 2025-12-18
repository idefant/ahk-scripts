#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook

SoundBeep 1200, 120
TrayTip "AHK", "mouse_modes loaded", 2

; ================== НАСТРОЙКИ ==================
speedStep := 10            ; шаг изменения системной скорости (1..20)
rawUnitsPerNotch := 20     ; чувствительность raw-скролла: меньше = быстрее
maxNotchesPerMsg := 20     ; ограничение количества "щелчков" за сообщение
; ===============================================

; --- Состояния (удержание клавиш) ---
wantSlow := false
wantFast := false
wantScrollH := false
wantScrollV := false

; --- Скорость ---
baseSpeed := 0
speedMode := "none"  ; "none" | "slow" | "fast"

; --- Скролл (raw input) ---
scrollOn := false
accumX := 0.0, accumY := 0.0
anchorX := 0, anchorY := 0
rawRegistered := false

OnExit(Cleanup)

; ================== ХОТКЕИ ==================
*F13:: {
    global wantSlow
    wantSlow := true
    RecomputeModes()
}
*F13 up:: {
    global wantSlow
    wantSlow := false
    RecomputeModes()
}

*F14:: {
    global wantFast
    wantFast := true
    RecomputeModes()
}
*F14 up:: {
    global wantFast
    wantFast := false
    RecomputeModes()
}

*F15:: {
    global wantScrollH
    wantScrollH := true
    RecomputeModes()
}
*F15 up:: {
    global wantScrollH
    wantScrollH := false
    RecomputeModes()
}

*F16:: {
    global wantScrollV
    wantScrollV := true
    RecomputeModes()
}
*F16 up:: {
    global wantScrollV
    wantScrollV := false
    RecomputeModes()
}

; ================== ЛОГИКА РЕЖИМОВ ==================
RecomputeModes() {
    global wantSlow, wantFast, wantScrollH, wantScrollV

    ; 1) скорость: FAST > SLOW > NONE
    desiredSpeed := wantFast ? "fast" : (wantSlow ? "slow" : "none")
    SetSpeedMode(desiredSpeed)

    ; 2) скролл: включаем, если зажата хотя бы одна ось
    if (wantScrollH || wantScrollV)
        StartScrollMode()
    else
        StopScrollMode()
}

SetSpeedMode(mode) {
    global speedMode, baseSpeed, speedStep

    if (mode = speedMode)
        return

    ; вход в режим — сохраняем базовую скорость один раз
    if (speedMode = "none" && mode != "none")
        baseSpeed := GetMouseSpeed()

    if (mode = "none") {
        if (baseSpeed)
            SetMouseSpeed(baseSpeed)
        baseSpeed := 0
        speedMode := "none"
        ToolTip
        return
    }

    target := baseSpeed + ((mode = "fast") ? speedStep : -speedStep)
    target := Clamp(target, 1, 20)
    SetMouseSpeed(target)

    speedMode := mode
    ToolTip (mode = "fast") ? "FAST MOUSE" : "SLOW MOUSE"
    SoundBeep 1400, 60
}

; ================== RAW INPUT SCROLL ==================
WM_INPUT := 0x00FF
RID_INPUT := 0x10000003
RIDEV_INPUTSINK := 0x00000100

OnMessage(WM_INPUT, WM_INPUT_Handler)

StartScrollMode() {
    global scrollOn, anchorX, anchorY, accumX, accumY, rawRegistered

    if (scrollOn)
        return

    CoordMode "Mouse", "Screen"
    MouseGetPos &anchorX, &anchorY

    ; зафиксировать курсор в точке
    DllCall("SetCursorPos", "Int", anchorX, "Int", anchorY)
    ClipCursorToPoint(anchorX, anchorY)

    accumX := 0.0
    accumY := 0.0
    scrollOn := true

    if (!rawRegistered) {
        RegisterRawMouse(A_ScriptHwnd)
        rawRegistered := true
    }
}

StopScrollMode() {
    global scrollOn
    if (!scrollOn)
        return
    scrollOn := false
    DllCall("ClipCursor", "Ptr", 0)
}

WM_INPUT_Handler(wParam, lParam, msg, hwnd) {
    global scrollOn, wantScrollH, wantScrollV
    global accumX, accumY, rawUnitsPerNotch, maxNotchesPerMsg, RID_INPUT

    if (!scrollOn)
        return

    size := 0
    headerSize := 8 + 2 * A_PtrSize

    ; узнать размер
    DllCall("GetRawInputData", "Ptr", lParam, "UInt", RID_INPUT, "Ptr", 0, "UIntP", &size, "UInt", headerSize)
    if (size = 0)
        return

    buf := Buffer(size)
    if (DllCall("GetRawInputData", "Ptr", lParam, "UInt", RID_INPUT, "Ptr", buf, "UIntP", &size, "UInt", headerSize) =
    0)
        return

    off := headerSize
    dx := NumGet(buf, off + 12, "Int")
    dy := NumGet(buf, off + 16, "Int")

    ; накапливаем raw-смещения
    accumX += dx
    accumY += dy

    ; если ось не активна — сбрасываем её накопитель, чтобы "не стрельнуло" при следующем удержании
    if (wantScrollV)
        SendAxisRaw(&accumY, rawUnitsPerNotch, "V", maxNotchesPerMsg)
    else
        accumY := 0.0

    if (wantScrollH)
        SendAxisRaw(&accumX, rawUnitsPerNotch, "H", maxNotchesPerMsg)
    else
        accumX := 0.0
}

SendAxisRaw(&accum, threshold, axis, cap) {
    notches := Floor(Abs(accum) / threshold)
    if (notches <= 0)
        return

    if (notches > cap)
        notches := cap

    dir := (accum > 0) ? 1 : -1

    loop notches {
        if (axis = "V")
            Send dir > 0 ? "{WheelDown}" : "{WheelUp}"
        else
            Send dir > 0 ? "{WheelRight}" : "{WheelLeft}"
    }

    accum -= dir * notches * threshold
}

ClipCursorToPoint(x, y) {
    rect := Buffer(16, 0)
    NumPut("Int", x, rect, 0)
    NumPut("Int", y, rect, 4)
    NumPut("Int", x + 1, rect, 8)
    NumPut("Int", y + 1, rect, 12)
    DllCall("ClipCursor", "Ptr", rect)
}

RegisterRawMouse(hwnd) {
    global RIDEV_INPUTSINK
    ridSize := 8 + A_PtrSize
    rid := Buffer(ridSize, 0)

    NumPut("UShort", 1, rid, 0)             ; HID_USAGE_PAGE_GENERIC
    NumPut("UShort", 2, rid, 2)             ; HID_USAGE_GENERIC_MOUSE
    NumPut("UInt", RIDEV_INPUTSINK, rid, 4) ; INPUTSINK
    NumPut("Ptr", hwnd, rid, 8)

    DllCall("RegisterRawInputDevices", "Ptr", rid, "UInt", 1, "UInt", ridSize)
}

; ================== WIN API: MOUSE SPEED ==================
GetMouseSpeed() {
    SPI_GETMOUSESPEED := 0x0070
    speed := 0
    DllCall("SystemParametersInfo", "UInt", SPI_GETMOUSESPEED, "UInt", 0, "UIntP", &speed, "UInt", 0)
    return speed
}

SetMouseSpeed(speed) {
    SPI_SETMOUSESPEED := 0x0071
    speed := Clamp(speed, 1, 20)
    DllCall("SystemParametersInfo", "UInt", SPI_SETMOUSESPEED, "UInt", 0, "UInt", speed, "UInt", 0)
}

Clamp(v, lo, hi) => (v < lo) ? lo : (v > hi) ? hi : v

Cleanup(*) {
    global baseSpeed, speedMode
    try DllCall("ClipCursor", "Ptr", 0)
    if (speedMode != "none" && baseSpeed)
        try SetMouseSpeed(baseSpeed)
}
