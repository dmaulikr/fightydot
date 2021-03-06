//
//  BaseEngine.swift
//  FightyDot
//
//  Created by Graham McRobbie on 29/12/2016.
//  Copyright © 2016 Graham McRobbie. All rights reserved.
//  
//  A basic nine men's morris engine.
//  This class handles the game logic and calls back to the relevent views.
//

import Foundation
import Firebase

class Engine {
    
    private var _p1: Player
    private var _p2: Player
    private var _board: Board
    
    private var _state: GameState = .PlacingPieces {
        didSet {
            if(_state != .TakingPiece && nextPlayer().type == .AI) {
                _view?.updateTips(state: .AITurn)
            } else {
                _view?.updateTips(state: _state)
            }
        }
    }
    weak private var _view: EngineDelegate?
    
    private var _currentPlayer: Player! {
        didSet {
            if let oldPlayer = oldValue {
                oldPlayer.isCurrentPlayer = false
            }
            _currentPlayer.isCurrentPlayer = true
        }
    }
    
    init(gameType: GameType, engineView: EngineDelegate) {
        _p1 = try! Player(name: Constants.PlayerData.defaultPvpP1Name, colour: .green, type: .humanLocal, isStartingPlayer: true, playerNum: PlayerNumber.p1, view: engineView.p1View)
        
        if(gameType == .PlayerVsPlayer) {
            _p2 = try! Player(name: Constants.PlayerData.defaultPvpP2Name, colour: .red, type: .humanLocal, isStartingPlayer: false, playerNum: PlayerNumber.p2, view: engineView.p2View)
        } else {
            _p2 = try! AIPlayer(name: Constants.PlayerData.defaultAIName, colour: .red, type: .AI, isStartingPlayer: false, playerNum: PlayerNumber.p2, view: engineView.p2View, thinkTime: 0.5)
        }
        
        _view = engineView
        _currentPlayer = _p1.isStartingPlayer ? _p1 : _p2
        _board = Board(view: engineView)
    }
    
    func handleNodeTapFor(nodeWithId nodeId: Int) throws {
        guard nodeId.isInIdRange() else {
            throw EngineError.InvalidId
        }
        
        // Prevent double taps/drags
        _board.disableNodes()
        
        switch(_state) {
        case .PlacingPieces:
            try placeNodeFor(player: _currentPlayer, nodeId: nodeId)
        case .TakingPiece:
            try takeNodeBelongingTo(player: nextPlayer(), nodeId: nodeId)
        default:
            throw EngineError.InvalidState
        }
    }
    
    func handleNodeDragged(from oldId: Int, to newId: Int) throws {
        guard oldId.isInIdRange() && newId.isInIdRange() else {
            throw EngineError.InvalidId
        }
        
        // Prevent double taps/drags
        _board.disableNodes()
        
        try moveNodeFor(player: _currentPlayer, from: oldId, to: newId)
    }
    
    func getMovablePositionsFor(nodeWithId id: Int) throws -> [Int]  {
        guard (id.isInIdRange()) else {
            throw EngineError.InvalidId
        }
        
        switch(_state) {
        case .MovingPieces:
            return (_board.getNode(withID: id)?.emptyNeighbours.map { $0.value.id})!
        case .FlyingPieces:
            return _board.getNodes(for: .none).map { $0.id }
        default:
            throw EngineError.InvalidState
        }
    }
    
    func reset() {
        resetPlayers()
        _board.reset()
        _state = .PlacingPieces
        _view?.updateTips(state: _state)
        _view?.playSound(fileName: Constants.Sfx.startGame, type: ".wav")
    }
    
    // For error reporting
    func uploadStateToFirebase(msg: String) {
        var paramDict = Dictionary<String, Any>()
        paramDict["state"] = "\(_state)"
        paramDict["msg"] = msg
        
        Analytics.logEvent(Constants.FirebaseEvents.engineState, parameters: paramDict)
        Analytics.logEvent(Constants.FirebaseEvents.boardState, parameters: _board.toDict())
        Analytics.logEvent(Constants.FirebaseEvents.playerOneState, parameters: _p1.toDict())
        Analytics.logEvent(Constants.FirebaseEvents.playerTwoState, parameters: _p2.toDict())
    }
    
    // MARK: - Private functions
    
    private func placeNodeFor(player: Player, nodeId: Int) throws {
        guard let node = _board.getNode(withID: nodeId) else {
            throw EngineError.InvalidId
        }
        
        let millFormed = player.playPiece(node: node)
        
        if (millFormed)  {
            _view?.playSound(fileName: Constants.Sfx.millFormed, type: ".wav")
            
            if(player.type == .humanLocal && nextPlayer().hasTakeableNodes) {
                try promptToTakePiece()
            }
        } else {
            _view?.playSound(fileName: Constants.Sfx.placePiece, type: ".wav")
            try nextTurn()
        }
    }
    
    private func promptToTakePiece() throws {
        _state = .TakingPiece
        try updateSelectableNodes()
    }
    
    private func updateSelectableNodes() throws {
        let selectableNodes = getSelectableNodes(state: _state)
        
        switch(_state) {
        case .PlacingPieces, .TakingPiece:
            _board.setNodesTappable(nodes: selectableNodes)
        case .MovingPieces, .FlyingPieces:
            _board.setNodesDraggable(nodes: selectableNodes)
        default:
            throw EngineError.InvalidState
        }
    }
    
    private func getSelectableNodes(state: GameState) -> [Node] {
        switch(state) {
        case .TakingPiece:
            return nextPlayer().takeableNodes
        case .MovingPieces, .FlyingPieces:
            return _currentPlayer.movableNodes
        default:
            return _board.getNodes(for: .none)
        }
    }
    
    private func takeNodeBelongingTo(player: Player, nodeId : Int) throws {
        guard let node = _board.getNode(withID: nodeId) else {
            throw EngineError.InvalidId
        }
        
        player.losePiece(node: node)
        _view?.playSound(fileName: Constants.Sfx.pieceLost, type: ".wav")
        
        try nextTurn()
    }
    
    private func nextTurn() throws {
        _state = nextPlayer().state
        
        if(_state == .GameOver) {
            _view?.gameWon(by: _currentPlayer)
        } else {
            switchPlayers()
            
            if(_currentPlayer.type != .AI) {
                try updateSelectableNodes()
            } else {
                makeMoveFor(aiPlayer: (_currentPlayer as? AIPlayer)!)
            }
        }
    }
    
    // Because the AI move is handled in a dispatch block, it cannot throw errors in Swift 3.
    // Therefore, error handling is done in the method itself, and fatal errors are returned
    // to the view immediately.
    private func makeMoveFor(aiPlayer: AIPlayer) {
        aiPlayer.processingState = .Thinking
        
        let opponent = nextPlayer()
        var bestMove: Move?
        
        DispatchQueue.main.asyncAfter(deadline: .now() + aiPlayer.artificialThinkTime) {
            
            // Get the move to make
            if(aiPlayer.hasPlayedNoPieces()) {
                let targetNode = aiPlayer.pickStartingNodeFrom(board: self._board)
                bestMove = Move(type: .PlacePiece, targetNodeId: targetNode.id)
            } else {
                do {
                    try bestMove = aiPlayer.getBestMove(board: self._board, opponent: self.nextPlayer())
                } catch {
                    self._view?.handleEngineError(logMsg: "Failed to calculate move for AI player. (\(error))")
                }
            }
            
            guard let moveToMake = bestMove else {
                self._view?.handleEngineError(logMsg: "Failed to unwrap move for AI player.")
                return
            }
            
            // Make the move
            switch (moveToMake.type) {
            case .PlacePiece:
                aiPlayer.processingState = .Placing
                do {
                    try self.placeNodeFor(player: aiPlayer, nodeId: moveToMake.targetNodeId)
                } catch {
                    self._view?.handleEngineError(logMsg: "Failed to place piece with id \(moveToMake.targetNodeId) for AI player. (\(error))")
                }
            case .MovePiece:
                aiPlayer.processingState = .Moving
                
                guard let destinationNodeId = moveToMake.destinationNodeId else {
                    self._view?.handleEngineError(logMsg: "Failed to get destination node for AI player.")
                    return
                }
                
                do {
                    try self.moveNodeFor(player: aiPlayer, from: moveToMake.targetNodeId, to: destinationNodeId)
                } catch {
                    self._view?.handleEngineError(logMsg: "Failed to move piece from \(moveToMake.targetNodeId) to \(destinationNodeId) for AI player. (\(error))")
                }
            }
            
            // Take a piece
            if(moveToMake.formsMill) {
                DispatchQueue.main.asyncAfter(deadline: .now() + aiPlayer.artificialThinkTime) {
                    aiPlayer.processingState = .TakingPiece
                    
                    if let nodeToTake = moveToMake.nodeToTakeId {
                        do {
                            try self.takeNodeBelongingTo(player: opponent, nodeId: nodeToTake)
                        } catch {
                            self._view?.handleEngineError(logMsg: "Failed to take piece \(nodeToTake) for AI player. (\(error))")

                        }
                    }
                }
            }
        }
    }
    
    private func moveNodeFor(player: Player, from oldId: Int, to newId: Int) throws {
        guard let oldNode = _board.getNode(withID: oldId) else {
            throw EngineError.InvalidId
        }
        
        guard let newNode = _board.getNode(withID: newId) else {
            throw EngineError.InvalidId
        }
        
        let millFormed = player.movePiece(from: oldNode, to: newNode)
        
        if (millFormed) {
            _view?.playSound(fileName: Constants.Sfx.millFormed, type: ".wav")
            
            if(player.type == .humanLocal && nextPlayer().hasTakeableNodes) {
                try promptToTakePiece()
            }
        } else {
            _view?.playSound(fileName: Constants.Sfx.placePiece, type: ".wav")
            try nextTurn()
        }
    }
    
    // Sometimes we want to look ahead to check the next player's properties
    // to check if we have a draw, can take a piece, etc.
    private func nextPlayer() -> Player {
        if(_currentPlayer === _p1) {
            return _p2
        } else {
            return _p1
        }
    }
    
    private func switchPlayers() {
        _currentPlayer = nextPlayer()
        
        if let aiPlayer = nextPlayer() as? AIPlayer {
            aiPlayer.processingState = .Waiting
        }
    }
    
    private func resetPlayers() {
        _p1.reset()
        _p2.reset()
        _currentPlayer = _p1.isStartingPlayer ? _p1 : _p2
    }
}
