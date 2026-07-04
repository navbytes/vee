import os

/// Central factory for unified-logging loggers, so every subsystem logs under a
/// consistent subsystem and shows up together in Console.app / `log stream`.
public enum VeeLog {
    public static let subsystem = "com.vee.app"

    public static func make(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
