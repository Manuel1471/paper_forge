defmodule PaperForge.Examples.AtlasReport do
  @moduledoc """
  Reproducible editorial and pagination workload. All companies and figures are fictional.
  Uses built-in fonts and vector artwork; no network or system font dependencies.
  """
  alias PaperForge.{Color, Flow, Page}

  def ink, do: Color.rgb255(19, 39, 51)
  def teal, do: Color.rgb255(0, 115, 110)
  def coral, do: Color.rgb255(225, 102, 71)
  def pale, do: Color.rgb255(237, 244, 241)
  def muted, do: Color.rgb255(91, 111, 118)

  def routes do
    cities = [
      "Monterrey",
      "Saltillo",
      "Querétaro",
      "León",
      "Puebla",
      "Mérida",
      "Toluca",
      "Guadalajara"
    ]

    for n <- 1..120 do
      %{
        id: "AT-#{String.pad_leading(to_string(n), 3, "0")}",
        origin: Enum.at(cities, rem(n - 1, 8)),
        destination: Enum.at(cities, rem(n + 2, 8)),
        trips: 180 + rem(n * 17, 220),
        on_time: 94.0 + rem(n * 13, 50) / 10,
        km: 240 + rem(n * 37, 920)
      }
    end
  end

  def months do
    Enum.zip(
      ~w(Ene Feb Mar Abr May Jun Jul Ago Sep Oct Nov Dic),
      [72, 74, 79, 81, 86, 89, 91, 94, 98, 102, 109, 115]
    )
  end

  def build do
    data = routes()

    document =
      PaperForge.new(compress: true)
      |> PaperForge.metadata(
        title: "ATLAS | Informe operativo 2026",
        author: "Atlas Logística - ejemplo ficticio",
        subject: "Demostración editorial y verificación de PaperForge 1.5.0"
      )
      |> PaperForge.style(:paragraph,
        size: 10.5,
        line_height: 15.5,
        color: ink(),
        space_after: 13
      )
      |> PaperForge.attach("atlas-routes.json", Jason.encode!(data, pretty: true),
        mime_type: "application/json"
      )

    PaperForge.layout(
      document,
      fn flow ->
        flow
        |> cover()
        |> contents()
        |> executive(data)
        |> network()
        |> financial()
        |> service()
        |> technology()
        |> sustainability()
        |> people()
        |> risks()
        |> roadmap()
        |> route_register(data)
        |> methodology(data)
        |> layout_lab()
        |> closing()
      end,
      page_options: [size: :a4, margins: [top: 64, right: 48, bottom: 54, left: 48]],
      header: &header/2,
      footer: &footer/2,
      first_header: nil,
      first_footer: nil
    )
  end

  defp cover(flow) do
    Flow.custom(
      flow,
      fn page, _ ->
        page
        |> rect(0, 0, page.width, page.height, ink())
        |> rect(48, 65, 40, 5, coral())
        |> label("ATLAS", 48, 118, 38, Color.white())
        |> label("LOGÍSTICA / INFORME ANUAL", 50, 143, 9, Color.rgb255(154, 194, 190))
        |> label("La distancia", 48, 239, 49, Color.white())
        |> label("se convierte", 48, 296, 49, Color.white())
        |> label("en confianza.", 48, 353, 49, Color.white())
        |> label("2026", 48, 426, 32, coral())
        |> network_art(72, 465, 440, 205)
        |> label("OPERACIÓN  /  PERSONAS  /  IMPACTO", 48, 733, 10, Color.white())
        |> label(
          "Edición demostrativa · Datos ficticios · PaperForge 1.5.0",
          48,
          766,
          9,
          Color.rgb255(154, 194, 190)
        )
      end,
      height: 700,
      id: "cover"
    )
  end

  defp contents(flow) do
    flow
    |> Flow.page_break()
    |> eyebrow("GUÍA DE LECTURA")
    |> Flow.table_of_contents(
      title: "Dentro de este informe",
      levels: 1..1,
      size: 28,
      line_height: 36,
      color: ink(),
      level_styles: %{1 => [size: 10.5, line_height: 23]},
      leader: ".",
      entry_formatter: fn entry ->
        String.replace(entry.title, "\n", " ") <> "  /  " <> to_string(entry.page)
      end
    )
    |> Flow.spacer(22)
    |> callout(
      "Un informe realista, una empresa ficticia",
      "Las cifras son un conjunto de datos sintético y reproducible. Este documento demuestra composición editorial, paginación, inspección y transformación de PDF; no describe resultados de una empresa real."
    )
  end

  defp executive(flow, data) do
    trips = Enum.sum(Enum.map(data, & &1.trips))

    flow
    |> chapter("01", "Una red más confiable,\nun crecimiento más disciplinado", "summary")
    |> Flow.paragraph(
      "En 2026, Atlas concentró su estrategia en una pregunta sencilla: ¿cómo hacer que cada entrega sea más predecible sin trasladar toda la complejidad al cliente? La respuesta combinó capacidad regional, información compartida y decisiones operativas más cerca del terreno."
    )
    |> metrics([
      {"$1,090 M", "INGRESOS SIMULADOS"},
      {format_int(trips), "VIAJES PROGRAMADOS"},
      {"120", "CORREDORES ACTIVOS"}
    ])
    |> Flow.spacer(18)
    |> subheading("La mejora se mide en la experiencia diaria")
    |> Flow.columns(
      2,
      [
        "La red operó con un modelo de capacidad reservada. Las ventanas de carga se acordaron antes del despacho y los cambios se registraron en una bitácora común. Esto permitió separar los retrasos de origen de las incidencias en tránsito.",
        "El crecimiento comercial se concentró en cuentas con demanda recurrente. La prioridad fue mantener el nivel de servicio y comprender el costo de cada corredor antes de ampliar la cobertura. La expansión dejó de ser un fin en sí mismo."
      ],
      size: 10.5,
      line_height: 15.5,
      column_gap: 24,
      space_after: 22
    )
    |> callout(
      "Decisión de dirección",
      "Mantener la inversión en calidad de servicio y automatización, con revisiones trimestrales de capacidad y un criterio explícito de rentabilidad por corredor."
    )
    |> Flow.footnote(
      "Los viajes se calculan sumando el anexo de 120 corredores. Los ingresos corresponden a la serie mensual, expresada en millones de pesos.",
      marker: false
    )
  end

  defp network(flow) do
    flow
    |> chapter("02", "La red: conectar capacidad\ncon demanda regional", "network")
    |> Flow.paragraph(
      "Ocho nodos regionales articulan la operación. El esquema siguiente es conceptual: muestra conexiones y dependencias, no distancias geográficas ni rutas cartográficas. Cada nodo concentra recepción, clasificación y salida hacia su zona de servicio."
    )
    |> Flow.custom(
      fn page, c ->
        page
        |> rect(c.block_x, c.block_y, c.block_width, 240, pale())
        |> network_art(c.block_x + 35, c.block_y + 28, c.block_width - 70, 165)
        |> label("RED CONCEPTUAL / OCHO NODOS", c.block_x + 20, c.block_y + 219, 9, teal())
      end,
      height: 260
    )
    |> subheading("Tres reglas para crecer sin fragmentar la operación")
    |> Flow.list(
      [
        "Asignar una ventana operativa a cada corredor y mantenerla visible para los equipos de origen y destino.",
        "Revisar desbalances de carga semanalmente, usando capacidad efectiva y no solo capacidad nominal.",
        "Activar proveedores alternos únicamente después de validar seguridad, trazabilidad y tiempos de respuesta."
      ],
      type: :ordered,
      size: 10.5,
      line_height: 16,
      space_after: 12
    )
  end

  defp financial(flow) do
    series = months()

    flow
    |> chapter("03", "Ingresos que crecen\ncon una base operativa más estable", "financial")
    |> Flow.paragraph(
      "El escenario simulado registra ingresos anuales de $1,090 millones. La estacionalidad aumenta la demanda al final del año; por ello, el presupuesto reserva capacidad desde el tercer trimestre y protege los contratos recurrentes frente a los picos de volumen."
    )
    |> Flow.chart(series,
      chart_type: :bar,
      colors: List.duplicate(teal(), 11) ++ [coral()],
      height: 220,
      color: teal(),
      label_color: muted(),
      show_values: true,
      chart_padding: 16,
      space_after: 20
    )
    |> Flow.paragraph("Ingresos mensuales · Millones de MXN · Escenario sintético",
      size: 8.5,
      color: muted()
    )
    |> table(
      ["Trimestre", "Ingresos / MXN M", "Participación"],
      [{"T1", 225}, {"T2", 256}, {"T3", 283}, {"T4", 326}]
      |> Enum.map(fn {q, value} -> [q, "$#{value}", "#{Float.round(value / 1090 * 100, 1)}%"] end),
      column_widths: [170, 170, 159]
    )
    |> Flow.paragraph(
      "Lectura de gestión: el aumento de ingresos no se presenta como evidencia de productividad. Para evaluar productividad se requiere separar precio, mezcla, ocupación y kilómetros vacíos; esas variables se revisan por corredor.",
      size: 9.5
    )
  end

  defp service(flow) do
    flow
    |> chapter("04", "La promesa de servicio\nempieza antes del despacho", "service")
    |> Flow.paragraph(
      "Una entrega puntual depende de varias decisiones anteriores al viaje. La confirmación de la cita, la disponibilidad del equipo y la integridad documental son parte de la misma promesa. El tablero operativo asigna responsables y tiempos límite a cada evento."
    )
    |> metrics([
      {"98.2%", "META DE PUNTUALIDAD"},
      {"30 min", "PRIMERA RESPUESTA"},
      {"24 h", "CIERRE DOCUMENTAL"}
    ])
    |> Flow.spacer(20)
    |> table(
      ["Momento", "Control", "Responsable"],
      [
        [
          "Antes de la carga",
          "Cita confirmada, unidad asignada y documentos completos",
          "Planeación"
        ],
        ["En tránsito", "Seguimiento de hitos y gestión de excepciones", "Torre de control"],
        ["En destino", "Prueba de entrega y registro de diferencias", "Operación local"],
        [
          "Después del viaje",
          "Conciliación de tiempos, costos e incidencias",
          "Servicio al cliente"
        ]
      ],
      column_widths: [105, 284, 110]
    )
    |> subheading("Una incidencia, un expediente")
    |> Flow.paragraph(
      "El cliente recibe un número de caso y una actualización verificable. El equipo registra qué ocurrió, qué evidencia existe y cuál es la siguiente acción. Las causas se clasifican después de resolver la urgencia para evitar que el indicador reemplace la atención al cliente."
    )
    |> callout(
      "El indicador no es una garantía",
      "La meta de 98.2% es aspiracional. Los porcentajes del registro operativo son valores simulados por corredor y no deben confundirse con un resultado consolidado auditado."
    )
  end

  defp technology(flow) do
    flow
    |> chapter("05", "Información compartida,\nmenos decisiones a ciegas", "technology")
    |> Flow.paragraph(
      "La plataforma conecta planeación, monitoreo y conciliación. Su diseño prioriza eventos observables sobre reportes aislados: una cita cambia de estado, una unidad cruza un hito, una entrega obtiene evidencia. Cada evento conserva origen, fecha y responsable."
    )
    |> Flow.grid(
      3,
      [
        "01 / CAPTURAR\nEventos de operación",
        "02 / VALIDAR\nReglas y consistencia",
        "03 / ACTUAR\nAlertas con responsable"
      ],
      cell_height: 85,
      gap: 15,
      size: 10,
      line_height: 16,
      fill_color: pale(),
      stroke_color: pale()
    )
    |> Flow.spacer(20)
    |> subheading("Arquitectura orientada a excepciones")
    |> Flow.columns(
      2,
      [
        "La integración no elimina la supervisión humana. Cuando faltan datos, el sistema comunica la incertidumbre y evita completar campos con supuestos. Los cambios relevantes quedan en un historial que permite reconstruir la secuencia de decisiones.",
        "Las alertas se ordenan por impacto y tiempo disponible. Una demora con margen de recuperación se atiende de forma distinta a una entrega con ventana crítica. El objetivo es reducir ruido y dirigir la atención al siguiente paso útil."
      ],
      size: 10.5,
      line_height: 16,
      column_gap: 25,
      space_after: 22
    )
    |> table(
      ["Dato", "Validación mínima"],
      [
        ["Identificador de viaje", "Único, estable y presente en todos los eventos"],
        ["Fecha y hora", "Zona horaria explícita y secuencia coherente"],
        ["Evidencia de entrega", "Archivo asociado al destino y al responsable"],
        ["Cambio de estado", "Transición permitida y motivo documentado"]
      ],
      column_widths: [160, 339]
    )
  end

  defp sustainability(flow) do
    flow
    |> chapter("06", "Usar mejor la capacidad\nantes de añadir más kilómetros", "sustainability")
    |> Flow.paragraph(
      "La agenda ambiental comienza por medir. Sin kilómetros recorridos, consumo y carga útil comparables, una reducción porcentual puede ocultar cambios en el perímetro de operación. Este escenario presenta una trayectoria objetivo, no una medición de emisiones certificada."
    )
    |> Flow.chart([{"2026", 100}, {"2027", 94}, {"2028", 88}, {"2029", 83}, {"2030", 78}],
      chart_type: :line,
      height: 210,
      color: teal(),
      show_values: true,
      space_after: 16
    )
    |> Flow.paragraph("Índice objetivo de intensidad energética · Base 2026 = 100",
      size: 8.5,
      color: muted()
    )
    |> subheading("Prioridades de implementación")
    |> Flow.list(
      [
        "Consolidar cargas compatibles y reducir retornos vacíos sin extender los tiempos comprometidos.",
        "Homologar la captura de combustible y kilometraje antes de comparar proveedores.",
        "Evaluar renovación de unidades según ciclo de uso, mantenimiento y disponibilidad de infraestructura."
      ],
      type: :ordered,
      size: 10.5,
      line_height: 16,
      space_after: 11
    )
    |> Flow.footnote(
      "El índice es ilustrativo. No equivale a toneladas de CO2 ni a una declaración de neutralidad de carbono.",
      marker: false
    )
  end

  defp people(flow) do
    flow
    |> chapter("07", "La seguridad se construye\nen cada cambio de turno", "people")
    |> Flow.paragraph(
      "La continuidad operativa depende de equipos que puedan reportar riesgos sin temor a perder tiempo o reconocimiento. El programa de seguridad combina capacitación práctica, revisión de incidentes y conversaciones breves antes de cada turno."
    )
    |> Flow.rich_text(
      [
        {"Cuidar a las personas", [size: 25, color: teal()]},
        {"\nes una condición de la operación, no un resultado secundario.", [size: 12]}
      ],
      padding: 22,
      fill_color: pale(),
      space_after: 24
    )
    |> table(
      ["Programa", "Frecuencia", "Evidencia"],
      [
        ["Inducción de seguridad", "Al ingreso", "Evaluación práctica y acompañamiento"],
        ["Revisión de fatiga", "Antes del turno", "Lista de verificación y escalamiento"],
        ["Simulacro de incidentes", "Trimestral", "Registro de respuesta y acciones"],
        ["Revisión de casi accidentes", "Mensual", "Causas, responsables y seguimiento"],
        ["Actualización técnica", "Semestral", "Competencias por función"]
      ],
      column_widths: [170, 100, 229]
    )
    |> subheading("Aprender sin normalizar el riesgo")
    |> Flow.paragraph(
      "La revisión de un incidente distingue las decisiones individuales de las condiciones del sistema. Una instrucción confusa, una ventana imposible o una herramienta que falla deben corregirse junto con la conducta observable. El cierre exige evidencia de que la acción se implementó."
    )
  end

  defp risks(flow) do
    flow
    |> chapter("08", "Prepararse para lo que\nno cabe en el plan", "risks")
    |> Flow.paragraph(
      "El registro de riesgos conecta escenarios con decisiones. No busca anticipar cada evento, sino definir señales, responsables y respuestas antes de que una interrupción limite las opciones. La revisión cambia cuando cambia la exposición."
    )
    |> table(
      ["Riesgo", "Señal temprana", "Respuesta prevista"],
      [
        [
          "Concentración comercial",
          "Una cuenta supera el umbral interno de participación",
          "Revisar exposición y diversificar renovaciones"
        ],
        [
          "Capacidad insuficiente",
          "Reservas recurrentes por encima del nivel disponible",
          "Activar capacidad validada y proteger ventanas críticas"
        ],
        [
          "Interrupción de corredor",
          "Alertas de seguridad o cierres prolongados",
          "Replanificar rutas y comunicar impactos verificables"
        ],
        [
          "Calidad de datos",
          "Eventos sin identificador o fechas inconsistentes",
          "Aislar registros y corregir el origen del error"
        ],
        [
          "Ciberincidente",
          "Accesos atípicos o pérdida de disponibilidad",
          "Contener, recuperar y mantener operación mínima"
        ],
        [
          "Presión de costos",
          "Desviación sostenida de combustible y mantenimiento",
          "Revisar supuestos y acuerdos comerciales"
        ]
      ],
      column_widths: [115, 184, 200],
      row_height: 60
    )
    |> callout(
      "Disciplina de seguimiento",
      "Cada riesgo conserva dueño, fecha de revisión y criterio de cierre. Un semáforo sin una decisión asociada no se considera un control suficiente."
    )
  end

  defp roadmap(flow) do
    flow
    |> chapter("09", "De la estrategia\na una secuencia ejecutable", "roadmap")
    |> Flow.paragraph(
      "El plan 2027 organiza la transformación en cuatro entregas. Cada etapa produce un resultado verificable antes de habilitar la siguiente; el calendario se ajusta si la calidad de los datos o la adopción operativa no alcanzan el nivel esperado."
    )
    |> table(
      ["Etapa", "Entregable", "Criterio de aceptación"],
      [
        [
          "T1 / BASE",
          "Catálogo de eventos y responsables",
          "Todos los corredores tienen identificadores y ventanas definidas"
        ],
        [
          "T2 / VISIBILIDAD",
          "Tablero de excepciones y seguimiento",
          "Los casos críticos cuentan con responsable y siguiente acción"
        ],
        [
          "T3 / EFICIENCIA",
          "Modelo de costo por corredor",
          "Costos conciliados con viajes y revisados por finanzas"
        ],
        [
          "T4 / ESCALA",
          "Expansión selectiva de la red",
          "Nuevos corredores cumplen servicio, seguridad y rentabilidad"
        ]
      ],
      column_widths: [100, 180, 219],
      row_height: 72
    )
    |> Flow.spacer(16)
    |> Flow.keep_together(fn group ->
      group
      |> subheading("La puerta de salida de cada etapa")
      |> Flow.paragraph(
        "El comité no aprueba la siguiente fase por haber consumido el presupuesto. La aprueba cuando existe evidencia de que la capacidad instalada funciona: datos completos, equipos entrenados y un proceso que puede sostenerse sin intervención extraordinaria."
      )
    end)
    |> Flow.reference("register",
      prefix: "El detalle de corredores comienza en la página ",
      size: 10
    )
  end

  defp route_register(flow, data) do
    rows =
      Enum.map(data, fn row ->
        [
          row.id,
          "#{row.origin}\n#{row.destination}",
          format_int(row.trips),
          "#{row.on_time}%",
          "#{row.km} km"
        ]
      end)

    flow
    |> chapter("10", "Registro operativo\nde corredores", "register")
    |> Flow.paragraph(
      "Anexo de 120 corredores. Cada fila conserva un identificador único y muestra origen, destino, viajes programados, puntualidad simulada y distancia de referencia. El encabezado se repite automáticamente; las filas se mantienen completas entre páginas."
    )
    |> table(["Corredor", "Origen / destino", "Viajes", "Puntualidad", "Distancia"], rows,
      column_widths: [74, 170, 75, 95, 85],
      row_height: 46,
      id: "route-table"
    )
    |> Flow.paragraph("FIN DEL REGISTRO / AT-120 · 120 corredores incluidos",
      size: 9,
      weight: :bold,
      color: teal(),
      id: "register-end"
    )
  end

  defp methodology(flow, data) do
    total = Enum.sum(Enum.map(data, & &1.trips))
    weighted = Enum.sum(Enum.map(data, &(&1.trips * &1.on_time))) / total

    flow
    |> chapter("11", "Metodología, trazabilidad\ny límites de interpretación", "methodology")
    |> Flow.paragraph(
      "Este informe utiliza datos deterministas para que cualquier persona pueda reproducir los resultados. El archivo atlas-routes.json está adjunto dentro del PDF y contiene exactamente las filas utilizadas en el anexo operativo."
    )
    |> table(
      ["Comprobación", "Resultado esperado"],
      [
        ["Corredores únicos", "120 identificadores, de AT-001 a AT-120"],
        ["Viajes programados", format_int(total)],
        ["Puntualidad ponderada por viajes", "#{Float.round(weighted, 2)}%"],
        ["Ingresos de la serie mensual", "$1,090 millones de MXN"],
        ["Suma de los cuatro trimestres", "$1,090 millones de MXN"],
        ["Origen de cifras", "Datos ficticios generados localmente; sin fuentes externas"]
      ],
      column_widths: [245, 254],
      row_height: 35
    )
    |> subheading("Qué prueba este documento")
    |> Flow.paragraph(
      "La ejecución comprueba que el PDF puede volver a abrirse, que el número de páginas coincide con el layout, que no existen referencias rotas y que se conservan adjuntos, enlaces y marcadores. También verifica las posiciones asignadas y la continuidad de las filas de la tabla."
    )
    |> subheading("Qué no prueba")
    |> Flow.paragraph(
      "No certifica compatibilidad con todos los lectores PDF, accesibilidad PDF/UA, conformidad PDF/A, firmas digitales ni precisión financiera de una empresa real. El reporte de validación registra los controles ejecutados, sin convertirlos en una garantía universal."
    )
  end

  defp layout_lab(flow) do
    flow
    |> chapter("12", "Pruebas visibles\nde composición automática", "layout-lab")
    |> Flow.paragraph(
      "Esta página reúne casos que antes podían producir posiciones incorrectas. Los fondos hacen visibles los límites de cada bloque; el contenido siguiente debe comenzar después del área reservada."
    )
    |> Flow.heading(
      "Un título largo necesita reservar todas sus líneas antes del siguiente párrafo",
      level: 2,
      size: 26,
      color: teal(),
      padding: 12,
      fill_color: pale(),
      bookmark: false,
      space_after: 16
    )
    |> Flow.paragraph(
      "Este párrafo debe aparecer debajo del título completo, sin superposición. La altura depende del ancho, de la fuente y del tamaño solicitado; no se presupone una sola línea."
    )
    |> Flow.rich_text(
      [
        {"28 pt", [size: 28, color: coral()]},
        {"  con texto pequeño en la misma línea", [size: 10]},
        {"\nLa segunda línea conserva la separación.", [size: 12]}
      ],
      padding: 14,
      fill_color: pale(),
      space_after: 18
    )
    |> Flow.columns(
      2,
      [
        "Columna izquierda\nTamaño explícito: 13 pt\nAncho del contenido",
        "Columna derecha\nMisma medida al dibujar\nMisma altura al paginar"
      ],
      size: 13,
      line_height: 19,
      column_gap: 24,
      width: :content,
      space_after: 16
    )
    |> Flow.keep_together(fn group ->
      group
      |> Flow.paragraph("GRUPO INSEPARABLE", size: 9, weight: :bold, color: teal())
      |> Flow.paragraph(
        "Este título y su explicación deben compartir página. El motor comprueba la ocupación real del grupo, incluyendo padding y espacio entre párrafos.",
        padding: 12,
        fill_color: pale()
      )
    end)
  end

  defp closing(flow) do
    flow
    |> chapter("13", "La siguiente entrega\nes una mejor decisión", "closing")
    |> Flow.paragraph(
      "Una red confiable no se define por la ausencia de incidentes. Se define por la capacidad de detectarlos, responder con claridad y aprender de ellos. El valor de este informe está en conectar cifras con decisiones y decisiones con responsables."
    )
    |> Flow.spacer(30)
    |> Flow.custom(
      fn page, c ->
        page
        |> rect(c.block_x, c.block_y, c.block_width, 240, ink())
        |> label("ATLAS", c.block_x + 28, c.block_y + 64, 34, Color.white())
        |> label(
          "Conectar. Cumplir. Aprender.",
          c.block_x + 28,
          c.block_y + 107,
          22,
          Color.white()
        )
        |> label(
          "Informe demostrativo / 2026",
          c.block_x + 28,
          c.block_y + 167,
          11,
          Color.rgb255(154, 194, 190)
        )
        |> label(
          "Creado íntegramente con PaperForge 1.5.0",
          c.block_x + 28,
          c.block_y + 200,
          10,
          Color.white()
        )
      end,
      height: 265
    )
    |> Flow.paragraph("REPRODUCIR\nmix run examples/paper_forge_1_5_report.exs",
      size: 10,
      line_height: 17
    )
    |> Flow.paragraph(
      "El generador entrega el informe, un extracto transformado y un archivo JSON con las verificaciones. Los ejemplos están pensados para revisión, adaptación y pruebas de regresión.",
      size: 9.5,
      color: muted()
    )
  end

  defp chapter(flow, number, title, destination) do
    flow
    |> Flow.page_break()
    |> eyebrow("#{number} / ATLAS 2026")
    |> Flow.heading(title, size: 29, color: ink(), destination: destination, space_after: 22)
  end

  defp eyebrow(flow, text),
    do: Flow.paragraph(flow, text, size: 9, line_height: 12, color: teal(), space_after: 16)

  defp subheading(flow, title),
    do:
      Flow.heading(flow, title,
        level: 2,
        size: 17,
        color: teal(),
        bookmark: false,
        space_after: 12
      )

  defp table(flow, columns, rows, options) do
    Flow.table(
      flow,
      columns,
      rows,
      Keyword.merge(
        [
          size: 9,
          cell_line_height: 12.5,
          padding: 9,
          row_height: 32,
          header_fill_color: ink(),
          header_color: Color.white(),
          color: ink(),
          stripe_fill_color: pale(),
          stroke_color: Color.rgb255(213, 224, 222),
          line_width: 0.4,
          space_after: 18,
          repeat_header: true
        ],
        options
      )
    )
  end

  defp metrics(flow, values) do
    Flow.custom(
      flow,
      fn page, c ->
        width = (c.block_width - 24) / 3

        values
        |> Enum.with_index()
        |> Enum.reduce(page, fn {{value, title}, i}, current ->
          x = c.block_x + i * (width + 12)

          current
          |> rect(x, c.block_y, width, 92, pale())
          |> label(value, x + 14, c.block_y + 41, 24, teal())
          |> label(title, x + 14, c.block_y + 67, 7, muted())
        end)
      end,
      height: 92
    )
  end

  defp callout(flow, title, body) do
    Flow.keep_together(flow, fn group ->
      group
      |> Flow.paragraph(title, size: 12, weight: :bold, color: teal(), space_after: 8)
      |> Flow.paragraph(body,
        size: 10,
        line_height: 15,
        padding: 14,
        fill_color: pale(),
        space_after: 15
      )
    end)
  end

  defp header(page, c) do
    page
    |> label("ATLAS", 48, 32, 12, teal())
    |> Page.text("INFORME OPERATIVO 2026",
      x: 340,
      y: 31,
      width: c.page_width - 388,
      align: :right,
      size: 8,
      color: muted()
    )
    |> Page.line(
      x1: 48,
      y1: 43,
      x2: c.page_width - 48,
      y2: 43,
      color: Color.rgb255(213, 224, 222),
      width: 0.5
    )
  end

  defp footer(page, c) do
    page
    |> label(
      "DATOS FICTICIOS / DEMOSTRACIÓN PAPERFORGE 1.5.0",
      48,
      c.page_height - 28,
      7,
      muted()
    )
    |> Page.text("#{String.pad_leading(to_string(c.page_number), 2, "0")} / #{c.total_pages}",
      x: c.page_width - 110,
      y: c.page_height - 28,
      width: 62,
      align: :right,
      size: 9,
      color: teal()
    )
  end

  defp label(page, text, x, y, size, color),
    do: Page.text(page, text, x: x, y: y, size: size, color: color)

  defp rect(page, x, y, w, h, color),
    do:
      Page.rectangle(page,
        x: x,
        y: y,
        width: w,
        height: h,
        fill: true,
        stroke: false,
        fill_color: color
      )

  defp network_art(page, x, y, w, h) do
    points = [
      {0.04, 0.35},
      {0.23, 0.08},
      {0.26, 0.68},
      {0.46, 0.38},
      {0.57, 0.85},
      {0.72, 0.19},
      {0.84, 0.62},
      {0.97, 0.36}
    ]

    edges = [{0, 1}, {0, 2}, {1, 3}, {2, 3}, {2, 4}, {3, 5}, {3, 6}, {4, 6}, {5, 7}, {6, 7}]

    page =
      Enum.reduce(edges, page, fn {a, b}, acc ->
        {ax, ay} = Enum.at(points, a)
        {bx, by} = Enum.at(points, b)

        Page.line(acc,
          x1: x + ax * w,
          y1: y + ay * h,
          x2: x + bx * w,
          y2: y + by * h,
          color: teal(),
          width: 2
        )
      end)

    points
    |> Enum.with_index()
    |> Enum.reduce(page, fn {{px, py}, i}, acc ->
      acc
      |> Page.circle(
        x: x + px * w,
        y: y + py * h,
        radius: 8,
        fill: true,
        stroke: false,
        fill_color: coral()
      )
      |> label("0#{i + 1}", x + px * w - 6, y + py * h + 26, 9, muted())
    end)
  end

  defp format_int(n),
    do:
      n
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/.{3}(?=.)/, "\\0,")
      |> String.reverse()
end
