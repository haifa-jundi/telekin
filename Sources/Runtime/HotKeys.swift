import Carbon
import Foundation

/// Global keyboard shortcuts through Carbon hot keys (no extra permission needed).
final class HotKeys {
    struct Binding {
        let keyCode: UInt32
        let modifiers: UInt32
        let action: () -> Void
    }

    private static let signature: OSType = 0x5445_4C4B // "TELK"
    private var registered: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    init(_ bindings: [Binding]) {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKey = EventHotKeyID()
            let read = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                         nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            guard read == noErr else { return read }
            let owner = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            owner.actions[hotKey.id]?()
            return noErr
        }, 1, &spec, context, &handler)
        if status != noErr { NSLog("Telekin: hot key handler failed (%d)", status) }

        for (index, binding) in bindings.enumerated() {
            let id = UInt32(index + 1)
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(binding.keyCode, binding.modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                             GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference {
                registered.append(reference)
                actions[id] = binding.action
            } else {
                NSLog("Telekin: shortcut %u could not be registered (%d); another app may use it", binding.keyCode, result)
            }
        }
    }

    deinit {
        registered.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}
