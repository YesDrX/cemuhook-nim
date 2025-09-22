import std/[asyncdispatch, strformat, nativesockets, asyncnet, tables, bitops, atomics, sequtils, random]
import ./[types, crc]

proc setConnectedController*(self: CEMUHookServer, controllerSlotId: uint8, controller: ConnectedController) =
    doAssert controllerSlotId >= 0 and controllerSlotId < 4, "controllerSlotId must be between 0 and 3"
    self.connectedControllers[controllerSlotId] = controller

proc setRumbleCallback*(self: CEMUHookServer, callback: proc(slotId: int, motorId: uint8, motorVibrationIntensity: uint8)) =
    self.rumbleCallback = callback

proc sendMessageToClient*[T](self : CEMUHookServer, ip : string, port : uint16, data : pointer) {.async.} =
    if (ip, port) notin self.connectedCemuhookClients:
        echo fmt"Client {ip}:{port} not found"
        return
    
    let client = self.connectedCemuhookClients[(ip, port)]
    when T is ActualControllerDataResponse:
        client.packetNumber += 1
        let dataT = cast[ptr T](data)
        dataT.packetNumber = client.packetNumber

    let header = cast[ptr Header](data)
    header.crc32 = 0
    header.crc32 = cast[ptr UncheckedArray[byte]](data).calcCrc32(T.sizeof)
    let handle = cast[ptr AsyncSocketDescImpl](self.socket).fd

    try:
        when defined(debug):
            echo fmt"Sending response to client {ip}:{port} ---> {cast[ptr T](data)[]}"
        let isTimeout = await withTimeout(sendTo(
                    handle.AsyncFD,
                    data      = data,
                    size      = T.sizeof,
                    saddr     = client.addrInfoPtr.ai_addr,
                    saddr_len = client.addrInfoPtr.ai_addrlen.SockLen
                ), 500)
        if not isTimeout:
            raise newException(ValueError, fmt"Timeout sending response to client {ip}:{port}")
    except:
        echo fmt"Failed to send response to client {ip}:{port}" & "\n" & getCurrentExceptionMsg()
        client.errorCount += 1
        if client.errorCount > 3:
            echo fmt"Client {ip}:{port} disconnected"
            freeaddrinfo(client.addrInfoPtr)
            self.connectedCemuhookClients.del((ip, port))

proc processClientRequestImpl*(self: CEMUHookServer) {.async.} =
    var
        data, address: string
        port : Port
    try:
        (data, address, port) = await self.socket.recvFrom(1024)
    except:
        return
    
    if address.len > 0 and (ip: address, port : port.uint16) notin self.connectedCemuhookClients:
        echo fmt"New CEMUHook client connected from {address}:{port}"
        self.connectedCemuhookClients[(address, port.uint16)] = newCemuHookClient(address, port.uint16)

    if address.len > 0 and data.len > MagicLength:
        if cast[ptr array[4, uint8]](data[0].addr)[] == HeaderMagicClient:
            let n = data.len
            let header = cast[ptr Header](data[0].addr)
            let crc = header.crc32
            for idx in 8 .. 11: data[idx] = '\0' # zero out crc
            let calculated_crc = cast[ptr UncheckedArray[byte]](data[0].addr).calcCrc32(n)
            echo fmt"Request header: {header[]}"
            if calculated_crc != crc:
                echo fmt"CRC Check failed for CEMUHook client from {address}:{port}"
            else:
                case header.evtType:
                    of ProtocalVersionInfoType:
                        await sendMessageToClient[VersionInformationResponse](self, address, port.uint16, versionResponse.addr)
                    
                    of ConnectedControllerInfoType:
                        let req = cast[ptr ConnectedControllerInfoRequest](data[0].addr)
                        echo fmt"ConnectedControllerInfoRequest: {req[]}"

                        let numPorts = req.numPorts
                        for idx in 0 .. numPorts-1:
                            let slotId = req.ports[idx].uint16
                            let resp = self.controllerInfo[slotId]
                            await sendMessageToClient[ConnectedControllerInfoResponse](self, address, port.uint16, resp.addr)
                    
                    of ActualControllerDataType:
                        let req = cast[ptr ActualControllerDataRequest](data[0].addr)
                        discard # will broadcast controller state anyway

                    of ControllerMotorsInfoType:
                        let req = cast[ptr ControllerMotorsRequest](data[0].addr)
                        let slotId = req.slot
                        if slotId >= 0 and slotId <= 3:
                            let resp = ControllerMotorsResponse(
                                header : Header(
                                    magic   : HeaderMagicServer,
                                    version : HeaderVersion,
                                    id      : self.id,
                                    length  : ControllerMotorsResponse.sizeof - Header.sizeof + MessageType.sizeof,
                                    evtType : MessageType.ControllerMotorsInfoType
                                ),
                                responseStart : ResponsStart(
                                    slot           : slotId.uint8,
                                    slotState      : 2,
                                    deviceModel    : 2,
                                    connectionType : 2,
                                    batteryStatus  : BatteryStatus.Full
                                ),
                                motorCount : self.connectedControllers[slotId].motorCount
                            )
                    
                    of RumbleControllerMotorsInfoType:
                        let req = cast[ptr RumbleControllerMotorRequest](data[0].addr)
                        let slotId = req.slot
                        if slotId >= 0 and slotId <= 3:
                            if self.rumbleCallback != nil:
                                self.rumbleCallback(slotId.int, req.motorId, req.motorVibrationIntensity)
                    else:
                        discard

proc sendButtonEvent*(self: CEMUHookServer, controllerSlotId: int, buttonIdx: int, isPressed: bool) {.async.} =
    let buttonId = buttonIdx.ButtonID
    if buttonId >= ButtonID.DpadLeft and buttonId <= ButtonID.Share:
        if isPressed:
            self.controllerStates[controllerSlotId].bitMask1.setBit(ButtonID.Share.ord - buttonId.ord)
        else:
            self.controllerStates[controllerSlotId].bitMask1.clearBit(ButtonID.Share.ord - buttonId.ord)
    elif buttonId >= ButtonID.Y and buttonId <= ButtonID.L2:
        if isPressed:
            self.controllerStates[controllerSlotId].bitMask2.setBit(ButtonID.L2.ord - buttonId.ord)
        else:
            self.controllerStates[controllerSlotId].bitMask2.clearBit(ButtonID.L2.ord - buttonId.ord)
    elif buttonId == ButtonID.Home:
        self.controllerStates[controllerSlotId].homeButton = isPressed.uint8
    elif buttonId == ButtonID.Touch:
        self.controllerStates[controllerSlotId].touchButton = isPressed.uint8
    else:
        echo fmt"Invalid button index {buttonIdx}"

    let ip_port_keys = self.connectedCemuhookClients.keys.toSeq
    for (ip, port) in ip_port_keys:
        if (ip, port) in self.connectedCemuhookClients:
            await sendMessageToClient[ActualControllerDataResponse](self, ip, port, self.controllerStates[controllerSlotId].addr)

proc sendAxisEvent*(self: CEMUHookServer, controllerSlotId: int, axisIdx: int, axisValue: uint8) {.async.} =
    case axisIdx.AxisID:
        of AxisID.LeftStickX:
            self.controllerStates[controllerSlotId].leftStickX = axisValue
        of AxisID.LeftStickY:
            self.controllerStates[controllerSlotId].leftStickY = axisValue
        of AxisID.RightStickX:
            self.controllerStates[controllerSlotId].rightStickX = axisValue
        of AxisID.RightStickY:
            self.controllerStates[controllerSlotId].rightStickY = axisValue
        of AxisID.DpadLeft:
            self.controllerStates[controllerSlotId].analogDPadLeft = axisValue
        of AxisID.DpadDown:
            self.controllerStates[controllerSlotId].analogDPadDown = axisValue
        of AxisID.DpadRight:
            self.controllerStates[controllerSlotId].analogDPadRight = axisValue
        of AxisID.DpadUp:
            self.controllerStates[controllerSlotId].analogDPadUp = axisValue
        of AxisID.Y:
            self.controllerStates[controllerSlotId].analogY = axisValue
        of AxisID.B:
            self.controllerStates[controllerSlotId].analogB = axisValue
        of AxisID.A:
            self.controllerStates[controllerSlotId].analogA = axisValue
        of AxisID.X:
            self.controllerStates[controllerSlotId].analogX = axisValue
        of AxisID.R1:
            self.controllerStates[controllerSlotId].analogR1 = axisValue
        of AxisID.L1:
            self.controllerStates[controllerSlotId].analogL1 = axisValue
        of AxisID.R2:
            self.controllerStates[controllerSlotId].analogR2 = axisValue
        of AxisID.L2:
            self.controllerStates[controllerSlotId].analogL2 = axisValue
    
    let ip_port_keys = self.connectedCemuhookClients.keys.toSeq
    for (ip, port) in ip_port_keys:
        if (ip, port) in self.connectedCemuhookClients:
            await sendMessageToClient[ActualControllerDataResponse](self, ip, port, self.controllerStates[controllerSlotId].addr)

proc broadcastControllerState*(self: CEMUHookServer) {.async.} =
    while not self.shouldEnd.load:
        for slotId in self.connectedControllers.low .. self.connectedControllers.high:
            let ip_port_keys = self.connectedCemuhookClients.keys.toSeq
            for (ip, port) in ip_port_keys:
                await sendMessageToClient[ActualControllerDataResponse](self, ip, port, self.controllerStates[slotId].addr)
        await sleepAsync(self.messageIntervalMs)

proc boardcastServerVersion*(self: CEMUHookServer) {.async.} =
    while not self.shouldEnd.load:
        let ip_port_keys = self.connectedCemuhookClients.keys.toSeq
        for (ip, port) in ip_port_keys:
            await sendMessageToClient[VersionInformationResponse](self, ip, port, versionResponse.addr)
        await sleepAsync(self.checkRequestIntervalMs * 5)

proc processClientRequest*(self: CEMUHookServer) {.async.} =
    while not self.shouldEnd.load:
        await self.processClientRequestImpl()
        await sleepAsync(self.checkRequestIntervalMs)

proc debugByChangeRandomState(self: CEMUHookServer) {.async.} =
    let buttonId = 0
    var buttonState = false
    let axisIdX = 0
    var axisValueX, axisValueY : uint8 = 127
    let axisIdY = 1
    while not self.shouldEnd.load:
        buttonState = if buttonState: false else: true
        await self.sendButtonEvent(0, buttonId, buttonState)
        axisValueX = (if axisValueX > 127: 0 else: 255).uint8
        await self.sendAxisEvent(0, axisIdX, axisValueX)
        axisValueY = (if axisValueY > 127: 0 else: 255).uint8
        await self.sendAxisEvent(0, axisIdY, axisValueY)
        await sleepAsync(1000)

proc run*(self: CEMUHookServer, debugWithRandomState : bool = false) =
    echo fmt"CEMUHook server started on {self.ip}:{self.port}"
    asyncCheck self.processClientRequest()
    asyncCheck self.boardcastServerVersion()
    if debugWithRandomState:
        asyncCheck self.debugByChangeRandomState()
    waitFor self.broadcastControllerState()
    echo "CEMUHook server stopped"

proc stop*(self: CEMUHookServer) =
    self.shouldEnd.store(true)

proc asyncRun*(self: CEMUHookServer, debugWithRandomState : bool = false) =
    echo fmt"CEMUHook server started on {self.ip}:{self.port}"
    asyncCheck self.processClientRequest()
    asyncCheck self.boardcastServerVersion()
    if debugWithRandomState:
        asyncCheck self.debugByChangeRandomState()
    asyncCheck self.broadcastControllerState()
