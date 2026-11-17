import Foundation
import SwiftUI
import UIKit
import PDFKit

/// Opciones de exportación limpia de PixelVoice Pro.
enum ExportFormatSelection: String, CaseIterable, Identifiable {
    case audioOnly = "Solo Archivo de Audio"
    case transcriptPDF = "Transcripción en PDF (.pdf)"
    case transcriptMarkdown = "Transcripción en Markdown (.md)"
    case transcriptPlainText = "Transcripción en Texto Plano (.txt)"
    case completePackage = "Paquete Completo (Audio + PDF + MD + TXT)"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .audioOnly: return "waveform.circle.fill"
        case .transcriptPDF: return "doc.richtext.fill"
        case .transcriptMarkdown: return "text.badge.checkmark"
        case .transcriptPlainText: return "doc.plaintext.fill"
        case .completePackage: return "shippingbox.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .audioOnly:
            return "Exporta el archivo de audio original (.m4a o .wav) con nombre fechado al segundo."
        case .transcriptPDF:
            return "Documento PDF maquetado con hora exacta, locutores en color, marcadores y etiquetas [😂 Risas]."
        case .transcriptMarkdown:
            return "Archivo .md estructurado con tablas de metadatos, bloques por locutor y eventos acústicos."
        case .transcriptPlainText:
            return "Archivo .txt universal con marcas de tiempo exactas al segundo, locutores y eventos."
        case .completePackage:
            return "Incluye el audio original junto con la transcripción en PDF, Markdown (.md) y Texto (.txt) lista para Google NotebookLM."
        }
    }
}

/// Servicio encargado de generar archivos de exportación (PDF, Markdown, TXT, Audio y Paquete Completo).
enum ExportService {
    /// Genera los `URL` listos para compartir mediante `UIActivityViewController` según la opción elegida.
    static func generateExportURLs(
        for recording: VoiceRecording,
        sourceAudioURL: URL,
        selection: ExportFormatSelection
    ) throws -> [URL] {
        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixelVoiceExports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)

        let cleanTitle = sanitizeFileName(recording.title)
        let exactStamp = ExactDateFormatter.filenameTimestamp(from: recording.createdAt)
        let baseName = "\(cleanTitle)_\(exactStamp)"

        switch selection {
        case .audioOnly:
            let destAudioURL = exportRoot.appendingPathComponent("\(baseName).\(recording.audioFormat.rawValue)")
            try copyOrSynthesizeAudioIfNeeded(from: sourceAudioURL, to: destAudioURL, duration: recording.duration)
            return [destAudioURL]

        case .transcriptPDF:
            let pdfURL = exportRoot.appendingPathComponent("\(baseName).pdf")
            let pdfData = renderPDF(for: recording)
            try pdfData.write(to: pdfURL, options: .atomic)
            return [pdfURL]

        case .transcriptMarkdown:
            let mdURL = exportRoot.appendingPathComponent("\(baseName).md")
            let mdText = buildMarkdown(for: recording)
            try mdText.write(to: mdURL, atomically: true, encoding: .utf8)
            return [mdURL]

        case .transcriptPlainText:
            let txtURL = exportRoot.appendingPathComponent("\(baseName).txt")
            let txtContent = buildPlainText(for: recording)
            try txtContent.write(to: txtURL, atomically: true, encoding: .utf8)
            return [txtURL]

        case .completePackage:
            let packageDir = exportRoot.appendingPathComponent("Paquete_\(baseName)", isDirectory: true)
            if FileManager.default.fileExists(atPath: packageDir.path) {
                try FileManager.default.removeItem(at: packageDir)
            }
            try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)

            let audioDest = packageDir.appendingPathComponent("\(baseName).\(recording.audioFormat.rawValue)")
            try copyOrSynthesizeAudioIfNeeded(from: sourceAudioURL, to: audioDest, duration: recording.duration)

            let pdfDest = packageDir.appendingPathComponent("\(baseName).pdf")
            try renderPDF(for: recording).write(to: pdfDest, options: .atomic)

            let mdDest = packageDir.appendingPathComponent("\(baseName).md")
            try buildMarkdown(for: recording).write(to: mdDest, atomically: true, encoding: .utf8)

            let txtDest = packageDir.appendingPathComponent("\(baseName).txt")
            try buildPlainText(for: recording).write(to: txtDest, atomically: true, encoding: .utf8)

            return [audioDest, pdfDest, mdDest, txtDest]
        }
    }

    // MARK: - Generador de Markdown (.md)

    static func buildMarkdown(for recording: VoiceRecording) -> String {
        var lines: [String] = []
        lines.append("# 🎙️ \(recording.title)")
        lines.append("")
        lines.append("> Generado por **Voice Notes** · Grabadora y Transcripción Inteligente")
        lines.append("")
        lines.append("## 📋 Metadatos Exactos del Archivo")
        lines.append("| Propiedad | Valor Exacto |")
        lines.append("| :--- | :--- |")
        lines.append("| **Fecha y Hora de Creación** | `\(recording.formattedExactCreationDate)` |")
        lines.append("| **Fecha y Hora de Finalización** | `\(recording.formattedExactEndDate)` |")
        lines.append("| **Franja del Día** | \(recording.dayPeriod.rawValue) |")
        lines.append("| **Duración Exacta** | `\(recording.formattedPreciseDuration)` |")
        lines.append("| **Peso del Archivo** | `\(recording.formattedDetailedFileSize)` |")
        lines.append("| **Formato y Calidad** | `\(recording.audioFormat.displayName)` · `\(Int(recording.sampleRate)) Hz` |")
        if !recording.tags.isEmpty {
            let tagNames = recording.tags.map(\.name).joined(separator: ", ")
            lines.append("| **Etiquetas (Tags)** | \(tagNames) |")
        }
        lines.append("")

        if !recording.speakers.isEmpty {
            lines.append("## 🗣️ Locutores Identificados (Speaker Diarization)")
            for spk in recording.speakers {
                let dur = ExactDateFormatter.standardDuration(spk.totalSpeakingDuration)
                lines.append("- **\(spk.displayName)** (`\(spk.defaultLabel)`): \(dur) hablados · \(spk.wordCount) palabras · Pitch medio \(Int(spk.pitchMeanHz)) Hz")
            }
            lines.append("")
        }

        if !recording.bookmarks.isEmpty {
            lines.append("## 🔖 Marcadores de Tiempo en Vivo")
            for bm in recording.bookmarks {
                let notePart = bm.note.isEmpty ? "" : " — *\(bm.note)*"
                lines.append("- **[\(bm.formattedTimestamp)]** \(bm.label)\(notePart) *(Creado: \(bm.formattedCreatedAtExact))*")
            }
            lines.append("")
        }

        lines.append("## 📝 Transcripción Completa y Eventos Acústicos")
        lines.append("")

        for segment in recording.segments {
            let speaker = recording.speakerProfile(for: segment.speakerId)
            let startStr = ExactDateFormatter.standardDuration(segment.startTime)
            let endStr = ExactDateFormatter.standardDuration(segment.endTime)
            lines.append("### [\(startStr) - \(endStr)] **\(speaker.displayName)**")

            var paragraph = segment.text
            if !segment.inlineEvents.isEmpty {
                let eventTags = segment.inlineEvents.map(\.formattedInlineTag).joined(separator: " ")
                paragraph += " " + eventTags
            }
            lines.append(paragraph)
            lines.append("")
        }

        if !recording.acousticEvents.isEmpty {
            lines.append("---")
            lines.append("## 🔊 Resumen de Eventos Acústicos Detectados (SoundAnalysis)")
            for ev in recording.acousticEvents {
                lines.append("- `\(ev.formattedInlineTag)` — Confianza: \(Int(ev.confidence * 100))% (Duración: \(String(format: "%.1fs", ev.duration)))")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Generador de Texto Plano (.txt)

    static func buildPlainText(for recording: VoiceRecording) -> String {
        var lines: [String] = []
        let separator = String(repeating: "=", count: 68)
        lines.append(separator)
        lines.append("VOICE NOTES - TRANSCRIPCIÓN E INFORME ACÚSTICO")
        lines.append(separator)
        lines.append("TÍTULO:              \(recording.title)")
        lines.append("FECHA Y HORA EXACTA: \(recording.formattedExactCreationDate)")
        lines.append("FINALIZACIÓN EXACTA: \(recording.formattedExactEndDate)")
        lines.append("FRANJA HORARIA:      \(recording.dayPeriod.rawValue)")
        lines.append("DURACIÓN EXACTA:     \(recording.formattedPreciseDuration)")
        lines.append("PESO DEL ARCHIVO:    \(recording.formattedDetailedFileSize)")
        lines.append("FORMATO DE AUDIO:    \(recording.audioFormat.displayName) (\(Int(recording.sampleRate)) Hz)")
        if !recording.tags.isEmpty {
            lines.append("ETIQUETAS:           \(recording.tags.map(\.name).joined(separator: ", "))")
        }
        lines.append(separator)
        lines.append("")

        if !recording.speakers.isEmpty {
            lines.append("LOCUTORES IDENTIFICADOS:")
            for spk in recording.speakers {
                lines.append("  • \(spk.displayName) (\(spk.defaultLabel)) - \(spk.wordCount) palabras (\(ExactDateFormatter.standardDuration(spk.totalSpeakingDuration)))")
            }
            lines.append("")
        }

        if !recording.bookmarks.isEmpty {
            lines.append("MARCADORES DE TIEMPO (BOOKMARKS):")
            for bm in recording.bookmarks {
                lines.append("  • [\(bm.formattedTimestamp)] \(bm.label) \(bm.note.isEmpty ? "" : "- \(bm.note)")")
            }
            lines.append("")
        }

        lines.append("TRANSCRIPCIÓN SINCRONIZADA:")
        lines.append(String(repeating: "-", count: 68))

        for segment in recording.segments {
            let speaker = recording.speakerProfile(for: segment.speakerId)
            let startStr = ExactDateFormatter.standardDuration(segment.startTime)
            let endStr = ExactDateFormatter.standardDuration(segment.endTime)
            let inlineTags = segment.inlineEvents.map(\.formattedInlineTag).joined(separator: " ")
            let suffix = inlineTags.isEmpty ? "" : " \(inlineTags)"
            lines.append("[\(startStr) - \(endStr)] \(speaker.displayName.uppercased()):")
            lines.append("\(segment.text)\(suffix)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Generador de PDF Nativo (`UIGraphicsPDFRenderer`)

    static func renderPDF(for recording: VoiceRecording) -> Data {
        let pageWidth: CGFloat = 595.2  // A4 ancho en puntos
        let pageHeight: CGFloat = 841.8 // A4 alto en puntos
        let margin: CGFloat = 42.0
        let contentWidth = pageWidth - (margin * 2)
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { context in
            context.beginPage()
            var cursorY: CGFloat = margin

            func ensureSpace(_ heightNeeded: CGFloat) {
                if cursorY + heightNeeded > (pageHeight - margin) {
                    context.beginPage()
                    cursorY = margin
                }
            }

            func drawText(_ text: String, font: UIFont, color: UIColor, spacingAfter: CGFloat = 6) {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = 3
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraphStyle
                ]
                let attributed = NSAttributedString(string: text, attributes: attributes)
                let bounding = attributed.boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                ensureSpace(ceil(bounding.height) + spacingAfter)
                attributed.draw(in: CGRect(x: margin, y: cursorY, width: contentWidth, height: ceil(bounding.height)))
                cursorY += ceil(bounding.height) + spacingAfter
            }

            // Cabecera del PDF
            drawText(
                "VOICE NOTES · INFORME DE TRANSCRIPCIÓN E IA ACÚSTICA",
                font: .systemFont(ofSize: 10, weight: .bold),
                color: Color.uiColor(fromHex: "#3B82F6"),
                spacingAfter: 4
            )
            drawText(
                recording.title,
                font: .systemFont(ofSize: 20, weight: .bold),
                color: .black,
                spacingAfter: 6
            )
            drawText(
                "Fecha y Hora Exacta: \(recording.formattedExactCreationDate) (\(recording.dayPeriod.rawValue))",
                font: .monospacedSystemFont(ofSize: 11, weight: .semibold),
                color: Color.uiColor(fromHex: "#1E293B"),
                spacingAfter: 4
            )
            drawText(
                "Duración: \(recording.formattedPreciseDuration)   |   Peso: \(recording.formattedDetailedFileSize)   |   Formato: \(recording.audioFormat.shortBadge)",
                font: .systemFont(ofSize: 10, weight: .medium),
                color: .darkGray,
                spacingAfter: 12
            )

            // Línea divisoria
            ensureSpace(12)
            let dividerPath = UIBezierPath()
            dividerPath.move(to: CGPoint(x: margin, y: cursorY))
            dividerPath.addLine(to: CGPoint(x: pageWidth - margin, y: cursorY))
            UIColor.lightGray.setStroke()
            dividerPath.lineWidth = 0.8
            dividerPath.stroke()
            cursorY += 14

            // Locutores
            if !recording.speakers.isEmpty {
                let speakerSummary = recording.speakers
                    .map { "\($0.displayName) (\($0.wordCount) pal. · \(ExactDateFormatter.standardDuration($0.totalSpeakingDuration)))" }
                    .joined(separator: "   •   ")
                drawText(
                    "Locutores detectados: \(speakerSummary)",
                    font: .systemFont(ofSize: 10.5, weight: .semibold),
                    color: Color.uiColor(fromHex: "#334155"),
                    spacingAfter: 14
                )
            }

            // Marcadores
            if !recording.bookmarks.isEmpty {
                drawText(
                    "Marcadores en Vivo (Bookmarks):",
                    font: .systemFont(ofSize: 12, weight: .bold),
                    color: .black,
                    spacingAfter: 4
                )
                for bm in recording.bookmarks {
                    drawText(
                        "• [\(bm.formattedTimestamp)] \(bm.label) \(bm.note.isEmpty ? "" : "— \(bm.note)")",
                        font: .systemFont(ofSize: 10.5, weight: .regular),
                        color: .darkGray,
                        spacingAfter: 4
                    )
                }
                cursorY += 8
            }

            // Segmentos de Transcripción
            drawText(
                "Transcripción Sincronizada y Eventos Acústicos:",
                font: .systemFont(ofSize: 13, weight: .bold),
                color: .black,
                spacingAfter: 10
            )

            for segment in recording.segments {
                let speaker = recording.speakerProfile(for: segment.speakerId)
                let startStr = ExactDateFormatter.standardDuration(segment.startTime)
                let endStr = ExactDateFormatter.standardDuration(segment.endTime)

                drawText(
                    "[\(startStr) - \(endStr)]  \(speaker.displayName)",
                    font: .systemFont(ofSize: 11, weight: .bold),
                    color: Color.uiColor(fromHex: speaker.colorHex),
                    spacingAfter: 2
                )

                var bodyText = segment.text
                if !segment.inlineEvents.isEmpty {
                    let tags = segment.inlineEvents.map(\.formattedInlineTag).joined(separator: "  ")
                    bodyText += "\n" + tags
                }

                drawText(
                    bodyText,
                    font: .systemFont(ofSize: 11, weight: .regular),
                    color: .black,
                    spacingAfter: 12
                )
            }
        }
    }

    // MARK: - Helpers de Archivos

    private static func sanitizeFileName(_ raw: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = raw
            .components(separatedBy: invalidCharacters)
            .joined()
            .replacingOccurrences(of: " ", with: "_")
        return cleaned.isEmpty ? "Grabacion_VoiceNotes" : String(cleaned.prefix(42))
    }

    private static func copyOrSynthesizeAudioIfNeeded(from sourceURL: URL, to destinationURL: URL, duration: TimeInterval) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } else {
            try RecordingStorageService.generateSynthesizedDemoWAVFile(at: destinationURL, durationSeconds: min(duration, 15.0))
        }
    }
}
