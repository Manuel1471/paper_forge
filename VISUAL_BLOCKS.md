# Bloques visuales configurables

Los bloques básicos permiten construir tus propios pases, credenciales o tarjetas.
La presentación vive en el archivo `.paperforge`; los datos pueden seguir llegando
desde JSON. No se incluyen componentes de negocio prediseñados.

Ejemplo completo: [galería de cuatro páginas](examples/visual_blocks.paperforge).
Genera el PDF con `mix run examples/visual_blocks.exs`.

## Composición

Todos los tamaños están en puntos PDF (72 puntos = una pulgada).
Los contenedores reciben hijos en `blocks` y configuración en `options`.

| Tipo | Función | Opciones principales |
| --- | --- | --- |
| `container` | Caja con hijos verticales | `padding`, `gap`, `background_color`, `border_radius` |
| `column` | Flujo vertical | `gap`, `padding` |
| `row` | Columnas iguales o de ancho explícito | `gap`, `column_widths`, `valign` |
| `block_grid` | Cuadrícula de bloques arbitrarios | `columns`, `gap`, `valign` |
| `overlay` | Capas en orden de dibujo | `width`, `height`; hijos con `offset_x`, `offset_y` |
| `shape` | Figura vectorial | `shape`, `color`, `border_color`, `border_width` |
| `icon` | Icono vectorial SVG | `content`, `size`, `color` |
| `badge` | Etiqueta compacta | `text`, `size`, `padding`, `icon` |
| `button` | Enlace con aspecto de botón | `text`, `link`, `icon`, `icon_size`, `icon_gap` |
| `framed_image` | Imagen recortada con marco | `source`, `width`, `height`, `fit`, `focal_point`, `caption` |

`grid` con `blocks` es un alias de `block_grid`. El grid anterior con `cells`
mantiene su comportamiento. Para los nuevos grids, usa `options.columns`.
`valign` acepta `top`, `middle` o `bottom`; cada fila usa la altura de su
hijo más alto. `column_widths` expresa anchos en puntos, sin incluir los gaps.

Opciones compartidas: `width`, `height`, `align` (left/center/right),
`space_before`, `space_after`, `background_color`, `border_color`,
`border_width`, `border_radius`. Los contenedores heredan `font`, `size`,
`color` y `line_height` hacia sus hijos; las opciones explícitas del hijo ganan.
Se admiten tokens del sistema de diseño y fuentes registradas.

```json
{
  "version": "1",
  "blocks": [{
    "type": "container",
    "options": {
      "padding": 18, "gap": 12, "border_radius": 12,
      "background_color": "#F0F6F5"
    },
    "blocks": [
      {"type": "heading", "text": "Tu próximo proyecto"},
      {"type": "paragraph", "text": "Diseño configurable y contenido dinámico."},
      {"type": "button", "text": "Ver detalles",
       "options": {"link": "https://example.com", "icon": "arrow_right",
                   "size": 11, "padding": 10}}
    ]
  }]
}
```

## Imágenes, figuras y capas

`framed_image.source` se resuelve con la política de recursos del registro.
`fit` admite el ajuste del motor de imágenes (por defecto `cover`);
`focal_point: [0.5, 0.5]` centra el recorte.
`shape: "circle"` requiere ancho y alto iguales.
Para esquinas redondeadas usa `border_radius`.
El título inferior usa `caption`, `caption_size` (9 por defecto) y
`caption_color`. El título participa en el cálculo de la altura.

Las figuras admiten `rectangle`, `circle`, `ellipse`, `line` y `polygon`.
Un círculo conserva su proporción dentro de su rectángulo; una elipse lo llena.
Los polígonos usan `points: [[0, 0], [1, 0], [0.5, 1]]`: coordenadas normalizadas.
Los iconos integrados son `check`, `arrow_right`, `mail`, `star` y `user`.
También puedes pasar SVG en `content`; sus colores explícitos se conservan.

En un overlay, el origen local es la esquina superior izquierda.
Los offsets son positivos o cero, las capas posteriores se dibujan encima.
La altura automática incluye el desplazamiento de cada hijo.
Para situar títulos sobre fotografías, combina `framed_image` y `container`
dentro de un `overlay`.

## Texto y enlaces

`rich_text.content` admite runs con `text` y `options`:
fuente, tamaño, color, peso, estilo italic/oblique, `underline`,
`strikethrough` y `link`. Las fuentes registradas se usan tanto al medir
como al dibujar. Para caracteres no disponibles en las fuentes estándar,
registra una fuente con los glifos necesarios.

Los botones requieren `options.link`. Los enlaces externos admiten
http, https, mailto y tel. El área activa cubre el botón completo.
Un icono opcional se coloca antes del texto, centrado verticalmente.

## Límites y paginación

Una composición es atómica: pasa completa a la siguiente página si hace falta.
No se divide una tabla o párrafo entre páginas dentro de estas cajas.
Si supera una página o una altura explícita, se devuelve un error en lugar
de recortar contenido silenciosamente. Usa bloques de flujo normales para
tablas largas y documentos que necesiten fragmentación automática.

Los hijos usan coordenadas locales: no admiten x/y absolutos, saltos de página,
secciones, notas globales ni callbacks custom. Usa offset_x/offset_y en overlays.
No añadas padding a hojas como iconos, figuras o imágenes; envuélvelas en una caja.
El recorte de imagen afecta al dibujo, no a áreas de anotación externas.

En Elixir se puede componer con
`Flow.visual(flow, :box, children_flow, padding: 18)`, y los demás tipos
listados arriba. En declarativo, `container`
corresponde al tipo nativo `:box`.
