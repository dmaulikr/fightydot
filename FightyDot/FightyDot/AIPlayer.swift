//
//  AIPlayer.swift
//  Ananke
//
//  Created by Graham McRobbie on 19/02/2017.
//  Copyright © 2017 Graham McRobbie. All rights reserved.
//

import Foundation

class AIPlayer: Player {

    private var _processingState: AIPlayerState = .Waiting {
        didSet {
            view?.update(status: _processingState)
        }
    }
    
    private var _thinkTime: Double
    
    var processingState: AIPlayerState {
        get {
            return _processingState
        } set {
            _processingState = newValue
        }
    }
    
    var thinkTime: Double {
        get {
            return _thinkTime
        }
    }
    
    init(name: String, colour: PlayerColour, type: PlayerType, isStartingPlayer: Bool, playerNum: PlayerNumber, view: PlayerDelegate?, thinkTime: Double) throws {
        _processingState = .Waiting
        _thinkTime = thinkTime
        
        try super.init(name: name, colour: colour, type: type, isStartingPlayer: isStartingPlayer, playerNum: playerNum, view: view)
    }
    
    override func reset() {
        super.reset()
        _processingState = .Waiting
    }
    
    func pickNodeToPlaceFrom(board: Board) -> Node {
        let emptyNodes = board.getNodes(for: .none)
        
        // Since we have more nodes than pieces, there will always be an empty spot
        return emptyNodes.randomElement()!
    }
    
    func pickNodeToTakeFrom(takableNodes: [Node]) -> Node? {
        return takableNodes.randomElement()
    }
    
    
    func pickNodeToMove() -> Node? {
        return movableNodes.randomElement()
    }
    
    func pickSpotToMoveToFrom(validMoveSpots: [Int]) -> Int? {
        return validMoveSpots.randomElement()
    }
}
