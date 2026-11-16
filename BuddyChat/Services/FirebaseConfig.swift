import Foundation

/// Fill these in from your Firebase project (Project settings → General → Your apps → Web app config).
/// These values are not passwords — Firebase's security rules protect the data.
enum FirebaseConfig {
    static let apiKey = "AIzaSyCXoMzDT9DxB6fEer3F-UuOQlChRhkUFYY"
    /// Looks like https://your-project-default-rtdb.firebaseio.com
    static let databaseURL = "https://buddychat-48c0b-default-rtdb.firebaseio.com"

    static var isConfigured: Bool { !apiKey.isEmpty && !databaseURL.isEmpty }
}
