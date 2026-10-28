# Publicar PaperForge 1.5.0

## Estado de la preparación

- Versión del paquete: `1.5.0`; requiere Elixir `~> 1.20`.
- Notas listas para copiar en GitHub: [RELEASE_1.5.0.md](RELEASE_1.5.0.md).
- Al consultar Hex durante la preparación, la última versión era `1.4.5`.
  Vuelve a comprobarlo antes de publicar.
- Los benchmarks históricos permanecen en Git, pero NO entran al paquete Hex.
  Tampoco se distribuyen tests, claves de prueba, logs ni PDFs generados.
- La imagen usada por la galería sí se incluye. El ejemplo de investigación
  omite la firma si no encuentra credenciales; puedes indicar rutas mediante
  PAPERFORGE_SIGNING_KEY y PAPERFORGE_SIGNING_CERT.
- No se ha publicado esta versión en Hex ni se ha creado el tag.

## 1. Resolver el acceso a GitHub

El push HTTPS falló por falta de credenciales. La clave SSH predeterminada
autenticó como `ManuelGarciaHLCN`, pero esa cuenta no tiene acceso de escritura
a `Manuel1471/paper_forge`.

Usa GitHub Desktop con una cuenta autorizada, configura la credencial HTTPS
correcta o una clave SSH de una cuenta con permisos. No necesitas modificar
commits ni hacer force-push.

Desde el repositorio, comprueba el estado y sube la rama:

```sh
cd /Users/manuelgarcia/Desktop/paper_forge
git switch release/v1.5.0
git status --short
git push -u origin release/v1.5.0
```

Abre el PR contra main y espera a que CI pase. Conserva los commits por
funcionalidad usando merge normal; evita squash si quieres mantener ese historial.

## 2. Verificar el commit que se publicará

Después de integrar el PR:

```sh
git switch main
git pull --ff-only origin main
mix deps.get
mix deps.unlock --check-unused
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix test.fuzz
mix docs --warnings-as-errors
mix hex.build
mix hex.publish --dry-run --yes
```

La simulación no publica. Revisa que la versión sea 1.5.0, las dependencias
sean las esperadas y el paquete no contenga archivos privados.
El resultado local es `paper_forge-1.5.0.tar`.
Credo mantiene hallazgos de refactorización anteriores; CI comprueba diferencias.
En la compilación limpia aparecieron advertencias de la dependencia externa
sign_core; la compilación estricta del código de PaperForge pasó.
La simulación puede imprimir “Publishing package/docs”, pero con --dry-run no
realiza la publicación.

## 3. Autenticarse en Hex

Tu sesión local estaba vencida durante esta preparación:

```sh
mix hex.user auth
mix hex.user whoami
mix hex.info paper_forge
```

Usa una cuenta que sea propietaria del paquete `paper_forge` en Hex.
Ser propietario del repositorio en GitHub no concede permisos en Hex.
Si 1.5.0 ya existe cuando llegues a este paso, detente y comprueba quién la
publicó; no uses `--replace` automáticamente.

## 4. Crear el tag y publicar

Con el árbol limpio y en el commit verificado:

```sh
git tag -a v1.5.0 -m "PaperForge 1.5.0"
git push origin v1.5.0
mix hex.publish
```

Confirma el resumen que muestra Hex. El comando publica el paquete y genera
y publica su documentación. No hace falta ejecutar un segundo comando de docs
cuando todo termina correctamente.

Si únicamente falló la subida de documentación después de publicar el paquete,
puedes reintentar esa parte desde el mismo tag:

```sh
mix hex.publish docs
```

Crea un GitHub Release seleccionando el tag existente `v1.5.0`, usa como título
**PaperForge 1.5.0 — PDF Interoperability & Transformation Engine** y pega el
contenido de RELEASE_1.5.0.md. No necesitas adjuntar el tar de Hex.

## 5. Comprobar la publicación

Comprueba la versión en [Hex](https://hex.pm/packages/paper_forge) y la
[documentación 1.5.0](https://hexdocs.pm/paper_forge/1.5.0/).

En un proyecto de prueba independiente:

```elixir
{:paper_forge, "~> 1.5.0"}
```

Ejecuta `mix deps.get` y `mix compile --warnings-as-errors`, genera un PDF y
ábrelo. Verifica que la resolución realmente seleccionó 1.5.0.

Referencias oficiales:
[publicación de paquetes](https://hex.pm/docs/publish) y
[opciones de mix hex.publish](https://hex.hexdocs.pm/Mix.Tasks.Hex.Publish.html).
