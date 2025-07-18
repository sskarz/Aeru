import Playgrounds
import Foundation
import FoundationModels
import SVDB

#Playground {
    // Only functions that matter to use RAG
    // addEntry(document: String) to add documents to SVD
    // generateAnswer() to generate answer
    
    let rag = RAGModel()
    
    rag.loadCollection()
    print("Collection loaded")
    let doc1: String = "Yesterday, a squirrel ran across my window ledge carrying a bright red marble."
    let doc2: String = "I never realized how odd it is to crave pineapple on toast until last Thursday."
    let doc3: String = "The old blue bike in my garage has a horn that sounds like a duck quacking underwater."
    let doc4: String = "Sometimes I wonder if clouds remember the shapes they've been."
    let doc5: String = "My cousin claims his cat can open doorknobs, but I've never seen it happen."
    
    await rag.addEntry(doc1)
    await rag.addEntry(doc2)
    await rag.addEntry(doc3)
    await rag.addEntry(doc4)
    await rag.addEntry(doc5)
    
    let userQuery: String = "Where's my notebook with recipes?"
    
    let response = try await rag.generateAnswer(query: userQuery)
    print(response)
}
