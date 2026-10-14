import Foundation

enum DictationCredential: UInt8, CaseIterable {
    case deepgram = 1, elevenLabs, assemblyAI, muse, openRouter, celeris

    var account: UUID { UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, rawValue)) }
    static let store = KeychainSecretStore(scope: "dictation-api-keys")
}
