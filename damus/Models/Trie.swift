//
//  Trie.swift
//  damus
//
//  Created by Terry Yiu on 6/26/23.
//

import Foundation

/// Tree data structure of all the substring permutations of a collection of strings optimized for searching for values of type V.
///
/// Each node in the tree can have child nodes.
/// Each node represents a single character in substrings, and each of its child nodes represent the subsequent character in those substrings.
///
/// A node that has no children mean that there are no substrings with any additional characters beyond the branch of letters leading up to that node.
///
/// A node that has values mean that there are strings that end in the character represented by the node and contain the substring represented by the branch of letters leading up to that node.
///
/// https://en.wikipedia.org/wiki/Trie
class Trie<V: Hashable> {
    private var children: [Character : Trie] = [:]

    /// Separate exact matches from strict substrings so that exact matches appear first in returned results.
    private var exactMatchValues = Set<V>()
    private var substringMatchValues = Set<V>()

    private var parent: Trie? = nil
}

extension Trie {
    var hasChildren: Bool {
        return !self.children.isEmpty
    }

    var hasValues: Bool {
        return !self.exactMatchValues.isEmpty || !self.substringMatchValues.isEmpty
    }

    /// Finds the branch that matches the specified key and returns the values from all of its descendant nodes.
    func find(key: String) -> [V] {
        var currentNode = self

        // Find branch with matching prefix.
        for char in key {
            if let child = currentNode.children[char] {
                currentNode = child
            } else {
                return []
            }
        }

        // Perform breadth-first search from matching branch and collect values from all descendants.
        var substringMatches = Set<V>(currentNode.substringMatchValues)
        var queue = Array(currentNode.children.values)

        while !queue.isEmpty {
            let node = queue.removeFirst()
            substringMatches.formUnion(node.exactMatchValues)
            substringMatches.formUnion(node.substringMatchValues)
            queue.append(contentsOf: node.children.values)
        }

        // Prioritize exact matches to be returned first, and then remove exact matches from the set of partial substring matches that are appended afterward.
        return Array(currentNode.exactMatchValues) + (substringMatches.subtracting(currentNode.exactMatchValues))
    }

    /// Inserts value of type V into this trie for the specified key. This function stores all substring endings of the key, not only the key itself.
    /// Runtime performance is O(n^2) and storage cost is O(n), where n is the number of characters in the key.
    func insert(key: String, value: V) {
        // Create root branches for each character of the key to enable substring searches instead of only just prefix searches.
        // Hence the nested loop.
        for i in 0..<key.count {
            var currentNode = self

            // Find branch with matching prefix.
            for char in key[key.index(key.startIndex, offsetBy: i)...] {
                if let child = currentNode.children[char] {
                    currentNode = child
                } else {
                    let child = Trie()
                    child.parent = currentNode
                    currentNode.children[char] = child
                    currentNode = child
                }
            }

            if i == 0 {
                currentNode.exactMatchValues.insert(value)
            } else {
                currentNode.substringMatchValues.insert(value)
            }
        }
    }

    /// Removes value of type V from this trie for the specified key.
    func remove(key: String, value: V) {
        for i in 0..<key.count {
            var currentNode = self

            var foundLeafNode = true

            // Find branch with matching prefix.
            for j in i..<key.count {
                let char = key[key.index(key.startIndex, offsetBy: j)]

                if let child = currentNode.children[char] {
                    currentNode = child
                } else {
                    foundLeafNode = false
                    break
                }
            }

            if foundLeafNode {
                currentNode.exactMatchValues.remove(value)
                currentNode.substringMatchValues.remove(value)

                // Clean up the tree if this leaf node no longer holds values or children.
                for j in (i..<key.count).reversed() {
                    if let parent = currentNode.parent, !currentNode.hasValues && !currentNode.hasChildren {
                        currentNode = parent
                        let char = key[key.index(key.startIndex, offsetBy: j)]
                        currentNode.children.removeValue(forKey: char)
                    }
                }
            }
        }
    }
}
