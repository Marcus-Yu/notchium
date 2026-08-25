import NotchiumCore

func oneShotStream<Element: Sendable>(_ value: Element) -> AsyncStream<Element> {
    AsyncStream { continuation in
        continuation.yield(value)
        continuation.finish()
    }
}

func stageOneUnavailable(_ kind: ServiceKind) -> FeatureAvailability {
    .unavailable(.stageTwoRequired)
}
