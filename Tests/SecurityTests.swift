import Foundation
@testable import AirPad

#if canImport(Testing)
import Testing

@Suite("Security primitives")
struct SecurityPrimitivesTests {
    @Test
    func hmacConsistency() throws {
        let sm = SecurityManager.shared
        let key = Data("secret-key".utf8)
        let msg = Data("hello world".utf8)
        let mac1 = sm.hmacSHA256(data: msg, key: key)
        let mac2 = sm.hmacSHA256(data: msg, key: key)
        #expect(mac1 == mac2)
        #expect(mac1.count == 32)
    }

    @Test
    func hkdfDeterminism() throws {
        let nm = NetworkManager.shared
        let secret = Data("shared-secret".utf8)
        let salt = Data(repeating: 0xAB, count: 16)
        let k1 = nm.test_deriveSessionKey(sharedSecret: secret, salt: salt)
        let k2 = nm.test_deriveSessionKey(sharedSecret: secret, salt: salt)
        #expect(k1 == k2)
        #expect(k1.count == 32)
    }
}
#elseif canImport(XCTest)
import XCTest

final class SecurityPrimitivesTests: XCTestCase {
    func testHmacConsistency() throws {
        let sm = SecurityManager.shared
        let key = Data("secret-key".utf8)
        let msg = Data("hello world".utf8)
        let mac1 = sm.hmacSHA256(data: msg, key: key)
        let mac2 = sm.hmacSHA256(data: msg, key: key)
        XCTAssertEqual(mac1, mac2)
        XCTAssertEqual(mac1.count, 32)
    }

    func testHkdfDeterminism() throws {
        let nm = NetworkManager.shared
        let secret = Data("shared-secret".utf8)
        let salt = Data(repeating: 0xAB, count: 16)
        let k1 = nm.test_deriveSessionKey(sharedSecret: secret, salt: salt)
        let k2 = nm.test_deriveSessionKey(sharedSecret: secret, salt: salt)
        XCTAssertEqual(k1, k2)
        XCTAssertEqual(k1.count, 32)
    }
}
#endif


