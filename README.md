# Remember Me

App nativa para iPhone que convierte frases en español ("Llamar al taller el viernes a las 10") en tareas, compras y citas de Apple Reminders y Apple Calendar.

## Estado: Fase B (EventKit y permisos)

| Fase | Contenido | Estado |
|---|---|---|
| A | Estructura, modelos de dominio, parser determinista, validador, tests | Fusionada en `main` |
| B | Permisos de Calendar y Reminders, agenda, listas, creación confirmada sin duplicados | Rama `phase-b/eventkit-integration`, pendiente de revisión |
| C | Captura de texto en lenguaje natural con vista previa | Pendiente |
| D | Notificaciones y reglas de anticipación | Pendiente |
| E | Entrada por voz | Pendiente |
| F | IA opcional y pulido visual | Pendiente |

**Validación CI de la Fase B (9 de octubre de 2026):** [ejecución 37926850668](https://github.com/vlgomez/remember-me-ios/actions/runs/37926850668) sobre el commit `417e001`, el último con cambios de código. `swift test`: 134 tests, 0 fallos (82 de la Fase A y 52 de la Fase B). XcodeGen 2.46.0 generó el proyecto y `xcodebuild` (Xcode 26.6, SDK iOS Simulator 26.5) compiló la app para el simulador sin firma: 0 avisos y 0 errores. El `Info.plist` compilado contiene `NSCalendarsFullAccessUsageDescription` y `NSRemindersFullAccessUsageDescription`, y ninguna otra clave de Calendar o Reminders. La app no se ha ejecutado en un simulador ni en un iPhone: el CI solo compila.

La Fase A se validó en la [ejecución 37915966741](https://github.com/vlgomez/remember-me-ios/actions/runs/37915966741) (82 tests, 0 fallos).

## Estructura

```
RememberMe/
├─ project.yml                  XcodeGen: genera RememberMe.xcodeproj
├─ scripts/check-privacy-keys.sh  Comprueba las claves de privacidad del Info.plist compilado
├─ RememberMe/                  App iOS (SwiftUI)
│  ├─ Info.plist                Solo las descripciones de privacidad de Calendar y Reminders
│  ├─ App/                      Punto de entrada, pestañas, dependencias (AppEnvironment)
│  ├─ Features/                 Today · Capture · Calendar · Reminders · Settings · Shared
│  ├─ Services/EventKit/        Permisos, Calendar, Reminders y comprobación de existencia
│  └─ Persistence/              Ubicación del registro de elementos creados
└─ Packages/RememberMeCore/     Dominio: solo Foundation, sin UIKit/SwiftUI/EventKit
   ├─ Sources/RememberMeCore/
   │  ├─ Models/                TaskIntent, TaskField, TaskAction, fechas, modelos de EventKit sin EventKit
   │  ├─ Parsing/               TaskIntentParser y DeterministicSpanishParser
   │  ├─ Validation/            TaskIntentValidator
   │  ├─ Rules/                 DateContext (fechas) y reglas de aviso
   │  ├─ UseCases/              Interpretar, permisos, agenda, listas y guardado confirmado
   │  ├─ Ports/                 Reloj, identificadores y puertos hacia Calendar y Reminders
   │  └─ Persistence/           Registro de elementos creados (memoria y JSON)
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

El workflow `.github/workflows/ci.yml` ejecuta esos comandos en un runner `macos-latest` de GitHub Actions en cada push y, además, comprueba con `scripts/check-privacy-keys.sh` que el `Info.plist` de la app compilada tiene la descripción de privacidad de cada petición de permiso que hace el código, y ninguna sobrante. Cada aviso y error de compilación se publica como anotación de la ejecución.

Antes de instalar en un iPhone, cambia `PRODUCT_BUNDLE_IDENTIFIER` en `project.yml` por uno tuyo y elige tu equipo de firma en Xcode.

## Integración con Calendar y Reminders (Fase B)

### Permisos

- **Calendar y Reminders son permisos independientes.** La app pide **acceso total** a los dos con las APIs de iOS 17: `requestFullAccessToEvents()` y `requestFullAccessToReminders()`. Necesita leer la agenda y comprobar si los elementos que creó siguen existiendo, y Reminders no ofrece acceso de solo escritura.
- **Claves de privacidad:** `NSCalendarsFullAccessUsageDescription` y `NSRemindersFullAccessUsageDescription` en `RememberMe/Info.plist`. Con iOS 17 como mínimo no se incluyen las claves antiguas (`NSCalendarsUsageDescription`, `NSRemindersUsageDescription`) ni la de solo escritura, según la nota técnica TN3152 de Apple.
- **Nunca se pide permiso al arrancar.** El diálogo del sistema solo aparece al pulsar «Permitir acceso» (Calendario, Ajustes) o al guardar desde Añadir, después de una explicación previa.
- **Estados:** sin decidir (explicación y botón), acceso total, solo añadir eventos (aviso para cambiarlo en Ajustes), denegado (botón «Abrir Ajustes») y restringido (sin botón: el usuario no puede cambiarlo). Las pantallas vuelven a leer el permiso al volver a la app.

### Qué hace la app

- **Calendario:** agenda de los próximos 7 días agrupada por día; los eventos de día completo aparecen como «Todo el día», no como medianoche. Estados de carga, vacío y error, y recarga al volver a la app o cuando Calendar cambia (`EKEventStoreChanged`).
- **Ajustes:** estado de cada permiso con su acción, y listas de Recordatorios (la predeterminada y las de solo lectura marcadas).
- **Añadir (temporal):** alta manual de tarea, compra o evento hasta que llegue la captura en lenguaje natural (Fase C). «Revisar» valida y muestra exactamente lo que se va a crear; «Guardar» crea el elemento. Todos los datos los escribe el usuario, incluida la duración del evento, que no tiene valor por defecto.

### Garantías al guardar (`SaveConfirmedTaskUseCase`)

- Solo guarda intenciones `readyToSave`: lo deducido se confirmó en una vista previa y no quedan aclaraciones. Una interpretación ambigua no crea nada.
- Respeta `TaskDate.allDay`: un recordatorio de día completo se guarda sin hora ni zona horaria.
- Solo crea elementos nuevos. No modifica, completa ni borra eventos o recordatorios existentes.
- **Sin duplicados:** registra cada intención guardada con el identificador del elemento creado (`calendarItemIdentifier` y, si existe, `calendarItemExternalIdentifier`) en `Application Support/RememberMe/saved-items.json`. Repetir el guardado devuelve el elemento existente. Si el usuario lo borró fuera de la app, solo se vuelve a crear si lo confirma. Si el registro no se puede leer, no se guarda nada.
- **Sin avisos duplicados:** las entradas manuales no crean alarmas. El registro anota si un elemento lleva alarma de EventKit, para que la Fase D no programe además una notificación local.

### Pruebas que todavía requieren un iPhone (o un simulador interactivo)

- El diálogo del sistema para Calendario y Recordatorios y los textos de privacidad.
- Conceder, denegar, elegir «Añadir eventos» y revocar el permiso desde Ajustes con la app abierta.
- Crear un recordatorio de día completo y comprobar en Recordatorios que no aparece a medianoche.
- Crear un evento y comprobar si Calendario le añade sus avisos por defecto.
- Repetir el guardado, borrar el elemento en Calendario o Recordatorios y volver a guardar.
- Listas de solo lectura, cuentas de iCloud o Exchange, y sincronización entre dispositivos.

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

- La integración con EventKit solo se ha compilado con el SDK real; no se ha ejecutado en un simulador ni en un iPhone. Los servicios de `Services/EventKit` no tienen tests automáticos porque necesitan permisos reales; la lógica que los usa sí está probada con dobles en `RememberMeCore`.
- La prevención de duplicados se basa en el identificador de la intención. En Añadir, repetir el mismo contenido durante la sesión reutiliza el identificador; una intención nueva con el mismo contenido en otra sesión (o, en la Fase C, una frase escrita de nuevo) no se detecta todavía como duplicado.
- EventKit puede cambiar `calendarItemIdentifier` tras una sincronización completa; la app prueba entonces con el identificador externo, que puede no existir aún en elementos recién creados.
- Los eventos se crean en el calendario predeterminado y los recordatorios en la lista elegida o en la predeterminada; no se puede elegir calendario.
- Añadir avisos a eventos existentes («Avísame dos horas antes de mi cita del jueves») no está implementado: devuelve `unsupportedAction` y no modifica nada.
- Hoy y Recordatorios siguen siendo pantallas vacías (Fases C y D).
- El parser cubre un subconjunto pequeño del español; está pensado para ampliarse en la Fase C.
- "Mañana" dicho de madrugada (por ejemplo, a las 00:30) se interpreta como el día siguiente.
- "en <Palabra en mayúscula>" se toma como ubicación, aunque no lo sea ("en Navidad"). Como es una deducción, queda pendiente de confirmar.
- La detección de horas repetidas supone que el cambio de horario es un salto único en un margen de ±12 horas, lo que se cumple en España.
- No hay icono de la app ni catálogo de recursos; el color de acento se aplica con `.tint(.green)`.
