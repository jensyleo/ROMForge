# 🎯 CHECKPOINT: Sistema de Filtros Implementado Correctamente

**Fecha:** 2026-07-30  
**Estado:** ✅ COMPLETO Y VERIFICADO EN VIVO

---

## 📋 Resumen

Se implementó correctamente el sistema de filtros de 5 botones independientes en ROMForge, tras resolver múltiples bugs conceptuales y de implementación. Los filtros ahora funcionan de manera intuitiva y consistente en ambas vistas (árbol de Database y tabla de Games).

---

## 🎮 Los 5 Filtros Implementados

### 1. **Correct** ✅ (Verde)
- Juegos 100% sanos: todos sus roms presentes, bien nombrados, con hashes correctos
- **Definición:** No falta ningún rom, todos tienen nombres correctos y coinciden con los hashes del DAT

### 2. **Incorrect** ⚠️ (Amarillo)
- Juegos con problemas **de nombre solamente** — archivos mal nombrados o encontrados en lugar incorrecto, pero cuyo contenido SÍ coincide con algo real en el DAT
- **Definición:** Problema de ubicación/nombre, no de contenido

### 3. **Bad** 🔶 (Naranja)
- Juegos **incompletos** (faltan algunas, no todas las roms) O con **hash incorrecto** (contenido no coincide con CRC32/MD5/SHA1 declarado)
- **Definición:** Problema real de contenido — bien sea roms faltantes o contenido corrupto/equivocado
- **Nota:** Reusa `AuditStatus.surplus` internamente pero relabelado "Bad" en UI

### 4. **Unknown** ❓ (Gris)
- Archivos genuinamente **desconocidos** — archives que no coinciden con NINGÚN juego en el DAT
- **Definición:** Cero relación con la base de datos
- **Comportamiento:** Siempre se muestran; **nunca se cuentan bajo "Bad"**
- **Nota:** El gris denota "no reconocido", distinto al naranja (problema de conocido incompleto)

### 5. **Missing** ❌ (Rojo)
- Juegos que **no existen en absoluto** — cero archivos encontrados para ese juego en el disco
- **Definición:** El DAT espera el juego, pero no hay ni un solo archivo
- **Nota:** Solo tiene sentido en vista "Database" (DAT-wide); "Rom files" es scoped a archivos reales en disco, por lo que un juego completamente ausente no aparece ahí de todas formas

---

## 🏗️ Arquitectura de Filtrado

### Niveles de Decisión

1. **Cálculo de Categoría Real (Toggle-Independiente)**
   - Función `gameCategory(for:)` — calcula la verdadera categoría de CADA juego desde **todos** sus roms (sin filtrar)
   - Almacenado en `gameAggregateStatusByName` — se actualiza cada vez que cambia el audit report
   - **Nunca depende** de qué botones están presionados

2. **Mostrar/Ocultar Juego**
   - Si el juego es `Unknown` (bucket de archivo sin DAT) → **siempre visible** (respeta `showUnknownArchives`)
   - Si es un juego real → **visible solo si su categoría real está en `activeStatusFilters`**
   - Los 4 botones (Correct/Incorrect/Bad/Missing) son **multi-selección independiente**

3. **Filas de ROM en el Panel de Detalle**
   - Juego seleccionado = mostrar **todas** sus roms sin filtrar
   - Los botones Correct/Incorrect/Bad/Missing **NO controlan qué roms ves** aquí — ese era un bug anterior
   - Cada fila de rom tiene su propio status en la tabla (✅✓❌?) pero la selección del juego no depende de eso

---

## 🐛 Bugs Resueltos en el Camino

### 1. **Juegos "Bad" mostraban gris en lugar de naranja**
- **Causa:** Row icons reutilizaban la función genérica de `.surplus` (gris)
- **Fix:** Creadas `gameSymbolName(for:)` / `gameTint(for:)` específicas para juegos reales
  - Juego real + `.surplus` = ⚠️ naranja
  - Archivo genuinamente desconocido = ❓ gris

### 2. **Conteo de "Bad" incluía archivos Unknown**
- **Causa:** `computeScopedStatusCounts()` sumaba todos los buckets `isSurplusBucket`
- **Fix:** "Unknown" no se cuenta en ningún toggle — son siempre-visibles aparte
- **Resultado:** "Bad: 2" ahora = 2 juegos incompletos/corrupt, no 2+N archivos desconocidos

### 3. **Archivos extra dentro de juegos se mostraban como "Unknown" separado**
- **Causa:** La comprobación de "¿este archivo pertenece a un juego conocido?" dependía de qué toggles estaban activos
- **Fix:** Ahora usa `gameAggregateStatusByName` (toggle-independent) para la comprobación
- **Resultado:** Un archivo extra dentro de `sf2.zip` se pliega correctamente bajo "Street Fighter II", no como "Unknown game"

### 4. **Los toggles ocultaban juegos cuando debían solo ocultar filas de rom**
- **Causa:** Anterior intento de hacer los toggles filtrar juegos directamente filtró filas primero
- **Fix:** Separación clara:
  - Filas: Los toggles Correct/Incorrect/Bad/Missing controlan **qué filas ves en el panel de ROM**
  - Juegos: La **categoría real** del juego (toggle-independent) controla **si el juego aparece en la lista**
  - Unknown: Toggle separado `showUnknownArchives` (no es uno de los 4)

---

## 🎛️ Orden de Filtros en UI

Desde el botón "Show all" hacia la derecha:

```
[Correct] [Incorrect] [Bad] [Unknown] [Missing]
```

Definido por jensyleo 2026-07-30.

---

## 🧪 Verificación en Vivo

- ✅ Botón "Show all" activa los 5 (los 4 status + Unknown toggle)
- ✅ `gng.zip` (2 roms faltantes, 17 correctas) = status "Bad" (naranja)
- ✅ Conteo "Bad" = juegos reales incompletos/corrupt solamente
- ✅ Unknown archivos siempre visibles (si `showUnknownArchives = true`)
- ✅ Panel de ROM de un juego seleccionado muestra **todas** sus roms (sin filtrar por toggles)
- ✅ Árbol de Database y tabla de Games coinciden siempre en qué juegos se ven

---

## 📝 Punto de Control

Este sistema de filtros es **stable, coherent, and ready for expansion**. 

Futuras mejoras pueden construir sobre esta base sin cambiar los conceptos fundamentales:
- Categorías adicionales (por BIOS, por año, por manufacturer, etc.)
- Filtros más granulares a nivel de rom individual
- Agrupación avanzada en el árbol

Pero el núcleo — los 5 botones y su semántica — está **correcto y probado en vivo**.

---

**Hecho por:** Claude + jensyleo  
**Tecnología:** SwiftUI state + `gameAggregateStatusByName` + multi-select toggles  
**Linaje de bugs:** Device exclusion → Status mismatch → Filter semantics → Color coding → Count accuracy  
