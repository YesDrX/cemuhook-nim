import std/[asyncdispatch, strformat]

import cemuhook

import sdl2 # download sdl2 binary (.dll/.so) from github and put it next to your executable
import sdl2/joystick

proc processJoystickEvents(server : CEMUHookServer) {.async.} =
    if init(INIT_JOYSTICK) != SDL_Return.SdlSuccess:
        raise newException(Exception, "Failed to initialize SDL2 joystick: " & $getError())
    let joysticksCount = numJoysticks()
    if joysticksCount == 0:
        raise newException(Exception, "No joysticks found")
    let joystick = joystickOpen(0)
    let joystickName = joystickName(joystick)
    echo fmt"Connected joystick: {joystickName}"
    
    var event : Event
    while true:
        discard sdl2.pollEvent(event)
        case event.kind:
            of JoyButtonDown, JoyButtonUp:
                let joyBtnEvt = cast[ptr JoyButtonEventObj](event.addr)
                await server.sendButtonEvent(0, joyBtnEvt.button.int, joyBtnEvt.state > 0)
            of JoyAxisMotion:
                let joyAxisEvt = cast[ptr JoyAxisEventObj](event.addr)
                let axisValue = (joyAxisEvt.value + 32768) div 256 # -32768 to 32767 ---> 0 to 255
                await server.sendAxisEvent(0, joyAxisEvt.axis.int, axisValue.uint8)
            else:
                discard
        await sleepAsync(1)

proc main() =
    let server = newCemuHookServer(msgIntervalMs = 5000)
    asyncRun(server)
    waitFor server.processJoystickEvents()

when isMainModule:
    main()
