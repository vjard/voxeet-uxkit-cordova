//
//  CDVVoxeet.swift
//  HelloCordova
//
//  Created by Vincent Jardel on 07/02/2020.
//


@objcMembers class CDVVoxeet : CDVPlugin {
    
    private var consumerKey: String?
    private var consumerSecret: String?
    private var refreshAccessTokenID: String?
    private var refreshAccessTokenClosure: ((String?) -> Void)?
    
    override func pluginInitialize() {
        NotificationCenter.default.addObserver(self, selector: #selector(finishLaunching(_:)), name: UIApplication.didFinishLaunchingNotification, object: nil)
    }
    
    func finishLaunching(_ notification: Notification?) {
        let consumerKey = Bundle.main.object(forInfoDictionaryKey: "VOXEET_CORDOVA_CONSUMER_KEY") as? String
        let consumerKeyPref = commandDelegate.settings["VOXEET_CORDOVA_CONSUMER_KEY".lowercased()] as? String
        let consumerSecret = Bundle.main.object(forInfoDictionaryKey: "VOXEET_CORDOVA_CONSUMER_SECRET") as? String
        let consumerSecretPref = commandDelegate.settings["VOXEET_CORDOVA_CONSUMER_SECRET".lowercased()] as? String
        
        if consumerKey != nil && (consumerKey?.count ?? 0) != 0 && !(consumerKey == "null") && consumerSecret != nil && (consumerSecret?.count ?? 0) != 0 && !(consumerSecret == "null") {
            self.consumerKey = consumerKey
            self.consumerSecret = consumerSecret
            initialize(withConsumerKey: self.consumerKey, consumerSecret: self.consumerSecret)
        } else if consumerKeyPref != nil && (consumerKeyPref?.count ?? 0) != 0 && consumerSecretPref != nil && (consumerSecretPref?.count ?? 0) != 0 {
            self.consumerKey = consumerKeyPref
            self.consumerSecret = consumerSecretPref
            initialize(withConsumerKey: self.consumerKey, consumerSecret: self.consumerSecret)
        }
    }
    
    private func sendCDVResult(command: CDVInvokedUrlCommand?, error: NSError?) {
        if error == nil {
            self.commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command?.callbackId)
        } else {
            self.commandDelegate.send(CDVPluginResult(status: .error, messageAs: error?.description), callbackId: command?.callbackId)
        }
    }
    
    func initialize(_ command: CDVInvokedUrlCommand?) {
        if let consumerKey = command?.arguments[0] as? String,
            let consumerSecret = command?.arguments[1] as? String {
            self.consumerKey = consumerKey
            self.consumerSecret = consumerSecret
            initialize(withConsumerKey: consumerKey, consumerSecret: self.consumerSecret)
            commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command?.callbackId)
        } else {
            commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command?.callbackId)
        }
    }
    
    func initialize(withConsumerKey consumerKey: String?, consumerSecret: String?) {
        guard let consumerKey = self.consumerKey,
            let consumerSecret = self.consumerSecret else { return }
        
        VoxeetSDK.shared.initialize(consumerKey: consumerKey, consumerSecret: consumerSecret)
        VoxeetUXKit.shared.initialize()
        
        VoxeetSDK.shared.pushNotification.type = .callKit
    }
    
    func initializeToken(_ command: CDVInvokedUrlCommand?) {
        DispatchQueue.main.async(execute: {
            if let accessToken = command?.arguments[0] as? String {
                VoxeetSDK.shared.initialize(accessToken: accessToken, refreshTokenClosure: { tokenClosure in
                    if let refreshAccessTokenClosure = tokenClosure as? ((String?) -> Void) {
                        self.refreshAccessTokenClosure = refreshAccessTokenClosure
                    }
                    
                    let callBackRefresh = CDVPluginResult(status: .ok)
                    callBackRefresh?.keepCallback = true
                    self.commandDelegate.send(callBackRefresh, callbackId: self.refreshAccessTokenID)
                })
            }
            VoxeetUXKit.shared.initialize()
            
            VoxeetSDK.shared.pushNotification.type = .callKit
            
            self.commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command?.callbackId)
        })
    }
    
    func connect(_ command: CDVInvokedUrlCommand?) {
        let participant = command?.arguments[0] as? [String: Any]
        guard let externalId = participant?["externalId"] as? String,
            let name = participant?["name"] as? String,
            let avatarURL = participant?["avatarUrl"] as? String else { return }
        let user = VTUser(externalID: externalId, name: name, avatarURL: avatarURL)
        
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.session.connect(user: user) { error in
                self.sendCDVResult(command: command, error: error)
            }
        })
    }
    
    func disconnect(_ command: CDVInvokedUrlCommand?) {
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.session.disconnect(completion: { error in
                self.sendCDVResult(command: command, error: error)
            })
        })
    }
    
    func create(_ command: CDVInvokedUrlCommand?) {
        let options = command?.arguments[0] as? [String: Any?]
        
        var nativeOptions: [String: Any] = [:]
        if let alias = options?["alias"] {
            nativeOptions["conferenceAlias"] = alias
        }
        
        if let params = options?["params"] as? [String: Any] {
            var nativeOptionsParams: [String: Any] = [:]
            nativeOptionsParams["ttl"] = params["ttl"]
            nativeOptionsParams["rtcpMode"] = params["rtcpMode"]
            nativeOptionsParams["mode"] = params["mode"]
            nativeOptionsParams["videoCodec"] = params["videoCodec"]
            nativeOptions["params"] = nativeOptionsParams
            
            if let liveRecording = params["liveRecording"] {
                nativeOptions["metadata"] = ["liveRecording": liveRecording]
            }
        }
        
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.conference.create(parameters: nativeOptions, success: { response in
                self.commandDelegate.send(CDVPluginResult(status: .ok, messageAs: response), callbackId: command?.callbackId)
            }) { error in
                self.commandDelegate.send(CDVPluginResult(status: .error, messageAs: error.description), callbackId: command?.callbackId)
            }
        })
    }
    
    func join(_ command: CDVInvokedUrlCommand?) {
        guard let conferenceID = command?.arguments[0] as? String,
            let options = command?.arguments[1] as? [String: Any?] else { return }
        
        var nativeOptions: [String: Any] = [:]
        if let alias = options["alias"],
            let user = options["user"] as? [String: Any],
            let userType = user["type"] {
            nativeOptions["conferenceAlias"] = alias
            nativeOptions["participantType"] = userType
        }
        
        DispatchQueue.main.async(execute: {
            let video = VoxeetSDK.shared.conference.defaultVideo
            VoxeetSDK.shared.conference.join(conferenceID: conferenceID, video: video, userInfo: nativeOptions, success: { response in
                self.commandDelegate.send(CDVPluginResult(status: .ok, messageAs: response), callbackId: command?.callbackId)
            }, fail: { error in
                self.commandDelegate.send(CDVPluginResult(status: .error, messageAs: error.description), callbackId: command?.callbackId)
            })
        })
    }
    
    func leave(_ command: CDVInvokedUrlCommand?) {
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.conference.leave(completion: { error in
                if error == nil || (error as NSError?)?.code == -10002 {
                    self.commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command?.callbackId)
                } else {
                    self.commandDelegate.send(CDVPluginResult(status: .error, messageAs: error?.description), callbackId: command?.callbackId)
                }
            })
        })
    }
    
    func invite(_ command: CDVInvokedUrlCommand?) {
        guard let conferenceID = command?.arguments[0] as? String,
            let participants = command?.arguments[1] as? [AnyHashable] else { return }
        var userIDs: [String] = []
        
        for participant in participants {
            guard let participant = participant as? [String: Any] else {
                continue
            }
            if let externalId = participant["externalId"] as? String {
                userIDs.append(externalId)
            }
        }
        
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.conference.invite(conferenceID: conferenceID, externalIDs: userIDs) { error in
                self.sendCDVResult(command: command, error: error)
            }
        })
    }
    
    func sendBroadcastMessage(_ command: CDVInvokedUrlCommand?) {
        guard let message = command?.arguments[0] as? String else { return }
        
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.conference.broadcast(message: message) { error in
                self.sendCDVResult(command: command, error: error)
            }
        })
    }
    
    func appearMaximized(_ command: CDVInvokedUrlCommand?) {
        let enabled = (command?.arguments[0] as? NSNumber)?.boolValue ?? false
        
        DispatchQueue.main.async(execute: {
            VoxeetUXKit.shared.appearMaximized = enabled
            self.commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command?.callbackId)
        })
    }
    
    func setUIConfiguration(_ command: CDVInvokedUrlCommand?) {
        guard let jsonStr = command?.arguments[0] as? String,
            let jsonData = jsonStr.data(using: .utf8) else { return }
        var json: [String: Any]? = nil
        do {
            json = try JSONSerialization.jsonObject(with: jsonData, options: .mutableContainers) as? [String: Any]
        } catch let jsonError {
            print("Error Called by: \(#file), \(#function), line: \(#line), error: \(jsonError.localizedDescription)")
        }
    }
    
    func defaultBuilt(inSpeaker command: CDVInvokedUrlCommand?) {
        let enabled = (command?.arguments[0] as? NSNumber)?.boolValue ?? false
        
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.conference.defaultBuiltInSpeaker = enabled
            self.commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command?.callbackId)
        })
    }
    
    func defaultVideo(_ command: CDVInvokedUrlCommand?) {
        let enabled = (command?.arguments[0] as? NSNumber)?.boolValue ?? false
        
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.conference.defaultVideo = enabled
            self.commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command?.callbackId)
        })
    }
    
    func setTelecomMode(_ command: CDVInvokedUrlCommand?) {
        let enabled = (command?.arguments[0] as? NSNumber)?.boolValue ?? false
        
        DispatchQueue.main.async(execute: {
            VoxeetUXKit.shared.telecom = enabled
            self.commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command?.callbackId)
        })
    }
    
    func isAudio3DEnabled(_ command: CDVInvokedUrlCommand?) {
        let isAudio3D = VoxeetSDK.shared.conference.audio3D
        
        commandDelegate.send(CDVPluginResult(status: .ok, messageAs: isAudio3D), callbackId: command?.callbackId)
    }
    
    func isTelecomMode(_ command: CDVInvokedUrlCommand?) {
        let isTelecom = VoxeetConferenceKit.shared.telecom
        
        commandDelegate.send(CDVPluginResult(status: .ok, messageAs: isTelecom), callbackId: command?.callbackId)
    }
    
    func startVideo(_ command: CDVInvokedUrlCommand?) {
        //        let isDefaultFrontFacing = (command?.arguments[0] as? NSNumber)?.boolValue ?? false
        guard let user = VoxeetSDK.shared.session.user,
            let userId = user.id else { return }
        
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.conference.startVideo(userID: userId) { error in
                if error == nil {
                    self.commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command?.callbackId)
                } else {
                    self.commandDelegate.send(CDVPluginResult(status: .error, messageAs: error?.description), callbackId: command?.callbackId)
                }
            }
        })
    }
    
    func stopVideo(_ command: CDVInvokedUrlCommand?) {
        guard let user = VoxeetSDK.shared.session.user,
            let userId = user.id else { return }
        
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.conference.stopVideo(userID: userId) { error in
                self.sendCDVResult(command: command, error: error)
            }
        })
    }
    
    func switchCamera(_ command: CDVInvokedUrlCommand?) {
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.conference.switchCamera(completion: {
                self.commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command?.callbackId)
            })
        })
    }
    
    /*
     *  MARK: Recording
     */
    func startRecording(_ command: CDVInvokedUrlCommand?) {
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.conference.startRecording(fireInterval: 0) { error in
                self.sendCDVResult(command: command, error: error)
            }
        })
    }
    
    func stopRecording(_ command: CDVInvokedUrlCommand?) {
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.conference.stopRecording(completion: { error in
                self.sendCDVResult(command: command, error: error)
            })
        })
    }
    
    /*
     *  MARK: Oauth2 helpers
     */
    func refreshAccessTokenCallback(_ command: CDVInvokedUrlCommand?) {
        refreshAccessTokenID = command?.callbackId
        // No need to be resolved because it's gonna be resolved in `initializeToken`
    }
    
    func onAccessTokenOk(_ command: CDVInvokedUrlCommand?) {
        guard let accessToken = command?.arguments[0] as? String else { return }
        if let refreshAccessTokenClosure = refreshAccessTokenClosure {
            refreshAccessTokenClosure(accessToken)
            commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command?.callbackId)
        }
    }
    
    func onAccessTokenKo(_ command: CDVInvokedUrlCommand?) {
        if let refreshAccessTokenClosure = refreshAccessTokenClosure {
            refreshAccessTokenClosure(nil)
            commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command?.callbackId)
        }
    }
    
    /*
     *  MARK: Android compatibility methods
     */
    func broadcast(_ command: CDVInvokedUrlCommand?) {
        join(command)
    }
    
    func screenAutoLock(_ command: CDVInvokedUrlCommand?) {
        // Android compatibility
        commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command?.callbackId)
    }
    
    func isUserLogged(in command: CDVInvokedUrlCommand?) {
        // Android compatibility
        let isLogIn = VoxeetSDK.shared.session.state == .connected
        commandDelegate.send(CDVPluginResult(status: .ok, messageAs: isLogIn), callbackId: command?.callbackId)
    }
    
    func check(forAwaitingConference command: CDVInvokedUrlCommand?) {
        // Android compatibility
        commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command?.callbackId)
    }
    
    /*
     *  MARK: Deprecated methods
     */
    
    func startConference(_ command: CDVInvokedUrlCommand?) {
        // Deprecated
        guard let confAlias = command?.arguments[0] as? String,
            let participants = command?.arguments[1] as? [AnyHashable] else { return }
        var userIDs: [String] = []
        
        for participant in participants {
            guard let participant = participant as? [String: Any] else {
                continue
            }
            if let object = participant["externalId"] as? String {
                userIDs.append(object)
            }
        }
        
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.conference.create(
                parameters: ["conferenceAlias": confAlias],
                success: { response in
                    guard let confID = response?["conferenceId"] as? String,
                        let isNew = response?["isNew"] as? Bool else { return }
                    
                    let video = VoxeetSDK.shared.conference.defaultVideo
                    VoxeetSDK.shared.conference.join(conferenceID: confID, video: video, userInfo: nil, success: { response in
                        #warning("Check if CDVResult needs response parameter")
//                        self.commandDelegate.send(CDVPluginResult(status: .ok, messageAs: response), callbackId: command?.callbackId)
                        self.commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command?.callbackId)
                    }, fail: { error in
                        self.commandDelegate.send(CDVPluginResult(status: .error, messageAs: error.description), callbackId: command?.callbackId)
                    })
                    
                    if isNew {
                        VoxeetSDK.shared.conference.invite(conferenceID: confID, externalIDs: userIDs) { error in
                            if let error = error {
                                print(error.description)
                            }
                        }
                    }
            }, fail: { error in
                self.commandDelegate.send(CDVPluginResult(status: .error,
                                                          messageAs: error.description),
                                          callbackId: command?.callbackId)
            })
        })
    }
    
    func stopConference(_ command: CDVInvokedUrlCommand?) {
        // Deprecated
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.conference.leave(completion: { error in
                self.sendCDVResult(command: command, error: error)
            })
        })
    }
    
    func openSession(_ command: CDVInvokedUrlCommand?) {
        // Deprecated
        guard let participant = command?.arguments[0] as? [String: Any],
            let participantExternalId = participant["externalId"] as? String,
            let participantName = participant["name"] as? String,
            let participantAvatarURL = participant["avatarUrl"] as? String else { return }
        
        let user = VTUser(externalID: participantExternalId,
                          name: participantName,
                          avatarURL: participantAvatarURL)
        
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.session.connect(user: user) { error in
                self.sendCDVResult(command: command, error: error)
            }
        })
    }
    
    func closeSession(_ command: CDVInvokedUrlCommand?) {
        // Deprecated
        DispatchQueue.main.async(execute: {
            VoxeetSDK.shared.session.disconnect(completion: { error in
                self.sendCDVResult(command: command, error: error)
            })
        })
    }
}
