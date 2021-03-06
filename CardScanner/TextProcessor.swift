//
//  TextProcessor.swift
//  CardScanner
//
//  Created by Reed Carson on 6/5/18.
//  Copyright © 2018 Reed Carson. All rights reserved.
//

import Foundation


class VisionTextProcessor {
    
    var cardElements = [CardElement]()
    var frequencyFilteredText = [String]()
    
    var mostOccuringTexts = [String:Int]()
    
    private func removeResultsUnderThreshold(_ threshold: Double, texts: [String:Int]) -> [String:Int] {
        //if textfrequency / topresultfrequency < threshold (0.01-1.0) remove
        var validResults = [String:Int]()
        if let highestFrequency = (texts.values.sorted { $0 > $1 }).first {
            for (text, frequency) in texts {
                if Double(frequency / highestFrequency) > threshold {
                    validResults[text] = frequency
                }
            }
        }
        return validResults
    }
    
    func getMostFrequentStringOccurences(_ textLines: [String], withResultsLimit limit: Int, andMinimumFrequency minFrequency: Int = 10) -> [(String, Int)] {
        
        let characterFileteredText = textLines.map {removeSpecialCharsFromString(text: $0)}
        
        for text in characterFileteredText {
            let numberOfOccurences = mostOccuringTexts[text] ?? 0
            mostOccuringTexts[text] = (numberOfOccurences + 1)
        }
        
        var textsWithMinimumFrequency = mostOccuringTexts.filter {$0.value > minFrequency}
        
        var textFilteredByThreshold = removeResultsUnderThreshold(0.75, texts: textsWithMinimumFrequency)
        
        print("most occuring \(textFilteredByThreshold)")
        
        var topResults: [(String, Int)] {
            var results = [(String, Int)]()
            for (element, frequency) in textFilteredByThreshold {
                results.append((element, frequency))
            }
            return results
        }
        
        if topResults.count > limit {
            let resultsSortedByFrequency = topResults.sorted{$0.1 > $1.1}
            return Array(resultsSortedByFrequency.prefix(limit))
        }
        
        return topResults
    }
    
    func getUpperLeftElements(_ cardElements: [CardElement]) -> [CardElement] {
        let sortedElements = cardElements.sorted {
            return ($0.frame.origin.y < $1.frame.origin.y) && ($0.frame.origin.x < $1.frame.origin.x)
        }
        
        guard let topLeftMostElement = sortedElements[safe: 0] else {
            return []
        }
        
        let topLeftElements = sortedElements.filter {topLeftMostElement.frame.intersects($0.frame)}
        return topLeftElements + [topLeftMostElement]
    }
    
    func getTopXTitles(_ limit: Int) -> [String] {
        let upperLeftElements = getUpperLeftElements(cardElements)
        let upperLeftElementText = upperLeftElements.map{$0.text}
        let results = getMostFrequentStringOccurences(upperLeftElementText, withResultsLimit: limit)
        return results.map {$0.0}
    }
    
    func removeSpecialCharsFromString(text: String) -> String {
        let okayChars = Set("abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLKMNOPQRSTUVWXYZ,-'")
        return text.filter {okayChars.contains($0)}
    }
    
    func clear() {
        cardElements = []
        frequencyFilteredText = []
        mostOccuringTexts = [:]
    }
}
