import Carbon
import Foundation

@MainActor
final class HotkeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor () -> Void
    private(set) var registrationStatus: OSStatus = noErr

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func start() {
        guard hotKeyRef == nil else {
            return
        }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else {
                return noErr
            }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard hotKeyID.id == 1 else {
                return noErr
            }
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                service.action()
            }
            return noErr
        }, 1, &eventType, selfPointer, &handler)
        guard handlerStatus == noErr else {
            registrationStatus = handlerStatus
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4754524E), id: 1)
        registrationStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handler {
            RemoveEventHandler(handler)
        }
    }
}
