# Remember Me

App nativa para iPhone que convierte frases en español ("Llamar al taller el viernes a las 10") en tareas, compras y citas de Apple Reminders y Apple Calendar.

## Estado: Fase A

| Hecho en esta fase | Pendiente |
|---|---|
| Estructura del proyecto y `project.yml` (XcodeGen, iOS 17) | EventKit y permisos (Fase B) |
| Paquete `RememberMeCore` con modelos de dominio | Captura de texto con vista previa en la app (Fase C) |
| Servicios de fechas con reloj, calendario y zona horaria inyectables | Notificaciones y reglas de anticipación (Fase D) |
| Parser determinista para un subconjunto documentado del español | Entrada por voz (Fase E) |
| Validador y confirmación de datos deducidos mediante vista previa | IA y pulido visual (Fase F) |
| Tests XCTest del dominio | |
| App SwiftUI mínima: cinco pestañas con estados vacíos | |
| Workflow de GitHub Actions para macOS | |

**Este código no se ha compilado todavía.** Se escribió en un entorno Linux sin Swift ni Xcode. La primera compilación y la primera ejecución de los tests serán las del workflow de CI o las de un Mac.

## Estructura

```
RememberMe/
├─ project.yml                  XcodeGen: genera RememberMe.xcodeproj
├─ RememberMe/                  App iOS (SwiftUI)
│  ├─ App/                      Punto de entrada, pestañas, dependencias
│  ├─ Features/                 Today · Capture · Calendar · Reminders · Settings
│  ├─ Services/                 (Fase B en adelante: EventKit, notificaciones, voz, IA)
│  └─ Persistence/              (Fase B en adelante)
└─ Packages/RememberMeCore/     Dominio: solo Foundation, sin UIKit/SwiftUI/EventKit
   ├─ Sources/RememberMeCore/
   │  ├─ Models/                TaskIntent, TaskField, TaskAction, TaskParseResult, ReminderPolicy, fechas...
   │  ├─ Parsing/               TaskIntentParser y DeterministicSpanishParser
   │  ├─ Validation/            TaskIntentValidator
   │  ├─ Rules/                 DateContext (fechas) y reglas de aviso
   │  ├─ UseCases/              InterpretTaskUseCase
   │  └─ Ports/                 DateProvider, IdentifierProvider
   └─ Tests/RememberMeCoreTests/
```

## Requisitos

- Mac con Xcode compatible con Swift 6 (`swift-tools-version: 6.0`).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) para generar el proyecto: `brew install xcodegen`.
- Versión mínima de iOS: 17.0 (SwiftData, Observation y los permisos modernos de EventKit).

## Cómo compilar y ejecutar los tests

Tests del dominio (no necesitan simulador):

```sh
cd Packages/RememberMeCore
swift test
```

App:

```sh
xcodegen generate
open RememberMe.xcodeproj
```

Compilación de la app desde la terminal, sin firmar:

```sh
xcodegen generate
xcodebuild build -project RememberMe.xcodeproj -scheme RememberMe \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

El workflow `.github/workflows/ci.yml` ejecuta exactamente esos comandos en un runner `macos-latest` de GitHub Actions en cada push.

Antes de instalar en un iPhone, cambia `PRODUCT_BUNDLE_IDENTIFIER` en `project.yml` por uno tuyo y elige tu equipo de firma en Xcode.

## Reglas del dominio

- **Procedencia de cada dato.** Cada campo es un `TaskField` con origen `userProvided`, `deterministicRule` o `aiInferred`. Lo deducido queda pendiente de confirmación.
- **Confirmación solo con vista previa.** Un dato deducido solo se confirma con la `IntentPreview` que se mostró al usuario, y solo si la intención no ha cambiado desde entonces.
- **Día completo ≠ medianoche.** `TaskDate.allDay` no tiene hora y no se puede convertir en un instante; su intervalo dura 23, 24 o 25 horas según el día.
- **Aritmética de calendario.** "Dentro de tres días" suma días de calendario y conserva la hora de reloj, aunque haya cambio de horario por medio. Las antelaciones en horas o minutos sí son duraciones reales.
- **Horas inexistentes o repetidas.** Las 02:30 del 28 de marzo de 2027 no existen en Madrid (error). Las del 25 de octubre de 2026 ocurren dos veces (aviso).
- **Fecha límite ≠ fecha de ejecución.** "Antes del 20" es una fecha límite exclusiva (el último día válido es el 19). "Para el 20" y "hasta el 20" son inclusivas. "Mañana" es una fecha de ejecución.
- **Sin fechas inventadas.** Una tarea sin fecha se queda sin fecha y sin aviso. A una fecha sin hora no se le asigna hora.
- **Ubicación solo como texto.** "Mercadona" se guarda tal cual; no se geocodifica.

## Frases que entiende el parser determinista

| Expresión | Resultado |
|---|---|
| `hoy`, `mañana`, `pasado mañana` | Día de ejecución exacto |
| `dentro de N días/semanas`, `en N días/semanas` | Día de ejecución exacto |
| `el viernes`, `este viernes`, `viernes` | Próximo viernes (deducido). Si hoy es viernes: pregunta |
| `el próximo viernes`, `el viernes que viene` | Si cae en esta misma semana: pregunta. Si no: ese viernes (deducido) |
| `el 20 de noviembre`, `el 20/11` | Próxima vez que llegue esa fecha (año deducido) |
| `el 20 de noviembre de 2026`, `20/11/2026` | Exacta |
| `antes del 20 de noviembre`, `antes de mañana` | Fecha límite exclusiva |
| `para el viernes`, `hasta el 20/11` | Fecha límite inclusiva |
| `tres días antes del 20 de noviembre` | Fecha límite + aviso 3 días antes |
| `a las 10:30`, `a las 18`, `a las 10 de la mañana`, `a las 5 de la tarde` | Hora exacta |
| `a las 10`, `a las 9 y media` (de 8 a 11) | Por la mañana (deducido) |
| `a las 5` (de 1 a 7, sin franja) | Pregunta: 05:00 o 17:00 |
| `al mediodía` | 12:00 |
| `esta tarde`, `por la mañana`, `de madrugada` | Pregunta la hora (no se inventa) |
| Hora sin día | Hoy si aún no ha pasado (deducido). Si ya pasó, pregunta |
| `Añadir` / `Añade` / `Apunta` / `Pon` X `a la lista de la compra` | Compra con título X |
| `Comprar ...` | Compra (deducido) |
| `cita`, `reunión`, `consulta` | Compromiso → evento de calendario (deducido). Sin hora: pregunta |
| `en Mercadona`, `en El Corte Inglés` | Ubicación textual (deducida) |
| `Recuérdame [que] ...` | Se descarta el prefijo |
| Frases con `avísame` | No admitidas aún: devuelve `unsupportedExpression` |

Cualquier otra cosa se queda en el título. El parser nunca rellena un hueco por su cuenta: devuelve una aclaración.

## Limitaciones conocidas

- El código no se ha compilado ni se han ejecutado los tests (ver arriba).
- El parser cubre un subconjunto pequeño del español; está pensado para ampliarse en la Fase C.
- "Mañana" dicho de madrugada (por ejemplo, a las 00:30) se interpreta como el día siguiente.
- "en <Palabra en mayúscula>" se toma como ubicación, aunque no lo sea ("en Navidad"). Como es una deducción, queda pendiente de confirmar.
- La detección de horas repetidas supone que el cambio de horario es un salto único en un margen de ±12 horas, lo que se cumple en España.
- La app solo muestra pantallas vacías: no lee ni escribe en Calendar o Reminders.
- No hay icono de la app ni catálogo de recursos; el color de acento se aplica con `.tint(.green)`.
