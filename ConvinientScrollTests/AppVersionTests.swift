import Testing
@testable import MacToolkit

@Suite("AppVersion") struct AppVersionTests {
    @Test func parsesDottedNumbers() { #expect(AppVersion("2.10.1")?.components == [2, 10, 1]) }

    @Test(arguments: ["", "v2.3.0", "2.3.0-beta", "2..3", "2.3.", " 2.3", "2.x"])
    func rejectsNonNumeric(_ s: String) { #expect(AppVersion(s) == nil) }

    @Test func comparesNumerically() { #expect(AppVersion("2.10.0")! > AppVersion("2.9.9")!) }

    @Test func equalWithMissingComponents() {
        #expect(AppVersion("2.3")! == AppVersion("2.3.0")!)
        #expect(!(AppVersion("2.3")! < AppVersion("2.3.0")!))
    }

    @Test func descriptionIsOriginal() { #expect(AppVersion("2.3")!.description == "2.3") }
}
