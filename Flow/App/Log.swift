import OSLog

enum Log {
    static let subsystem = "com.liamblackshawbrown.flow"
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    static let models = Logger(subsystem: subsystem, category: "models")
    static let insert = Logger(subsystem: subsystem, category: "insert")
    static let media = Logger(subsystem: subsystem, category: "media")
}
