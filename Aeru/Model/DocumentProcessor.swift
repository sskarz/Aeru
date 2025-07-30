import Foundation
import PDFKit

class DocumentProcessor {
    
    static func extractTextFromPDF(at url: URL) -> String? {
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to access security scoped resource")
            return nil
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        guard let pdfDocument = PDFDocument(url: url) else {
            print("Failed to create PDF document from URL: \(url)")
            return nil
        }
        
        let pageCount = pdfDocument.pageCount
        var extractedText = ""
        
        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            
            if let pageText = page.string {
                extractedText += pageText + "\n"
            }
        }
        
        return extractedText.isEmpty ? nil : extractedText
    }
    
    static func chunkText(_ text: String, maxChunkSize: Int = 3500) -> [String] {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { sentence in
                sentence.hasSuffix(".") || sentence.hasSuffix("!") || sentence.hasSuffix("?") ? 
                sentence : sentence + "."
            }
        
        var chunks: [String] = []
        var currentChunk = ""
        
        for sentence in sentences {
            let potentialChunk = currentChunk.isEmpty ? sentence : currentChunk + " " + sentence
            
            if potentialChunk.count <= maxChunkSize {
                currentChunk = potentialChunk
            } else {
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk)
                }
                
                if sentence.count <= maxChunkSize {
                    currentChunk = sentence
                } else {
                    var truncatedSentence = String(sentence.prefix(maxChunkSize))
                    if let lastSpaceIndex = truncatedSentence.lastIndex(of: " ") {
                        truncatedSentence = String(truncatedSentence[..<lastSpaceIndex]) + "."
                    }
                    chunks.append(truncatedSentence)
                    currentChunk = ""
                }
            }
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        return chunks.filter { !$0.isEmpty }
    }
    
    static func saveDocumentToLocalStorage(_ data: Data, fileName: String) -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let fileURL = documentsDirectory.appendingPathComponent("Documents").appendingPathComponent(fileName)
        
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Failed to save document: \(error)")
            return nil
        }
    }
}