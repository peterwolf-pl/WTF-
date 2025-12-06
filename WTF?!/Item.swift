//
//  Item.swift
//  WTF?!
//
//  Created by Peter Wolf on 06/12/2025.
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
