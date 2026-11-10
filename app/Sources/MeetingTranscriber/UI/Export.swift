import AppKit
import CoreText
import DetectorCore
import UniformTypeIdentifiers

/// Экспорт встречи: Markdown, DOCX, PDF и копирование текста. Всё строится из одного `MeetingDocument`.
enum Export {
    enum Format: CaseIterable {
        case markdown, docx, pdf

        var title: String {
            switch self {
            case .markdown: "Markdown…"
            case .docx: "Word (DOCX)…"
            case .pdf: "PDF…"
            }
        }

        var fileExtension: String {
            switch self {
            case .markdown: "md"
            case .docx: "docx"
            case .pdf: "pdf"
            }
        }
    }

    static func data(_ document: MeetingDocument, as format: Format) throws -> Data {
        switch format {
        case .markdown:
            return Data(document.markdown().utf8)
        case .docx:
            let text = attributed(document)
            return try text.data(from: NSRange(location: 0, length: text.length),
                                 documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        case .pdf:
            return pdf(attributed(document))
        }
    }

    /// Диалог сохранения; ошибка записи — диалог с причиной.
    @MainActor static func save(_ document: MeetingDocument, as format: Format) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.title.replacingOccurrences(of: "/", with: "-") + "." + format.fileExtension
        if let type = UTType(filenameExtension: format.fileExtension) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data(document, as: format).write(to: url, options: .atomic)
        } catch {
            alert("Не удалось сохранить файл", error)
        }
    }

    @MainActor static func copy(_ document: MeetingDocument) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(document.plainText(), forType: .string)
    }

    @MainActor static func alert(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Понятно")
        alert.runModal()
    }

    /// Заголовок, дата и длительность, summary, транскрипт с именами и таймкодами. Цвета заданы явно: документ печатается на белом.
    static func attributed(_ document: MeetingDocument) -> NSAttributedString {
        let out = NSMutableAttributedString()
        func add(_ text: String, size: CGFloat = 11, bold: Bool = false, color: NSColor = .black, after: CGFloat = 6, indent: CGFloat = 0) {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = after
            style.lineSpacing = 2
            style.firstLineHeadIndent = indent
            style.headIndent = indent
            // «**жирное**» внутри строки: нечётные куски — жирные
            for (index, part) in text.components(separatedBy: "**").enumerated() where !part.isEmpty {
                let font = bold || index % 2 == 1 ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
                out.append(NSAttributedString(string: part, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]))
            }
            out.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: size), .paragraphStyle: style]))
        }

        add(document.title, size: 20, bold: true, after: 4)
        var meta: [String] = []
        if let date = document.startedAt {
            meta.append(date.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(Locale(identifier: "ru_RU"))))
        }
        if let duration = document.duration, duration > 0 { meta.append(MeetingDocument.durationText(duration)) }
        if !meta.isEmpty { add(meta.joined(separator: " · "), color: .darkGray, after: 16) }

        let blocks = document.summaryBlocks()
        if !blocks.isEmpty {
            add("Summary", size: 15, bold: true, after: 8)
            for block in blocks {
                switch block {
                case .heading(let text): add(text, size: 12, bold: true, after: 4)
                case .bullet(let text): add("•  " + text, after: 3, indent: 12)
                case .paragraph(let text): add(text)
                }
            }
            add("", after: 6)
        }

        add("Транскрипт", size: 15, bold: true, after: 8)
        if document.lines.isEmpty { add("Речь не распознана", color: .darkGray) }
        for line in document.lines {
            // звёздочки в тексте реплики — не разметка: жирным только таймкод и имя
            let text = line.text.replacingOccurrences(of: "**", with: "")
            add("**[\(MeetingDocument.timecode(line.start))] \(line.speakerName):** \(text)")
        }
        return out
    }

    /// Постранично через CoreText, A4 с полями 56: `dataWithPDF` дал бы одну длинную страницу.
    static func pdf(_ text: NSAttributedString) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        let setter = CTFramesetterCreateWithAttributedString(text)
        var position = 0
        while position < text.length {
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: position, length: 0),
                                                 CGPath(rect: box.insetBy(dx: 56, dy: 56), transform: nil), nil)
            CTFrameDraw(frame, context)
            context.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame).length
            if visible == 0 { break }
            position += visible
        }
        context.closePDF()
        return data as Data
    }
}
