import Foundation
import RememberMeCore

/// Ubicación del registro de elementos creados por la app.
///
/// El registro relaciona cada intención guardada con el identificador del evento o recordatorio
/// que se creó, para no duplicarlo si se repite la operación. Vive en Application Support (no se
/// muestra al usuario y se incluye en las copias de seguridad del dispositivo). No guarda el
/// contenido de los eventos ni de los recordatorios.
enum SavedItemStorage {
    static var fileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "RememberMe", directoryHint: .isDirectory)
            .appending(path: "saved-items.json", directoryHint: .notDirectory)
    }

    static func makeRegistry() -> JSONFileSavedItemRegistry {
        JSONFileSavedItemRegistry(fileURL: fileURL)
    }
}
