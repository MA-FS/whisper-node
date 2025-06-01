import Foundation
import os.log

public struct WhisperNodeCore {
    private static let logger = Logger(subsystem: "com.whispernode.core", category: "initialization")
    
    public static func initialize() {
        logger.info("WhisperNode Core initialized")
    }
}