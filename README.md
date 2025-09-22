# CEMUHook - Nim Implementation

A Nim implementation of the CEMUHook protocol, which enables game controllers to communicate with applications (primarily emulators like CEMU) by emulating DS4 controller functionality. This library provides a UDP server that translates controller input events into the CEMUHook protocol format.

## Overview

CEMUHook is a [protocol](./protocal.md) that allows external applications to provide controller input data to emulators. This implementation creates a server that:
- Receives controller input events (buttons, analog sticks, motion data)
- Translates them into CEMUHook protocol messages
- Broadcasts controller state to connected clients via UDP
- Supports rumble/vibration feedback
- Provides DS4 controller emulation with full analog and digital input support

## Features

- ✅ Full DS4 controller emulation
- ✅ Button and analog stick input handling
- ✅ Motion data support (accelerometer/gyroscope)
- ✅ Touch pad simulation
- ✅ Rumble/vibration feedback
- ✅ Multi-controller support (up to 4 controllers)
- ✅ Asynchronous UDP server implementation
- ✅ CRC32 validation for message integrity

## Architecture

The project is structured into several key components:

### Core Modules

- **`types.nim`** - Defines all protocol message structures, enums, and data types
- **`server.nim`** - Implements the CEMUHook UDP server and message handling logic
- **`crc.nim`** - Provides CRC32 calculation for message validation
- **`cemuhook.nim`** - Main module that exports the public API

### Protocol Support

The implementation supports the complete CEMUHook message protocol:
- Version information exchange
- Controller connection/disconnection events
- Real-time controller data streaming
- Motor/rumble control messages
- Touch pad data

## Installation
```
nimble install https://github.com/YesDrX/cemuhook-nim.git
```
### Prerequisites

- Nim >= 2.2.4
- SDL2 library (for controller input examples)

### Examples
```bash
nim r tests/example.nim # need sdl2
nim r tests/debug.nim
```

### SDL2 Setup for SDL2 example
Download the SDL2 binary (`.dll` for Windows, `.so` for Linux) from the [SDL2 GitHub releases](https://github.com/libsdl-org/SDL/releases) and place it next to your executable or in your system PATH.

## Usage

### Basic Server Setup

```nim
import cemuhook

let server = newCemuHookServer(msgIntervalMs = 1000)
server.run()
```

### With Controller Input

```nim
import cemuhook

let server = newCemuHookServer(msgIntervalMs = 5000)
# Send button events
await server.sendButtonEvent(0, 10, true)  # Press A button on controller 0
# Send analog events  
await server.sendAxisEvent(0, 0, 128)      # Move left stick X to center
```

## Test Files Explained

### `./tests/example.nim`

This is a **comprehensive real-world example** that demonstrates how to integrate CEMUHook with actual hardware controllers using SDL2. Here's what it does:

**Key Components:**
- **SDL2 Integration**: Initializes SDL2 joystick subsystem to detect and read from physical controllers
- **Real Controller Input**: Connects to the first available joystick/gamepad
- **Event Processing**: Continuously polls for SDL2 input events and translates them to CEMUHook format
- **Asynchronous Operation**: Uses async/await for non-blocking controller event processing

**How it works:**
1. **Initialization**: Creates a CEMUHook server with 5-second message intervals
2. **Controller Detection**: Scans for connected joysticks and opens the first one found
3. **Event Loop**: Continuously processes SDL2 events:
   - **Button Events**: `JoyButtonDown`/`JoyButtonUp` → Translated to CEMUHook button events
   - **Analog Events**: `JoyAxisMotion` → Converted from SDL2's -32768 to 32767 range to CEMUHook's 0-255 range
4. **Real-time Streaming**: Immediately forwards all input events to connected CEMUHook clients

**Use Case**: This example is perfect for creating a bridge between physical controllers and emulators that support CEMUHook (like CEMU, RPCS3, etc.).

### `./tests/debug.nim`

This is a **minimal debugging/testing tool** designed for protocol validation and client testing. Here's what it does:

**Key Components:**
- **Minimal Setup**: Creates the simplest possible CEMUHook server configuration
- **Debug Mode**: Enables `debugWithRandomState = true` which generates synthetic controller data
- **Synthetic Input**: Automatically generates fake controller events for testing purposes

**How it works:**
1. **Server Creation**: Creates a CEMUHook server with 1-second message intervals (fast for debugging)
2. **Debug Mode**: The `debugWithRandomState` flag activates automatic fake input generation:
   - Toggles button states periodically
   - Cycles analog stick values between extreme positions
   - Sends this synthetic data to any connected clients
3. **Protocol Testing**: Useful for testing CEMUHook client implementations without physical hardware

**Use Case**: This is ideal for:
- Testing CEMUHook client applications
- Validating protocol implementation
- Debugging network connectivity issues
- Development when physical controllers aren't available

## API Reference

### CEMUHookServer

```nim
proc newCemuHookServer*(port: uint16 = 26760, ip: string = "127.0.0.1", msgIntervalMs: int = 1): CEMUHookServer
```
Creates a new CEMUHook server instance.

```nim
proc run*(server: CEMUHookServer, debugWithRandomState: bool = false)
```
Starts the server (blocking). Set `debugWithRandomState` to `true` for testing with synthetic input.

```nim
proc asyncRun*(server: CEMUHookServer, debugWithRandomState: bool = false)
```
Starts the server asynchronously (non-blocking).

```nim
proc sendButtonEvent*(server: CEMUHookServer, controllerSlotId: int, buttonIdx: int, isPressed: bool) {.async.}
```
Sends a button press/release event for the specified controller slot.

```nim
proc sendAxisEvent*(server: CEMUHookServer, controllerSlotId: int, axisIdx: int, axisValue: uint8) {.async.}
```
Sends an analog input event (0-255 range) for the specified axis.

```nim
proc setRumbleCallback*(server: CEMUHookServer, callback: proc(slotId: int, motorId: uint8, motorVibrationIntensity: uint8))
```
Sets a callback function to handle rumble/vibration requests from clients.

### Button and Axis IDs

The library provides enums for easy button and axis identification:

**ButtonID**: `DpadLeft`, `DpadDown`, `DpadRight`, `DpadUp`, `Options`, `L3`, `R3`, `Share`, `Y`, `B`, `A`, `X`, `R1`, `L1`, `R2`, `L2`, `Home`, `Touch`

**AxisID**: `LeftStickX`, `LeftStickY`, `RightStickX`, `RightStickY`, plus analog versions of all buttons

## License

MIT License - see the license file for details.

---

*This implementation provides a complete CEMUHook server that can bridge any input source to CEMUHook-compatible applications.*
