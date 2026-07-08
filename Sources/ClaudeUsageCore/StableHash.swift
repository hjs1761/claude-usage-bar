import Foundation

/// 프로세스 간 결정론적 해시. Swift 기본 `hashValue`는 실행마다 시드가 랜덤화되어
/// 캐시 키/재현성에 못 쓰므로 FNV-1a(64bit)를 직접 구현한다.
public enum StableHash {
    public static func fnv1a(_ s: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325          // FNV offset basis
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3                // FNV prime (overflow-wrap)
        }
        return String(hash, radix: 16)
    }
}
