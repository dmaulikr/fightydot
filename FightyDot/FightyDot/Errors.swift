//
//  Errors.swift
//  FightyDot
//
//  Created by Graham McRobbie on 29/12/2016.
//  Copyright © 2016 Graham McRobbie. All rights reserved.
//

import Foundation

enum AIError: Error {
    case FailedToGetDestinationNode
    case FailedToGetNodeToTake
    case FailedToGetTargetNode
}

enum EngineError: Error {
    case InvalidId
    case InvalidState
}

enum PlayerError: Error {
    case EmptyName
}

enum ViewError: Error {
    case MissingTag
}
