# 🎙️ PixelVoice Pro (iOS)

Aplicación de grabadora de voz en alta fidelidad, transcripción inteligente en español, separación de locutores (Speaker Diarization) y detección de eventos acústicos (`SoundAnalysis` / IA) para iPhone.

## ✨ Características Principales

- **Sistema Estricto de Fechas y Horas al Segundo**: Formato obligatorio `DD/MM/YYYY - HH:MM:SS AM/PM` en todas las tarjetas y cabeceras, agrupadas cronológicamente y clasificadas por franja horaria (`Mañana`, `Tarde`, `Noche`).
- **Motor de Audio Avanzado (`AVFoundation`)**: Grabación en `.m4a` (AAC) o `.wav` (Linear PCM) a 44.1 kHz / 48 kHz, onda y espectrograma FFT en vivo a 60 FPS, marcadores en vivo (Bookmarks) y grabación continua en segundo plano.
- **Transcripción, Diarización y Eventos Acústicos**:
  - Transcripción en vivo con `Speech` (On-Device) y soporte modular para API Whisper.
  - Separación automática de hablantes (`Locutor 1`, `Locutor 2`, etc.) con renombrado global en toda la nota.
  - Detección de eventos no verbales (`[😂 Risas - 02:14]`, `[👏 Aplausos]`, `[🎵 Música]`, `[😮‍💨 Suspiro]`, `[⏸️ Pausa larga]`).
- **Reproducción Interactiva (Karaoke 60 Hz) y Búsqueda Profunda**:
  - Resaltado palabra por palabra y salto instantáneo al tocar cualquier palabra o evento.
  - Controles Pro (`-10s`, `-5s`, `+5s`, `+10s`, velocidad `0.5x–2.0x` y **"Saltar silencios"** automático).
  - Buscador global y local con salto al minuto y segundo exacto.
- **Exportación Limpia**: Exporta solo el audio, solo la transcripción en **PDF**, **Markdown (`.md`)** o **Texto plano (`.txt`)**, o el paquete completo.
