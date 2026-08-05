//
//  Item.swift
//  MiroCloneiPad
//
//  Created by habil on 06/08/26.
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
