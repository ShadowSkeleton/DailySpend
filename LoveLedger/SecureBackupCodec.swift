import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Encrypts portable backups with AES-GCM. The password is never persisted;
/// without it, neither DailySpend nor its developer can recover the file.
enum SecureBackupCodec {
    private static let currentFormat = 1
    private static let saltLength = 16
    private static let keyLength = 32
    private static let iterationCount: UInt32 = 310_000

    private struct Envelope: Codable {
        let format: Int
        let algorithm: String
        let iterations: UInt32
        let salt: Data
        let sealedData: Data
    }

    enum CodecError: LocalizedError {
        case weakPassphrase
        case randomGenerationFailed
        case keyDerivationFailed
        case unsupportedFormat
        case invalidPassphraseOrCorruptedFile

        var errorDescription: String? {
            switch self {
            case .weakPassphrase:
                return "Use a passphrase with at least 12 characters."
            case .randomGenerationFailed:
                return "DailySpend couldn’t create secure backup data."
            case .keyDerivationFailed:
                return "DailySpend couldn’t protect this backup."
            case .unsupportedFormat:
                return "This encrypted backup was created by a newer version of DailySpend."
            case .invalidPassphraseOrCorruptedFile:
                return "The passphrase is incorrect or the backup file is damaged."
            }
        }
    }

    static func isEncryptedBackup(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(Envelope.self, from: data)) != nil
    }

    static func encrypt(_ plaintext: Data, passphrase: String) throws -> Data {
        let salt = try randomSalt()
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterationCount)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let sealedData = sealedBox.combined else {
            throw CodecError.keyDerivationFailed
        }

        let envelope = Envelope(
            format: currentFormat,
            algorithm: "AES-256-GCM/PBKDF2-HMAC-SHA256",
            iterations: iterationCount,
            salt: salt,
            sealedData: sealedData
        )
        return try JSONEncoder().encode(envelope)
    }

    static func decrypt(_ data: Data, passphrase: String) throws -> Data {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw CodecError.invalidPassphraseOrCorruptedFile
        }
        guard envelope.format == currentFormat,
              envelope.algorithm == "AES-256-GCM/PBKDF2-HMAC-SHA256",
              envelope.iterations >= 100_000,
              envelope.iterations <= 1_000_000 else {
            throw CodecError.unsupportedFormat
        }

        do {
            let key = try deriveKey(
                passphrase: passphrase,
                salt: envelope.salt,
                iterations: envelope.iterations
            )
            let sealedBox = try AES.GCM.SealedBox(combined: envelope.sealedData)
            return try AES.GCM.open(sealedBox, using: key)
        } catch let error as CodecError {
            throw error
        } catch {
            throw CodecError.invalidPassphraseOrCorruptedFile
        }
    }

    private static func randomSalt() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CodecError.randomGenerationFailed
        }
        return Data(bytes)
    }

    private static func deriveKey(passphrase: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        guard passphrase.count >= 12 else { throw CodecError.weakPassphrase }
        guard !salt.isEmpty else { throw CodecError.invalidPassphraseOrCorruptedFile }

        let passwordData = Data(passphrase.utf8)
        var keyBytes = [UInt8](repeating: 0, count: keyLength)
        let status = passwordData.withUnsafeBytes { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBuffer.baseAddress?.assumingMemoryBound(to: Int8.self),
                    passwordData.count,
                    saltBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    &keyBytes,
                    keyBytes.count
                )
            }
        }
        guard status == kCCSuccess else { throw CodecError.keyDerivationFailed }
        return SymmetricKey(data: Data(keyBytes))
    }
}
