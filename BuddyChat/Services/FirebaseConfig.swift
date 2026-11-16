import Foundation

/// Fill these in from your Firebase project (Project settings → General → Your apps → Web app config).
/// These values are not passwords — Firebase's security rules protect the data.
enum FirebaseConfig {
    static let apiKey = "PASTE_API_KEY"
    /// Looks like https://your-project-default-rtdb.firebaseio.com
    static let databaseURL = "https://PASTE_PROJECT-default-rtdb.firebaseio.com"

    static var isConfigured: Bool { !apiKey.hasPrefix("PASTE") && !databaseURL.contains("PASTE") }
}
