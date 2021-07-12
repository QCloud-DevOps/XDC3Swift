//
//  XinfinClient+Static.swift
//  XDC
//
// Created by Developer on 15/06/21.
//

import Foundation

public extension ABIFunction {
    func execute(withClient client: XinfinClientProtocol, account: XinfinAccount, completion: @escaping((XinfinClientError?, String?) -> Void)) {
        
        guard let tx = try? self.transaction() else {
            return completion(XinfinClientError.encodeIssue, nil)
        }
        
        
        client.eth_sendRawTransaction(tx, withAccount: account) { (error, res) in
            guard let res = res, error == nil else {
                return completion(XinfinClientError.unexpectedReturnValue, nil)
            }
            
            return completion(nil, res)
        }
        
    }
    
    func call<T: ABIResponse>(withClient client: XinfinClientProtocol, responseType: T.Type, block: XinfinBlock = .Latest, completion: @escaping((XinfinClientError?, T?) -> Void)) {
        
        guard let tx = try? self.transaction() else {
            return completion(XinfinClientError.encodeIssue, nil)
        }
        
        client.eth_call(tx, block: block) { (error, res) in
            guard let res = res, error == nil else {
                return completion(XinfinClientError.unexpectedReturnValue, nil)
            }
        //    print(res)
            guard let response = (try? T(data: res)) else {
                return completion(XinfinClientError.decodeIssue, nil)
            }
        //    print(response)
            return completion(nil, response)
        }
    }
}

public struct EventFilter {
    public let type: ABIEvent.Type
    public let allowedSenders: [XinfinAddress]
    
    public init(type: ABIEvent.Type,
                allowedSenders: [XinfinAddress]) {
        self.type = type
        self.allowedSenders = allowedSenders
    }
}

public extension XinfinClient {
    typealias EventsCompletion = (XinfinClientError?, [ABIEvent], [XinfinLog]) -> Void
    func getEvents(addresses: [XinfinAddress]?,
                   orTopics: [[String]?]?,
                   fromBlock: XinfinBlock,
                   toBlock: XinfinBlock,
                   matching matches: [EventFilter],
                   completion: @escaping EventsCompletion) {
        self.eth_getLogs(addresses: addresses, orTopics: orTopics, fromBlock: fromBlock, toBlock: toBlock) { [weak self] (error, logs) in
            self?.handleLogs(error, logs, matches, completion)
        }
    }
    
    func getEvents(addresses: [XinfinAddress]?,
                   orTopics: [[String]?]?,
                   fromBlock: XinfinBlock,
                   toBlock: XinfinBlock,
                   eventTypes: [ABIEvent.Type],
                   completion: @escaping EventsCompletion) {
        let unfiltered = eventTypes.map { EventFilter(type: $0, allowedSenders: []) }
        self.eth_getLogs(addresses: addresses, orTopics: orTopics, fromBlock: fromBlock, toBlock: toBlock) { [weak self] (error, logs) in
            self?.handleLogs(error, logs, unfiltered, completion)
        }
    }

    func getEvents(addresses: [XinfinAddress]?,
                   topics: [String?]?,
                   fromBlock: XinfinBlock,
                   toBlock: XinfinBlock,
                   eventTypes: [ABIEvent.Type],
                   completion: @escaping EventsCompletion) {
        let unfiltered = eventTypes.map { EventFilter(type: $0, allowedSenders: []) }
        getEvents(addresses: addresses,
                  topics: topics,
                  fromBlock: fromBlock,
                  toBlock: toBlock,
                  matching: unfiltered,
                  completion: completion)
    }
    
    func getEvents(addresses: [XinfinAddress]?,
                   topics: [String?]?,
                   fromBlock: XinfinBlock,
                   toBlock: XinfinBlock,
                   matching matches: [EventFilter],
                   completion: @escaping EventsCompletion) {
        
        self.eth_getLogs(addresses: addresses, topics: topics, fromBlock: fromBlock, toBlock: toBlock) { [weak self] (error, logs) in
            self?.handleLogs(error, logs, matches, completion)
        }
    }
        
    private func handleLogs(_ error: XinfinClientError?,
                            _ logs: [XinfinLog]?,
                            _ matches: [EventFilter],
                            _ completion: EventsCompletion) {
        if let error = error {
            return completion(error, [], [])
        }
        
        guard let logs = logs else { return completion(nil, [], []) }
        
        var events: [ABIEvent] = []
        var unprocessed: [XinfinLog] = []
        
        var filtersBySignature: [String: [EventFilter]] = [:]
        for filter in matches {
            if let sig = try? filter.type.signature() {
                var filters = filtersBySignature[sig, default: [EventFilter]()]
                filters.append(filter)
                filtersBySignature[sig] = filters
            }
        }
        
        let parseEvent: (XinfinLog, ABIEvent.Type) -> ABIEvent? = { log, eventType in
            let topicTypes = eventType.types.enumerated()
                .filter { eventType.typesIndexed[$0.offset] == true }
                .compactMap { $0.element }
            
            let dataTypes = eventType.types.enumerated()
                .filter { eventType.typesIndexed[$0.offset] == false }
                .compactMap { $0.element }
            
            guard let data = try? ABIDecoder.decodeData(log.data, types: dataTypes, asArray: true) else {
                return nil
            }
            
            guard data.count == dataTypes.count else {
                return nil
            }
            
            let rawTopics = Array(log.topics.dropFirst())
            
            guard let parsedTopics = (try? zip(rawTopics, topicTypes).map { pair in
                try ABIDecoder.decodeData(pair.0, types: [pair.1])
                }) else {
                    return nil
            }
            
            guard let eventOpt = ((try? eventType.init(topics: parsedTopics.flatMap { $0 }, data: data, log: log)) as ABIEvent??), let event = eventOpt else {
                return nil
            }
            
            return event
        }
        
        for log in logs {
            guard let signature = log.topics.first,
                let filters = filtersBySignature[signature] else {
                    unprocessed.append(log)
                    continue
            }
            
            for filter in filters {
                let allowedSenders = Set(filter.allowedSenders)
                if allowedSenders.count > 0 && !allowedSenders.contains(log.address) {
                    unprocessed.append(log)
                } else if let event = parseEvent(log, filter.type) {
                    events.append(event)
                } else {
                    unprocessed.append(log)
                }
            }
        }
        
        return completion(error, events, unprocessed)
    }
}
