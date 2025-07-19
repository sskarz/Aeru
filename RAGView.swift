//
//  RAGView.swift
//  SVDBDemo
//
//  Created by Sanskar Thapa on July 15th, 2025.
//

import Accelerate
import CoreML
import NaturalLanguage
import SVDB
import SwiftUI
import FoundationModels
import SwiftSoup
import Foundation

struct EmbeddingEntry: Codable {
    let id: UUID
    let text: String
    let embedding: [Double]
    let magnitude: Double
}

struct WebSearchResult {
    let title: String
    let url: String
    let content: String
}

func generateRandomSentence() -> String {
    var sentence = ""
    for _ in 1...5 {
        if let randomWord = words.randomElement() {
            sentence += randomWord + " "
        }
    }
    return sentence.trimmingCharacters(in: .whitespaces)
}

class WebSearchService {
    private let session = URLSession.shared
    
    func searchAndScrape(query: String) async -> [WebSearchResult] {
        do {
            // Get search results from DuckDuckGo search engine
            let searchResults = try await performSearch(query: query)
            
            // Scrape each website
            var webResults: [WebSearchResult] = []
            
            for (index, result) in searchResults.enumerated() {
                // Add delay between requests to be respectful
                if index > 0 {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                }
                
                if let scrapedContent = await scrapeWebsite(url: result.url) {
                    let webResult = WebSearchResult(
                        title: scrapedContent.pageTitle.isEmpty ? result.title : scrapedContent.pageTitle,
                        url: result.url,
                        content: scrapedContent.content
                    )
                    webResults.append(webResult)
                }
            }
            
            return webResults
        } catch {
            print("Web search error: \(error)")
            return []
        }
    }
    
    private func performSearch(query: String) async throws -> [(title: String, url: String)] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://html.duckduckgo.com/html/?q=\(encodedQuery)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""
        
        return parseSearchResults(from: html)
    }
    
    private func parseSearchResults(from html: String) -> [(title: String, url: String)] {
        var results: [(title: String, url: String)] = []
        let lines = html.components(separatedBy: .newlines)
        
        for line in lines {
            if line.contains("result__a") && line.contains("href=") {
                if let result = parseResultLine(line) {
                    results.append(result)
                    if results.count >= 3 {
                        break
                    }
                }
            }
        }
        
        // Fallback parsing if no results found
        if results.isEmpty {
            results = parseAlternativeResults(from: html)
        }
        
        return results
    }
    
    private func parseResultLine(_ line: String) -> (title: String, url: String)? {
        guard let hrefStart = line.range(of: "href=\"") else { return nil }
        let afterHref = String(line[hrefStart.upperBound...])
        
        guard let hrefEnd = afterHref.range(of: "\"") else { return nil }
        let url = cleanAndValidateURL(String(afterHref[..<hrefEnd.lowerBound]))
        
        guard let titleStart = line.range(of: ">") else { return nil }
        let afterTitle = String(line[titleStart.upperBound...])
        
        guard let titleEnd = afterTitle.range(of: "</a>") else { return nil }
        let title = String(afterTitle[..<titleEnd.lowerBound])
        
        if !url.isEmpty && !title.isEmpty && isValidURL(url) {
            return (title: title, url: url)
        }
        
        return nil
    }
    
    private func parseAlternativeResults(from html: String) -> [(title: String, url: String)] {
        var results: [(title: String, url: String)] = []
        let lines = html.components(separatedBy: .newlines)
        
        for line in lines {
            if line.contains("href=") && (line.contains("http://") || line.contains("https://")) {
                if let result = parseAnyLinkLine(line) {
                    results.append(result)
                    if results.count >= 3 {
                        break
                    }
                }
            }
        }
        
        return results
    }
    
    private func parseAnyLinkLine(_ line: String) -> (title: String, url: String)? {
        guard let hrefStart = line.range(of: "href=\"") else { return nil }
        let afterHref = String(line[hrefStart.upperBound...])
        
        guard let hrefEnd = afterHref.range(of: "\"") else { return nil }
        var url = String(afterHref[..<hrefEnd.lowerBound])
        
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            url = cleanAndValidateURL(url)
            let title = extractTitleFromLine(line) ?? url
            
            if !title.isEmpty && isValidURL(url) && !url.contains("duckduckgo.com") {
                return (title: title, url: url)
            }
        }
        
        return nil
    }
    
    private func extractTitleFromLine(_ line: String) -> String? {
        if let start = line.range(of: ">") {
            let afterStart = String(line[start.upperBound...])
            if let end = afterStart.range(of: "<") {
                let title = String(afterStart[..<end.lowerBound])
                return title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    
    private func cleanAndValidateURL(_ url: String) -> String {
        var cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanURL.hasPrefix("//duckduckgo.com/l/?uddg=") {
            if let decodedURL = extractURLFromDuckDuckGoRedirect(cleanURL) {
                cleanURL = decodedURL
            }
        }
        
        if cleanURL.hasPrefix("//") {
            cleanURL = "https:" + cleanURL
        } else if cleanURL.hasPrefix("/") {
            cleanURL = "https://duckduckgo.com" + cleanURL
        }
        
        if !cleanURL.hasPrefix("http://") && !cleanURL.hasPrefix("https://") && cleanURL.hasPrefix("www.") {
            cleanURL = "https://" + cleanURL
        }
        
        return cleanURL
    }
    
    private func extractURLFromDuckDuckGoRedirect(_ redirectURL: String) -> String? {
        if let uddgRange = redirectURL.range(of: "uddg=") {
            let afterUddg = String(redirectURL[uddgRange.upperBound...])
            if let endRange = afterUddg.range(of: "&") {
                let encodedURL = String(afterUddg[..<endRange.lowerBound])
                return encodedURL.removingPercentEncoding
            } else {
                return afterUddg.removingPercentEncoding
            }
        }
        return nil
    }
    
    private func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
    
    private func scrapeWebsite(url: String) async -> (pageTitle: String, content: String)? {
        guard let websiteURL = URL(string: url) else { return nil }
        
        var request = URLRequest(url: websiteURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        
        do {
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                return nil
            }
            
            let html = String(data: data, encoding: .utf8) ?? ""
            return parseWebsiteContent(from: html)
        } catch {
            print("Scraping error for \(url): \(error)")
            return nil
        }
    }
    
    private func parseWebsiteContent(from html: String) -> (pageTitle: String, content: String) {
        do {
            let doc = try SwiftSoup.parse(html)
            
            // Extract title
            let pageTitle = try doc.title()
            
            // Remove unwanted elements
            try doc.select("script").remove()
            try doc.select("style").remove()
            try doc.select("nav").remove()
            try doc.select("header").remove()
            try doc.select("footer").remove()
            try doc.select(".advertisement").remove()
            try doc.select(".ad").remove()
            try doc.select("[class*=cookie]").remove()
            try doc.select("[class*=popup]").remove()
            
            var allText = ""
            let maxLength = 4000
            
            // Extract text from paragraphs
            let paragraphs = try doc.select("p")
            for paragraph in paragraphs {
                let text = try paragraph.text()
                if shouldIncludeText(text) {
                    allText += text + " "
                    if allText.count >= maxLength { break }
                }
            }
            
            // Extract from articles if needed
            if allText.count < 500 {
                let articles = try doc.select("article")
                for article in articles {
                    let text = try article.text()
                    if shouldIncludeText(text) {
                        allText += text + " "
                        if allText.count >= maxLength { break }
                    }
                }
            }
            
            // Extract from content divs if needed
            if allText.count < 500 {
                let contentDivs = try doc.select("div[class*=content], div[class*=main], div[class*=body]")
                for div in contentDivs {
                    let text = try div.text()
                    if shouldIncludeText(text) {
                        allText += text + " "
                        if allText.count >= maxLength { break }
                    }
                }
            }
            
            // Extract headers if still needed
            if allText.count < 300 {
                let headers = try doc.select("h1, h2, h3, h4, h5, h6")
                for header in headers {
                    let text = try header.text()
                    if shouldIncludeText(text) && text.count > 5 {
                        allText += text + " "
                        if allText.count >= maxLength { break }
                    }
                }
            }
            
            if allText.count > maxLength {
                allText = String(allText.prefix(maxLength)) + "..."
            }
            
            return (
                pageTitle: pageTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                content: allText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            
        } catch {
            return (pageTitle: "", content: "Failed to parse content")
        }
    }
    
    private func shouldIncludeText(_ text: String) -> Bool {
        guard text.count > 20 else { return false }
        
        let lowercaseText = text.lowercased()
        let unwantedKeywords = [
            "cookie", "javascript", "advertisement", "subscribe", "newsletter",
            "privacy policy", "terms of service", "follow us", "share this"
        ]
        
        for keyword in unwantedKeywords {
            if lowercaseText.contains(keyword) {
                return false
            }
        }
        
        return true
    }
}

struct RAGView: View {
    let collectionName: String = "testCollection"
    @State private var collection: Collection?
    @State private var query: String = ""
    @State private var newEntry: String = ""
    @State private var neighbors: [(String, Double)] = []
    @State private var userLLMQuery: String = ""
    @State private var userLLMResponse: String.PartiallyGenerated = ""
    @State private var session: LanguageModelSession = LanguageModelSession()
    @State private var isWebSearching: Bool = false
    @State private var webSearchResults: [WebSearchResult] = []
    private let webSearchService = WebSearchService()

    var body: some View {
        VStack {
            TextField("Enter RAG Vector query", text: $query)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())

            HStack {
                TextField("New Entry", text: $newEntry)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Add Entry") {
                    Task {
                        await addEntry(newEntry)
                    }
                }
            }
            .padding()

            Button("Generate Random Embeddings") {
                Task {
                    await generateRandomEmbeddings()
                }
            }
            .padding()
            
            HStack {
                TextField("User LLM Query", text: $userLLMQuery)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            HStack {
                Button("RAG LLM") {
                    Task {
                        try await queryLLM()
                    }
                }.padding()
                
                Button("Web Search") {
                    Task {
                        try await webSearch()
                    }
                }
                .padding()
                .disabled(isWebSearching)
                .overlay(
                    isWebSearching ?
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Searching...")
                            .font(.caption)
                    } : nil
                )
            }
            
            // Web search results indicato
            if !webSearchResults.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Web Sources Used:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    
                    ForEach(Array(webSearchResults.enumerated()), id: \.offset) { index, result in
                        Text("• \(result.title)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            TextEditor(text: $userLLMResponse)
                .frame(minHeight: 100)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                )
                .background(Color(.systemGray6))
                .cornerRadius(8)
            

            List(neighbors, id: \.0) { neighbor in
                Text("\(neighbor.0) - \(neighbor.1)")
            }
            
        }
        .padding()
        .onAppear {
            Task {
                await loadCollection()
            }
        }
    }
    
    func webSearch() async throws {
        userLLMResponse = ""
        isWebSearching = true
        webSearchResults = []
        
        // Perform web search and scraping
        let results = await webSearchService.searchAndScrape(query: userLLMQuery)
        webSearchResults = results
        
        // Create context from web search results
        let webContext = results.map { result in
            """
            Title: \(result.title)
            URL: \(result.url)
            Content: \(result.content)
            """
        }.joined(separator: "\n\n---\n\n")
        
        // Create enhanced prompt with web context
        let prompt = """
                You are a helpful assistant that answers questions based on both web search results and provided context.
                
                Web Search Results:
                \(webContext)
                
                Question: \(userLLMQuery)
                
                Instructions:
                1. Answer based primarily on the web search results above
                2. Be accurate and cite the sources when possible
                3. If the web results don't contain enough information, say so
                4. Provide a comprehensive and informative response
                
                Answer:
                """
        print("WEB SEARCH PROMPT: \n", prompt)
        
        // Generate response using LLM
        let responseStream = session.streamResponse(to: prompt)
        for try await partialStream in responseStream {
            userLLMResponse = partialStream
        }
        
        isWebSearching = false
    }
    
    func queryLLM() async throws {
        userLLMResponse = ""
        await findLLMNeighbors()
        webSearchResults = [] // Clear web search results when using RAG
        
        let prompt = """
                You are a helpful assistant that answers questions based on the provided context.
                
                Context:
                \(neighbors.map { $0.0 }.joined(separator: "\n"))
                
                Question: \(userLLMQuery)
                
                Instructions:
                1. Answer based solely on the information provided in the context
                2. If the context doesn't contain enough information, say so
                3. Be concise and accurate
                
                Answer:
                """
        let responseStream = session.streamResponse(to: prompt)
        for try await partialStream in responseStream {
            userLLMResponse = partialStream
        }
    }

    func loadCollection() async {
        do {
            collection = try SVDB.shared.collection(collectionName)
        } catch {
            print("Failed to load collection:", error)
        }
    }

    func generateRandomEmbeddings() async {
        var randomSentences: [String] = []
        for _ in 1...100 {
            let sentence = generateRandomSentence()
            randomSentences.append(sentence)
        }

        for sentence in randomSentences {
            await addEntry(sentence)
        }

        print("Done creating")
    }

    func addEntry(_ entry: String) async {
        guard let collection = collection else { return }
        guard let embedding = generateEmbedding(for: entry) else {
            return
        }

        collection.addDocument(text: entry, embedding: embedding)
    }

    func generateEmbedding(for sentence: String) -> [Double]? {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            return nil
        }

        let words = sentence.lowercased().split(separator: " ")
        guard let firstVector = embedding.vector(for: String(words.first!)) else {
            return nil
        }

        var vectorSum = [Double](firstVector)

        for word in words.dropFirst() {
            if let vector = embedding.vector(for: String(word)) {
                vDSP_vaddD(vectorSum, 1, vector, 1, &vectorSum, 1, vDSP_Length(vectorSum.count))
            }
        }

        var vectorAverage = [Double](repeating: 0, count: vectorSum.count)
        var divisor = Double(words.count)
        vDSP_vsdivD(vectorSum, 1, &divisor, &vectorAverage, 1, vDSP_Length(vectorAverage.count))

        return vectorAverage
    }
    
    func findLLMNeighbors() async {
        guard let collection = collection else { return }
        guard let queryEmbedding = generateEmbedding(for: userLLMQuery) else {
            return
        }
        
        let results = collection.search(query: queryEmbedding, num_results: 5)
        neighbors = results.map { ($0.text, $0.score) }
        print("NEIGHBORS: ", neighbors)
    }
}

struct RAGView_Previews: PreviewProvider {
    static var previews: some View {
        RAGView()
    }
}
