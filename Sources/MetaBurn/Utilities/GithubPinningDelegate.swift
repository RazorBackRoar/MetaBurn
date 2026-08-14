import Foundation
import Security
import CryptoKit

final class GithubPinningDelegate: NSObject, URLSessionDelegate {
    /// Prefer reject over cancel so URLSession will not keep using a failed protection space.
    static let pinFailureDisposition: URLSession.AuthChallengeDisposition = .rejectProtectionSpace

    // Hashes of the public keys in the certificate chain for api.github.com
    private let knownKeyHashes: Set<String> = [
        "rlkAiJEjAwr5USvccZ2NlLzz7elZETOabSnkRvKdow0=", // Leaf cert
        "ZSagvDzjltLkewXEBuDxIzpW/dpVw1Juvvmd0hhkzdY=", // Intermediate cert
        "sLVjNUaFYfW7n6EtgBeEpjOlcnBdNPMrZDRF36iwBdE="  // Root cert
    ]

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            completionHandler(Self.pinFailureDisposition, nil)
            return
        }

        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            completionHandler(Self.pinFailureDisposition, nil)
            return
        }

        for certificate in chain {
            guard let publicKey = SecCertificateCopyKey(certificate),
                  let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
                continue
            }

            let hash = SHA256.hash(data: publicKeyData)
            let hashString = Data(hash).base64EncodedString()

            if knownKeyHashes.contains(hashString) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        completionHandler(Self.pinFailureDisposition, nil)
    }
}
