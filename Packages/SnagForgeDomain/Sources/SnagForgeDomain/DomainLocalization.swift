import Foundation

/// SwiftPM owns the domain's native localization bundle. Standalone test builds
/// compile these same sources directly and resolve resources from their host.
enum DomainLocalization {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }
}
