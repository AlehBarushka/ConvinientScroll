import Foundation
import Testing
@testable import MacToolkit

@Suite("ThrottleAlertPolicy")
struct ThrottleAlertPolicyTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test func flappingGivesOneHeavyAndOneCritical() {
        var policy = ThrottleAlertPolicy()
        var alerts: [ThrottleAlert] = []
        let steps: [(ThermalLevel, ThermalLevel, TimeInterval)] = [
            (.moderate, .heavy, 0), (.heavy, .moderate, 20), (.moderate, .heavy, 40),
            (.heavy, .moderate, 60), (.moderate, .heavy, 90), (.heavy, .critical, 150)
        ]
        for (from, to, t) in steps {
            if let alert = policy.alert(from: from, to: to, at: t0 + t) { alerts.append(alert) }
        }
        #expect(alerts == [.heavy, .critical])
    }

    @Test func heavyRepeatsAfterCooldown() {
        var policy = ThrottleAlertPolicy()
        #expect(policy.alert(from: .nominal, to: .heavy, at: t0) == .heavy)
        #expect(policy.alert(from: .nominal, to: .heavy, at: t0 + 599) == nil)
        #expect(policy.alert(from: .nominal, to: .heavy, at: t0 + 600) == .heavy)
    }

    @Test func descendingAndRecoveryAreSilent() {
        var policy = ThrottleAlertPolicy()
        #expect(policy.alert(from: .critical, to: .heavy, at: t0) == nil)
        #expect(policy.alert(from: .heavy, to: .nominal, at: t0 + 1) == nil)
        #expect(policy.alert(from: nil, to: .critical, at: t0 + 2) == .critical)
    }

    @Test func sameLevelIsSilent() {
        var policy = ThrottleAlertPolicy()
        #expect(policy.alert(from: .critical, to: .critical, at: t0) == nil)
        #expect(policy.alert(from: .heavy, to: .heavy, at: t0) == nil)
    }
}
