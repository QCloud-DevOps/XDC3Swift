//
//  XinfinAccount.swift
//  XDC
//
// Created by Developer on 15/06/21.
//

import Foundation

protocol XinfinAccountProtocol {
    var address: XinfinAddress { get }
    
    // For Keystore handling
    init?(keyStorage: XinfinKeyStorageProtocol, keystorePassword: String) throws
    static func create(keyStorage: XinfinKeyStorageProtocol, keystorePassword password: String) throws -> XinfinAccount
    
    // For non-Keystore formats. This is not recommended, however some apps may wish to implement their own storage.
    init(keyStorage: XinfinKeyStorageProtocol) throws
    
    func sign(data: Data) throws -> Data
    func sign(hash: String) throws -> Data
    func sign(hex: String) throws -> Data
    func sign(message: Data) throws -> Data
    func sign(message: String) throws -> Data
    func sign(_ transaction: XinfinTransaction) throws -> SignedTransaction
}

public enum XinfinAccountError: Error {
    case createAccountError
    case loadAccountError
    case signError
}

public class XinfinAccount: XinfinAccountProtocol {
    private let privateKeyData: Data
    private let publicKeyData: Data
    
    public lazy var publicKey: String = {
        return self.publicKeyData.web3.hexString
    }()
    public lazy var privateKey: String = {
        return self.privateKeyData.web3.hexString
    }()
    
    public lazy var address: XinfinAddress = {
        return KeyUtil.generateAddress(from: self.publicKeyData)
    }()
    
    required public init(keyStorage: XinfinKeyStorageProtocol, keystorePassword password: String) throws {
        
        do {
            let data = try keyStorage.loadPrivateKey()
            if let decodedKey = try? KeystoreUtil.decode(data: data, password: password) {
                self.privateKeyData = decodedKey
                self.publicKeyData = try KeyUtil.generatePublicKey(from: decodedKey)
            } else {
                print("Error decrypting key data")
                throw XinfinAccountError.loadAccountError
            }
        } catch {
           throw XinfinAccountError.loadAccountError
        }
    }
    
    required public init(keyStorage: XinfinKeyStorageProtocol) throws {
        do {
            let data = try keyStorage.loadPrivateKey()
            self.privateKeyData = data
            self.publicKeyData = try KeyUtil.generatePublicKey(from: data)
        } catch {
            throw XinfinAccountError.loadAccountError
        }
    }
    
    public static func create(keyStorage: XinfinKeyStorageProtocol, keystorePassword password: String) throws -> XinfinAccount {
        guard let privateKey = KeyUtil.generatePrivateKeyData() else {
            throw XinfinAccountError.createAccountError
        }
        
        do {
            let encodedData = try KeystoreUtil.encode(privateKey: privateKey, password: password)
            try keyStorage.storePrivateKey(key: encodedData)
            return try self.init(keyStorage: keyStorage, keystorePassword: password)
        } catch {
            throw XinfinAccountError.createAccountError
        }
    }
    
    public func sign(data: Data) throws -> Data {
        return try KeyUtil.sign(message: data, with: self.privateKeyData, hashing: true)
    }
    
    public func sign(hex: String) throws -> Data {
        if let data = Data.init(hex: hex) {
            return try KeyUtil.sign(message: data, with: self.privateKeyData, hashing: true)
        } else {
            throw XinfinAccountError.signError
        }
    }
    
    public func sign(hash: String) throws -> Data {
        if let data = hash.web3.xdcData {
            return try KeyUtil.sign(message: data, with: self.privateKeyData, hashing: false)
        } else {
            throw XinfinAccountError.signError
        }
    }
    
    public func sign(message: Data) throws -> Data {
        return try KeyUtil.sign(message: message, with: self.privateKeyData, hashing: false)
    }
    
    public func sign(message: String) throws -> Data {
        if let data = message.data(using: .utf8) {
            return try KeyUtil.sign(message: data, with: self.privateKeyData, hashing: true)
        } else {
            throw XinfinAccountError.signError
        }
    }
    
    public func signMessage(message: Data) throws -> String {
        let prefix = "\u{19}Xinfin Signed Message:\n\(String(message.count))"
        guard var data = prefix.data(using: .ascii) else {
            throw XinfinAccountError.signError
        }
        data.append(message)
        let hash = data.web3.keccak256
        
        guard var signed = try? self.sign(message: hash) else {
            throw XinfinAccountError.signError
            
        }
        
        // Check last char (v)
        guard var last = signed.popLast() else {
            throw XinfinAccountError.signError
            
        }
        
        if last < 27 {
            last += 27
        }
        
        signed.append(last)
        return signed.web3.hexString
    }
    
    public func signMessage(message: TypedData) throws -> String {
        let hash = try message.signableHash()
        
        guard var signed = try? self.sign(message: hash) else {
            throw XinfinAccountError.signError
            
        }
        
        // Check last char (v)
        guard var last = signed.popLast() else {
            throw XinfinAccountError.signError
            
        }
        
        if last < 27 {
            last += 27
        }
        
        signed.append(last)
        return signed.web3.hexString
    }
}
