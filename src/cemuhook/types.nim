import std/[tables, asyncnet, nativesockets, strformat, asyncdispatch, atomics, random]

type
    CEMUBitmask1* {.size:sizeof(uint8).} = enum
        DpadLeft  = 0b10000000
        DpadDown  = 0b01000000
        DpadRight = 0b00100000
        DpadUp    = 0b00010000
        Options   = 0b00001000
        L3        = 0b00000100
        R3        = 0b00000010
        Share     = 0b00000001
    
    CEMUBitmask2* {.size:sizeof(uint8).} = enum
        Y         = 0b10000000
        B         = 0b01000000
        A         = 0b00100000
        X         = 0b00010000
        R1        = 0b00001000
        L1        = 0b00000100
        R2        = 0b00000010
        L2        = 0b00000001

    ButtonID* {.size: sizeof(uint8).} = enum
        DpadLeft  = 0
        DpadDown  = 1
        DpadRight = 2
        DpadUp    = 3
        Options   = 4
        L3        = 5
        R3        = 6
        Share     = 7
        Y         = 8
        B         = 9
        A         = 10
        X         = 11
        R1        = 12
        L1        = 13
        R2        = 14
        L2        = 15
        Home      = 16
        Touch     = 17
    
    AxisID* {.size: sizeof(uint8).} = enum # Analog
        LeftStickX  = 0
        LeftStickY  = 1
        RightStickX = 2
        RightStickY = 3
        DpadLeft    = 4
        DpadDown    = 5
        DpadRight   = 6
        DpadUp      = 7
        Y           = 8
        B           = 9
        A           = 10
        X           = 11
        R1          = 12
        L1          = 13
        R2          = 14
        L2          = 15

    MessageType* {.size: sizeof(uint32).} = enum
        ProtocalVersionInfoType        = 0x100000
        ConnectedControllerInfoType    = 0x100001
        ActualControllerDataType       = 0x100002
        ControllerMotorsInfoType       = 0x110001 # Unofficial
        RumbleControllerMotorsInfoType = 0x110002 # Unofficial

    Header* {.packed.} = object
        magic*      : array[4, uint8] # 4 bytes
        version*    : uint16 # 2 bytes
        length*     : uint16 # 2 bytes
        crc32*      : uint32 # 4 bytes
        id*         : uint32 # 4 bytes
        evtType*    : MessageType # 4 bytes

    VersionInformationRequest* {.packed.} = object
        header*        : Header
    
    VersionInformationResponse* {.packed.} = object
        header*        : Header
        version*       : uint16 # 2 bytes

    BatteryStatus* {.size: sizeof(uint8).} = enum
        NotApplicable = 0x00
        Dying         = 0x01
        Low           = 0x02
        Medium        = 0x03
        High          = 0x04
        Full          = 0x05
        Charging      = 0xEE
        Charged       = 0xEF

    ResponsStart* {.packed.} = object
        slot*           : uint8 # 1 byte
        slotState*      : uint8 # 1 byte # 0 = not connected, 1 = reserved, 2 = connected
        deviceModel*    : uint8 # 1 byte # 0 = applicable, 1 = no or partial gryo, 2 = full gryo, 3 = not used
        connectionType* : uint8 # 1 byte # 0 = not applicable, 1 = usb, 2 = bluetooth
        macAddress*     : array[6, uint8] # 6 bytes
        batteryStatus*  : BatteryStatus # 1 byte

    ConnectedControllerInfoRequest* {.packed.} = object
        header*     : Header
        numPorts*   : int32 # 4 bytes
        ports*      : array[4, byte] # 1 - 4 bytes
    
    ConnectedControllerInfoResponse* {.packed.} = object
        header*        : Header
        responseStart* : ResponsStart # 11 bytes
        empty*         : uint8  = 0   # 1
    
    ActualControllerDataRequestAction* {.size: sizeof(uint8).} = enum
        SlotBasedRegistration = 1
        MacBasedRegistration  = 2
        SubscribeAll          = 0

    ActualControllerDataRequest* {.packed.} = object
        header*     : Header
        action*     : ActualControllerDataRequestAction
        slot*       : uint8 # 1 byte
        macAddress* : array[6, uint8] # 6 bytes
    
    ActualControllerDataResponseTouchData* {.packed.} = object
        isTouchActive* : uint8  # 1 byte # 0 = not active, 1 = active
        touchId*       : uint8  # 1 byte
        x*             : uint16 # 2 bytes
        y*             : uint16 # 2 bytes

    ActualControllerDataResponse* {.packed.} = object
        header*                : Header
        responseStart*         : ResponsStart # 11 bytes
        isControllerConnected* : uint8  = 1 # 1 byte # 1 = connected, 0 = not connected
        packetNumber*          : uint32 # 4 bytes
        bitMask1*              : uint8  # 1 byte
        bitMask2*              : uint8  # 1 byte
        homeButton*            : uint8  # 1 byte
        touchButton*           : uint8  # 1 byte
        leftStickX*            : uint8  # 1 byte
        leftStickY*            : uint8  # 1 byte
        rightStickX*           : uint8  # 1 byte
        rightStickY*           : uint8  # 1 byte
        analogDPadLeft*        : uint8  # 1 byte
        analogDPadDown*        : uint8  # 1 byte
        analogDPadRight*       : uint8  # 1 byte
        analogDPadUp*          : uint8  # 1 byte
        analogY*               : uint8  # 1 byte
        analogB*               : uint8  # 1 byte
        analogA*               : uint8  # 1 byte
        analogX*               : uint8  # 1 byte
        analogR1*              : uint8  # 1 byte
        analogL1*              : uint8  # 1 byte
        analogR2*              : uint8  # 1 byte
        analogL2*              : uint8  # 1 byte
        firstTouch*            : ActualControllerDataResponseTouchData # 6 bytes
        secondTouch*           : ActualControllerDataResponseTouchData # 6 bytes
        motionDataTimestamp*   : uint64  # 8 bytes
        accelerometerX*        : float32 # 4 bytes
        accelerometerY*        : float32 # 4 bytes
        accelerometerZ*        : float32 # 4 bytes
        gyroPitch*             : float32 # 4 bytes
        gyroYaw*               : float32 # 4 bytes
        gyroRoll*              : float32 # 4 bytes

    ControllerMotorsRequest* {.packed.} = object
        header*         : Header
        action*         : ActualControllerDataRequestAction
        slot*           : uint8 # 1 byte
        macAddress*     : array[6, uint8] # 6 bytes
    
    ControllerMotorsResponse* {.packed.} = object
        header*        : Header
        responseStart* : ResponsStart # 11 bytes
        motorCount*    : uint8 # 1 byte # 0 = no rumble support, 1 = single motor, 2 = left/right motors
    
    RumbleControllerMotorRequest* {.packed.} = object
        header*                  : Header
        action*                  : ActualControllerDataRequestAction
        slot*                    : uint8 # 1 byte
        macAddress*              : array[6, uint8] # 6 bytes
        motorId*                 : uint8 # 1 byte # 0 .. motorCount-1
        motorVibrationIntensity* : uint8 # 1 byte # 0 .. 255, 0 = no vibration
    
    ConnectedController* = object
        name*       : string
        macAddress* : array[6, uint8]
        slotState*  : uint8 = 2 # 1 byte # 0 = not connected, 1 = reserved, 2 = connected
        motorCount* : uint8 = 2
    
    CEMUHookClient* = ref object
        ip*              : string
        port*            : uint16
        errorCount*      : int = 0
        packetNumber*    : uint32
        addrInfoPtr*     : ptr AddrInfo

    CEMUHookServer* = ref object
        ip*                      : string
        port*                    : uint16
        socket*                  : AsyncSocket
        connectedControllers*    : array[4, ConnectedController]
        controllerInfo*          : array[4, ConnectedControllerInfoResponse]
        controllerStates*        : array[4, ActualControllerDataResponse]
        connectedCemuhookClients*: Table[tuple[ip: string, port: uint16], CEMUHookClient]
        rumbleCallback*          : proc(slotId: int, motorId: uint8, motorVibrationIntensity: uint8) = nil
        shouldEnd*               : Atomic[bool]
        messageIntervalMs*       : int = 1
        checkRequestIntervalMs*  : int = 1000
        id*                      : uint32

    AsyncSocketDescImpl* = object
        fd*: SocketHandle

const
    MagicLength*       = 4
    HeaderMagicServer* = ['D'.uint8, 'S'.uint8, 'U'.uint8, 'S'.uint8]
    HeaderMagicClient* = ['D'.uint8, 'S'.uint8, 'U'.uint8, 'C'.uint8]
    HeaderVersion*     = 1001.uint16

var
    versionResponse* = VersionInformationResponse(
        header : Header(
            magic   : HeaderMagicServer,
            version : HeaderVersion,
            length  : VersionInformationResponse.sizeof - Header.sizeof + MessageType.sizeof,
            evtType : MessageType.ProtocalVersionInfoType
        ),
        version : HeaderVersion
    )

proc newCemuHookClient*(ip : string, port : uint16): CEMUHookClient =
    new(result)
    result.ip = ip
    result.port = port
    result.addrInfoPtr = getAddrInfo(ip, port.Port, AF_INET, SOCK_DGRAM, IPPROTO_UDP)

proc newCemuHookServer*(port : uint16 = 26760, ip : string = "127.0.0.1", msgIntervalMs : int = 1): CEMUHookServer =
    new(result)
    result.ip = ip
    result.port = port
    result.messageIntervalMs = msgIntervalMs
    result.socket = newAsyncSocket(domain = AF_INET, sockType = SOCK_DGRAM, protocol = IPPROTO_UDP)
    result.socket.bindAddr(Port(port), ip)
    result.connectedCemuhookClients = initTable[tuple[ip: string, port: uint16], CEMUHookClient]()
    result.shouldEnd.store(false)
    result.id = rand(int32.high).uint32
    for slotId in 0 .. 3:
        result.controllerInfo[slotId] = ConnectedControllerInfoResponse(
            header : Header(
                magic   : HeaderMagicServer,
                version : HeaderVersion,
                id      : result.id,
                length  : ConnectedControllerInfoResponse.sizeof - Header.sizeof + MessageType.sizeof,
                evtType : MessageType.ConnectedControllerInfoType
            ),
            responseStart : ResponsStart(
                slot           : slotId.uint8,
                slotState      : 2,
                deviceModel    : 2,
                connectionType : 2,
                batteryStatus  : BatteryStatus.Full
            ),
            empty : 0
        )
        result.controllerStates[slotId] = ActualControllerDataResponse(
            header : Header(
                magic   : HeaderMagicServer,
                version : HeaderVersion,
                id      : result.id,
                length  : ActualControllerDataResponse.sizeof - Header.sizeof + MessageType.sizeof,
                evtType : MessageType.ActualControllerDataType
            ),
            responseStart : ResponsStart(
                slot           : slotId.uint8,
                slotState      : 2,
                deviceModel    : 2,
                connectionType : 2,
                batteryStatus  : BatteryStatus.Full
            )
        )
    versionResponse.header.id = result.id
