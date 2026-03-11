//
//  Item.swift
//  Tabi
//
//  Created by Akinalp Fidan on 11.03.2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
